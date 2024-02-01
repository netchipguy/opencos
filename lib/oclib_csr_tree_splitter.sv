
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oclib_csr_tree_splitter
  #(
    parameter         type CsrInType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrInFbType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrOutType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrOutFbType = oclib_pkg::bc_8b_bidi_s,
    parameter integer Outputs = 8,
    parameter integer InputBufferStages = 0,
    parameter integer OutputBufferStages = 0,
    parameter integer OutputBufferStagesEach [Outputs-1:0] = '{ Outputs { OutputBufferStages } },
    parameter [31:0]  OutputBlockIdKey [Outputs-1:0]  = '{ Outputs { 32'hffffffff } }, // default is same as output
    parameter [31:0]  OutputBlockIdMask [Outputs-1:0]  = '{ Outputs { 32'h00000000 } }, // default is same as output
    parameter bit     UseClockOut = oclib_pkg::False,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = UseClockOut,
    parameter integer ResetPipeline = 0,
    parameter bit     UseCsrSelect = oclib_pkg::False
    )
  (
   input        clock,
   input        reset,
   input        clockOut = 1'b0,
   input        resetOut = 1'b0,
   input        csrSelect = 1'b1,
   input        CsrInType in,
   output       CsrInFbType inFb,
   output       CsrOutType out [Outputs-1:0],
   input        CsrOutFbType outFb [Outputs-1:0],
   output logic resetRequest
  );

  // synchronize/pipeline reset as needed
  logic                            resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  localparam bit InputIsCsr = ((type(CsrInType) == type(oclib_pkg::csr_32_s)) ||
                               (type(CsrInType) == type(oclib_pkg::csr_32_noc_s)) ||
                               (type(CsrInType) == type(oclib_pkg::csr_32_tree_s)) ||
                               (type(CsrInType) == type(oclib_pkg::csr_64_s)));
  localparam bit InputIsBc = ((type(CsrInType) == type(oclib_pkg::bc_async_8b_bidi_s)) ||
                              (type(CsrInType) == type(oclib_pkg::bc_async_1b_bidi_s)) ||
                              (type(CsrInType) == type(oclib_pkg::bc_8b_bidi_s)));
  localparam bit InputIsAsync = ((type(CsrInType) == type(oclib_pkg::bc_async_8b_bidi_s)) ||
                                 (type(CsrInType) == type(oclib_pkg::bc_async_1b_bidi_s)));
  localparam bit OutputIsCsr = ((type(CsrOutType) == type(oclib_pkg::csr_32_s)) ||
                                (type(CsrOutType) == type(oclib_pkg::csr_32_noc_s)) ||
                                (type(CsrOutType) == type(oclib_pkg::csr_32_tree_s)) ||
                                (type(CsrOutType) == type(oclib_pkg::csr_64_s)));
  localparam bit OutputIsBc = ((type(CsrOutType) == type(oclib_pkg::bc_async_8b_bidi_s)) ||
                               (type(CsrOutType) == type(oclib_pkg::bc_async_1b_bidi_s)) ||
                               (type(CsrOutType) == type(oclib_pkg::bc_8b_bidi_s)));
  localparam bit OutputIsAsync = ((type(CsrOutType) == type(oclib_pkg::bc_async_8b_bidi_s)) ||
                                  (type(CsrOutType) == type(oclib_pkg::bc_async_1b_bidi_s)));
  localparam bit InputUsesClockOut = (InputIsAsync && UseClockOut);
  localparam bit NeedSynchronizer = (UseClockOut && !InputIsAsync);

  logic   useClockOut;
  assign useClockOut = (UseClockOut ? clockOut : clock);

  logic   useClockIn;
  assign useClockIn = (InputUsesClockOut ? clockOut : clock);

  if ((type(CsrInType) == type(CsrOutType)) && !UseClockOut && (Outputs==1)) begin : NOCONV
    assign out[0] = in;
    assign inFb = outFb[0];
    assign resetRequest = 1'b0;
  end
  else if (InputIsBc && OutputIsBc) begin : BC2BC
    // both are BC, lets convert to serial, demux from there, and convert to outputs
    // this is the only one that works for now :)

    // first normalize input BC
    oclib_pkg::bc_8b_bidi_s inNormal;
    oclib_pkg::bc_8b_bidi_s inNormalFb;

    oclib_bc_bidi_adapter #(.BcAType(CsrInType),.BcBType(oclib_pkg::bc_8b_bidi_s),
                            .BufferStages(InputBufferStages))
    uBC_IN (.clock(clock), .reset(resetSync),
            .aIn(in), .aOut(inFb), .bOut(inNormal), .bIn(inNormalFb));

    // use a BC message splitter
    oclib_pkg::bc_8b_bidi_s outSplit [Outputs-1:0];
    oclib_pkg::bc_8b_bidi_s outSplitFb [Outputs-1:0];

    oclib_bc_tree_splitter #(.BcType(oclib_pkg::bc_8b_bidi_s))
    uBC_SPLIT (.clock(clock), .reset(resetSync),
               .upIn(inNormal), .upOut(inNormalFb),
               .downOut(outSplit), .downIn(outSplitFb),
               .resetRequest(resetRequest));

    // now drive out the output BC
    for (genvar i=0; i<Outputs; i++) begin : OUT
      oclib_bc_bidi_adapter #(.BcAType(oclib_pkg::bc_8b_bidi_s),.BcBType(CsrOutType),
                              .BufferStages(OutputBufferStagesEach[i]))
      uBC_IN (.clock(clock), .reset(resetSync),
              .aIn(outSplit[i]), .aOut(outSplitFb[i]), .bOut(out[i]), .bIn(outFb[i]));
    end

  end
  else if (InputIsCsr && OutputIsCsr) begin : CSR2CSR

    logic [Outputs-1:0]       mask;

    enum logic [2:0] { StIdle, StCalcMask, StRead, StWrite, StWait } state;

    always_ff @(posedge clock) begin
      if (state == StCalcMask) begin
        for (int i=0; i<Outputs; i++) begin
          // by default downOut[0] responds to block 0, downOut[1] to block 1, etc.
          // different addresses can be provided via setting OutputBlockIdKey (say '{2,3,4,5})
          // and different RANGES can be given (for later subdecode) using IdKey (say '{ 'h100, 'h200, 'h400, 'h440} ) and
          // IdMask (say '{ 'hff, 'h1ff, 'h3f, 'h3f })
          mask[i] <= ((OutputBlockIdKey[i] == 32'hffffffff) ? (in.toblock == i) :
                      ((in.toblock & OutputBlockIdMask[i]) == OutputBlockIdKey[i]));
        end
      end
    end

    CsrOutType outInternal;
    CsrOutFbType outInternalFb;

    always_comb begin
      outInternalFb = '0;
      for (int i=0; i<Outputs; i++) begin
        out[i] = outInternal;
        out[i].read = outInternal.read && mask[i];
        out[i].write = outInternal.write && mask[i];
        // this reverse path vvvv is really bad for now
        if (outFb[i].ready) begin
          outInternalFb.ready = 1'b1;
          outInternalFb.rdata = outFb[i].rdata;
          outInternalFb.error = outFb[i].error;
        end
      end
    end

    logic writing;

    always_ff @(posedge clock) begin
      if (resetSync) begin
        inFb <= '0;
        outInternal <= '0;
        state <= StIdle;
        writing <= 1'b0;
        resetRequest <= 1'b0;
      end
      else begin
        inFb.ready <= 1'b0;
        case (state)

          StIdle : begin
            if (in.read || in.write) begin
              // note that the way the structs are setup, this will copy everything value from a larger
              // struct (noc, tree) to a smaller struct (tree, regular)
              outInternal <= in;
              writing <= in.write;
              state <= StCalcMask;
            end
            outInternal.read <= 1'b0;
            outInternal.write <= 1'b0;
          end // StIdle

          StCalcMask : begin
            state <= (writing ? StWrite : StRead);
          end // StCalcMask

          StWrite : begin
            outInternal.write <= 1'b1;
            if (outInternalFb.ready) begin
              inFb.ready <= 1'b1;
              inFb.error <= outInternalFb.error;
              inFb.rdata <= '0;
              state <= StWait;
            end
          end // StWrite

          StRead : begin
            outInternal.read <= 1'b1;
            if (outInternalFb.ready) begin
              inFb.ready <= 1'b1;
              inFb.error <= outInternalFb.error;
              inFb.rdata <= outInternalFb.rdata;
              state <= StWait;
            end
          end // StRead

          StWait : begin
            outInternal.read <= 1'b0;
            outInternal.write <= 1'b0;
            if (!(in.read || in.write)) begin
              state <= StIdle;
            end
          end // StWait

        endcase // case (state)
      end // else: !if(resetSync)
    end // always_ff @ (posedge clock)

  end // block: CSR2CSR
  else begin
    // as needed, we should be adding other translations here, though I don't think there's any
    // way to make each output a separate type... (i.e. split to some CSR, and an AXIL/APB/DRP/etc)
    `OC_STATIC_ERROR($sformatf("Don't know how to split CSR from: %s to: %s", $typename(CsrInType),$typename(CsrOutType)));
  end

endmodule // oclib_csr_tree_splitter
