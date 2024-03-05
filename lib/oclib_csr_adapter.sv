
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oclib_csr_adapter
  #(
    parameter        type CsrInType = oclib_pkg::csr_32_s,
    parameter        type CsrInFbType = oclib_pkg::csr_32_fb_s,
    parameter        type CsrInProtocol = oclib_pkg::csr_32_s,
    parameter        type CsrOutType = oclib_pkg::csr_32_s,
    parameter        type CsrOutFbType = oclib_pkg::csr_32_fb_s,
    parameter        type CsrOutProtocol = oclib_pkg::csr_32_s,
    parameter bit    UseClockOut = oclib_pkg::False,
    parameter int    SyncCycles = 3,
    parameter bit    ResetSync = UseClockOut,
    parameter int    ResetPipeline = 0,
    parameter int    Spaces = 1,
    parameter [31:0] AnswerToBlock = oclib_pkg::BcBlockIdAny,
    parameter [3:0]  AnswerToSpace = oclib_pkg::BcSpaceIdAny, // a base space, if we have multiple address spaces
    // CsrIntType -- the internal normalized datapath type
    // now these are borderline "localparam" but if you're really careful and you are using
    // this to cross clocks or serialize a csr_64 it can work.  But most outputs will only
    // work with csr_32 there (and have assertions to check)
    parameter        type CsrIntType = oclib_pkg::csr_32_s,
    parameter        type CsrIntFbType = oclib_pkg::csr_32_fb_s,
    parameter bit    EnableILA = oclib_pkg::False
    )
  (
   input  clock,
   input  reset,
   input  clockOut = 1'b0,
   input  resetOut = 1'b0,
   input  CsrInType in,
   output CsrInFbType inFb,
   // OK so this is kinda ugly because we break the OC standard of using unpacked dimensions
   // when we have arrays of stuff.  The issue is that this block USUALLY doesn't have Spaces>1,
   // and it would be ugly to require the caller to declare a 1-entry unpacked dimension, which
   // then is the wrong thing to plug into the next block... i.e. Verilog should have made it
   // that "type X out [0]" is the same as "type X out" (or can be automatically converted).
   // Which is how unpacked dimensions work, i.e. you can plug "type X [0:0] out" into "type X out",
   // so we use that here.  Anyway it will compile error when used the other way.  Just copy/paste
   // existing code that uses this module to fan-out, close your eyes, and think of England
   output CsrOutType [Spaces-1:0] out,
   input  CsrOutFbType [Spaces-1:0] outFb
   );

  // do some muxing of clocks and resets based on the situation.  for each clock we sort out,
  // we also do a reset.  If we've been told to sync reset we do that for all clocks, and if
  // we are trusting a clock, we are trusting the matching reset.

  logic   clockInMuxed;
  logic   resetInSync;
  if (UseClockOut && ((`OC_TYPES_EQUAL(CsrInType, oclib_pkg::bc_async_8b_bidi_s)) ||
                      (`OC_TYPES_EQUAL(CsrInType, oclib_pkg::bc_async_1b_bidi_s)))) begin
    // If we've been given a clockOut, and the input bus is async, then we'll just use
    // clockOut anywhere we need a clock, to try and not stretch the clockIn domain
    assign clockInMuxed = clockOut;
    oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
    uRESET_IN (.clock(clockInMuxed), .in(resetOut), .out(resetInSync));
  end
  else begin
    assign clockInMuxed = clock;
    oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
    uRESET_IN (.clock(clockInMuxed), .in(reset), .out(resetInSync));
  end

  logic   clockOutMuxed;
  logic   resetOutSync;
  if (UseClockOut) begin
    assign clockOutMuxed = clockOut;
    oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
    uRESET_OUT (.clock(clockOutMuxed), .in(resetOut), .out(resetOutSync));
  end
  else begin
    assign clockOutMuxed = clock;
    assign resetOutSync = resetInSync;
  end

  if ((`OC_TYPES_EQUAL(CsrInType, CsrOutType)) && !UseClockOut && (Spaces==1)) begin : NOCONV
    assign out = in;
    assign inFb = outFb;
  end
  else begin
    // OK, we are doing some kind of conversion...

    // first we normalize incoming bus to CsrIntType

    CsrIntType inNormal;
    CsrIntFbType inNormalFb;

    if (`OC_TYPES_EQUAL(CsrInType, CsrIntType)) begin
      // we actually need to take care of converting 32/64 bit here
      assign inNormal = in;
      assign inFb = inNormalFb;
    end

    // OK, so we are converting input to csr_32_s ... is this a byte channel?
    else if ((`OC_TYPES_EQUAL(CsrInType, oclib_pkg::bc_async_8b_bidi_s)) ||
             (`OC_TYPES_EQUAL(CsrInType, oclib_pkg::bc_async_1b_bidi_s)) ||
             (`OC_TYPES_EQUAL(CsrInType, oclib_pkg::bc_8b_bidi_s))) begin

      // Convert the BC to a normalized CSR

      oclib_bc_to_csr #(.BcType(CsrInType),
                        .CsrType(CsrIntType), .CsrFbType(CsrIntFbType))
      uBC_TO_CSR (.clock(clockInMuxed), .reset(resetInSync),
                  .bcIn(in), .bcOut(inFb),
                  .csr(inNormal), .csrFb(inNormalFb));
    end

    // it's not CsrIntType, it's not a byte channel, I give up
    else begin
      `OC_STATIC_ERROR($sformatf("Don't know how to convert CSR from type: %s", $typename(CsrInType)));
    end

    // do a clock crossing, if required

    CsrIntType inSync;
    CsrIntFbType inSyncFb;
    // remember, if the incoming bus was async, and we were given clockOut, we already put
    // it onto clockOut (via clockInMuxed) above...
    if (UseClockOut && !((`OC_TYPES_EQUAL(CsrInType, oclib_pkg::bc_async_8b_bidi_s)) ||
                         (`OC_TYPES_EQUAL(CsrInType, oclib_pkg::bc_async_1b_bidi_s)))) begin
      oclib_csr_synchronizer #(.SyncCycles(SyncCycles),
                               .UseResetIn(oclib_pkg::True), .UseResetOut(oclib_pkg::True),
                               .CsrType(CsrIntType), .CsrFbType(CsrIntFbType))
      uCSR_SYNC (.clockIn(clockInMuxed), .resetIn(resetInSync),
                 .csrIn(inNormal), .csrInFb(inNormalFb),
                 .clockOut(clockOutMuxed), .resetOut(resetOutSync),
                 .csrOut(inSync), .csrOutFb(inSyncFb));
    end
    else begin
      assign inSync = inNormal;
      assign inNormalFb = inSyncFb;
    end

    // split based on Spaces, if required
    CsrIntType [Spaces-1:0] inSpaces;
    CsrIntFbType [Spaces-1:0] inSpacesFb;
    logic [3:0] spaceSelect;
    logic [Spaces-1:0] csrSelect;

    always_ff @(posedge clockOutMuxed) begin
      for (int o=0; o<Spaces; o++) begin
        csrSelect[o] <= (inSync.space == o);
      end
      spaceSelect <= inSync.space;
    end

    always_comb begin
      for (int o=0; o<Spaces; o++) begin
        inSpaces[o] = inSync;
        inSpaces[o].write = inSync.write && csrSelect[o];
        inSpaces[o].read = inSync.read && csrSelect[o];
      end
      inSyncFb = inSpacesFb[spaceSelect];
    end

    if (EnableILA) begin
    `OC_DEBUG_ILA(uILA, clock, 8192, 128, 32,
                  { in, inFb, inSync.write, inSync.read, csrSelect },
                  { resetInSync, resetOutSync,
                    in.valid, in.ready, inFb.valid, inFb.ready,
                    out[0].read, out[0].write, out[1].read, out[1].write,
                    outFb[0].ready, outFb[1].ready
                    });
    end

    // convert from internal to output format

    for (genvar o=0; o<Spaces; o++) begin : spaces

      if (`OC_TYPES_EQUAL(CsrOutType, CsrIntType)) begin
        always_comb begin
          out[o] = inSpaces[o];
          inSpacesFb[o] = outFb[o];
        end
      end // if (`OC_TYPES_EQUAL(CsrOutType, CsrIntType)) begin

      else if (`OC_TYPES_EQUAL(CsrOutType, oclib_pkg::drp_s)) begin
        `OC_STATIC_ASSERT(`OC_TYPES_EQUAL(CsrIntType, oclib_pkg::csr_32_s)); // DRP needs standard CsrIntType
        oclib_csr_to_drp #(.AnswerToBlock(AnswerToBlock), .AnswerToSpace(AnswerToSpace))
        uCSR_TO_DRP (.clock(clockOutMuxed), .reset(resetOutSync),
                     .csr(inSpaces[o]), .csrFb(inSpacesFb[o]),
                     .drp(out[o]), .drpFb(outFb[o]));
      end // if (`OC_TYPES_EQUAL(CsrOutType, oclib_pkg::drp_s)) begin

      else if (`OC_TYPES_EQUAL(CsrOutType, oclib_pkg::apb_s)) begin
        `OC_STATIC_ASSERT(`OC_TYPES_EQUAL(CsrIntType, oclib_pkg::csr_32_s)); // APB needs standard CsrIntType
        oclib_csr_to_apb #(.AnswerToBlock(AnswerToBlock), .AnswerToSpace(AnswerToSpace))
        uCSR_TO_APB (.clock(clockOutMuxed), .reset(resetOutSync),
                     .csr(inSpaces[o]), .csrFb(inSpacesFb[o]),
                     .apb(out[o]), .apbFb(outFb[o]));
      end // if (`OC_TYPES_EQUAL(CsrOutType, oclib_pkg::apb_s)) begin

      else if (`OC_TYPES_EQUAL(CsrOutType, oclib_pkg::axil_32_s)) begin
        `OC_STATIC_ASSERT(`OC_TYPES_EQUAL(CsrIntType, oclib_pkg::csr_32_s)); // AXIL needs standard CsrIntType
        oclib_csr_to_axil #(.AnswerToBlock(AnswerToBlock), .AnswerToSpace(AnswerToSpace))
        uCSR_TO_AXIL (.clock(clockOutMuxed), .reset(resetOutSync),
                      .csr(inSpaces[o]), .csrFb(inSpacesFb[o]),
                      .axil(out[o]), .axilFb(outFb[o]));
      end // if (`OC_TYPES_EQUAL(CsrOutType, oclib_pkg::axil_32_s)) begin

      else begin
        `OC_STATIC_ERROR($sformatf("Don't know how to convert CSR to type: %s", $typename(CsrOutType)));
      end

    end // block: out

  end // else: !if(type(CsrInType) == type(CsrOutType))

  // Some tools have issues with this stuff. so let's do some sanity checks (this also makes the "types"
  // visible in waveform tools...)

  localparam int     CsrInTypeW = $bits(CsrInType);
  localparam int     CsrInFbTypeW = $bits(CsrInFbType);
  localparam int     CsrInProtocolW = $bits(CsrInProtocol);
  localparam int     CsrOutTypeW = $bits(CsrOutType);
  localparam int     CsrOutFbTypeW = $bits(CsrOutFbType);
  localparam int     CsrOutProtocolW = $bits(CsrOutProtocol);

  `OC_STATIC_ASSERT(CsrInTypeW == $bits(in));
  `OC_STATIC_ASSERT(CsrInFbTypeW == $bits(inFb));
  `OC_STATIC_ASSERT(CsrOutTypeW == $bits(out[0]));
  `OC_STATIC_ASSERT(CsrOutFbTypeW == $bits(outFb[0]));

  `OC_STATIC_ASSERT(`OC_TYPES_EQUAL(CsrInType,CsrInType));
  `OC_STATIC_ASSERT(`OC_TYPES_EQUAL(CsrInFbType,CsrInFbType));

  // You'd think this would be in oclib_pkg, but generated code must be in a module

  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::bc_8b_bidi_s,       oclib_pkg::bc_8b_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::bc_8b_bidi_s,       oclib_pkg::bc_async_8b_bidi_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::bc_8b_s,            oclib_pkg::bc_async_8b_bidi_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::bc_async_8b_bidi_s, oclib_pkg::bc_async_8b_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::bc_async_8b_bidi_s, oclib_pkg::csr_32_s));

  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::csr_32_s,           oclib_pkg::csr_32_tree_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::csr_32_tree_s,      oclib_pkg::csr_32_noc_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::csr_32_noc_s,       oclib_pkg::csr_32_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::csr_32_s,           oclib_pkg::axil_32_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::csr_32_s,           oclib_pkg::drp_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::csr_32_s,           oclib_pkg::apb_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::drp_s,              oclib_pkg::axil_32_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::drp_s,              oclib_pkg::apb_s));
  `OC_STATIC_ASSERT(`OC_TYPES_NOTEQUAL(oclib_pkg::apb_s,              oclib_pkg::axil_32_s));

endmodule // oclib_csr_adapter
