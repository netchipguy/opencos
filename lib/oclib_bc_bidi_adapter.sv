
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oclib_bc_bidi_adapter
  #(
    parameter         type BcTypeA = oclib_pkg::bc_8b_bidi_s,
    parameter         type BcTypeB = oclib_pkg::bc_8b_bidi_s,
    parameter integer BufferStages = 0,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = ResetSync ? 0 : BufferStages // pipeline reset same as buffer stages, unless it's async
    )
  (
   input  clock,
   input  reset,
   input  BcTypeA aIn,
   output BcTypeA aOut,
   input  BcTypeB bIn,
   output BcTypeB bOut
   );

  if (type(BcTypeA) == type(BcTypeB)) begin : NOCONV
    if ((BufferStages == 0) || (type(BcTypeA) == type(bc_async_8b_bidi_s))) begin : NOBUFF
      assign bOut = aIn;
      assign aOut = bIn;
    end
    else if (type(BcTypeA) == type(oclib_pkg::bc_8b_bidi_s)) begin : BUFF

      oclib_ready_valid_pipeline #(.Width($bits(aIn.data)),
                                   .Length(BufferStages),
                                   .ResetSync(ResetSync),
                                   .ResetPipeline(ResetPipeline))
      uBUF_A_B (.clock(clock), .reset(reset),
                .inData(aIn.data), .inValid(aIn.valid), .inReady(aOut.ready),
                .outData(bOut.data), .outValid(bOut.valid), .outReady(bIn.ready));

      oclib_ready_valid_pipeline #(.Width($bits(aIn.data)),
                                   .Length(BufferStages),
                                   .ResetSync(ResetSync),
                                   .ResetPipeline(ResetPipeline))
      uBUF_B_A (.clock(clock), .reset(reset),
                .inData(bIn.data), .inValid(bIn.valid), .inReady(bOut.ready),
                .outData(aOut.data), .outValid(aOut.valid), .outReady(aIn.ready));
    end
    else begin
      `OC_STATIC_ERROR($sformatf("Don't know how to buffer (BufferStages=%0d) BC type: %s", BufferStages, $typename(BcTypeA)));
    end
  end
  else if ((type(BcTypeA) == type(oclib_pkg::bc_8b_bidi_s)) &&
           (type(BcTypeB) == type(oclib_pkg::bc_async_8b_bidi_s))) begin : CONV_S8_A8

    oclib_ready_valid_to_async_req_ack #(.Width($bits(aIn.data)),
                                         .ResetSync(ResetSync),
                                         .ResetPipeline(ResetPipeline))
    uCONV_A_B (.clock(clock), .reset(reset),
               .inData(aIn.data), .inValid(aIn.valid), .inReady(aOut.ready),
               .outData(bOut.data), .outReq(bOut.req), .outAck(bIn.ack));

    oclib_async_req_ack_to_ready_valid #(.Width($bits(aIn.data)),
                                         .ResetSync(ResetSync),
                                         .ResetPipeline(ResetPipeline))
    uCONV_B_A (.clock(clock), .reset(reset),
               .inData(bIn.data), .inReq(bIn.req), .inAck(bOut.ack),
               .outData(aOut.data), .outValid(aOut.valid), .outReady(aIn.ready));
  end
  else if ((type(BcTypeA) == type(oclib_pkg::bc_async_8b_bidi_s)) &&
           (type(BcTypeB) == type(oclib_pkg::bc_8b_bidi_s))) begin : CONV_A8_S8

    oclib_async_req_ack_to_ready_valid #(.Width($bits(aIn.data)),
                                         .ResetSync(ResetSync),
                                         .ResetPipeline(ResetPipeline))
    uCONV_A_B (.clock(clock), .reset(reset),
               .inData(aIn.data), .inReq(aIn.req), .inAck(aOut.ack),
               .outData(bOut.data), .outValid(bOut.valid), .outReady(bIn.ready));

    oclib_ready_valid_to_async_req_ack #(.Width($bits(aIn.data)),
                                         .ResetSync(ResetSync),
                                         .ResetPipeline(ResetPipeline))
    uCONV_B_A (.clock(clock), .reset(reset),
               .inData(bIn.data), .inValid(bIn.valid), .inReady(bOut.ready),
               .outData(aOut.data), .outReq(aOut.req), .outAck(aIn.ack));
  end
  else if ((type(BcTypeA) == type(oclib_pkg::bc_8b_bidi_s)) &&
           (type(BcTypeB) == type(oclib_pkg::bc_async_1b_bidi_s))) begin : CONV_S8_A1

    oclib_ready_valid_to_async_serial #(.Width($bits(aIn.data)),
                                        .ResetSync(ResetSync),
                                        .ResetPipeline(ResetPipeline))
    uCONV_A_B (.clock(clock), .reset(reset),
               .inData(aIn.data), .inValid(aIn.valid), .inReady(aOut.ready),
               .outData(bOut.data), .outAck(bIn.ack));

    oclib_async_serial_to_ready_valid #(.Width($bits(aIn.data)),
                                        .ResetSync(ResetSync),
                                        .ResetPipeline(ResetPipeline))
    uCONV_B_A (.clock(clock), .reset(reset),
               .inData(bIn.data), .inAck(bOut.ack),
               .outData(aOut.data), .outValid(aOut.valid), .outReady(aIn.ready));
  end
  else if ((type(BcTypeA) == type(oclib_pkg::bc_async_1b_bidi_s)) &&
           (type(BcTypeB) == type(oclib_pkg::bc_8b_bidi_s))) begin : CONV_A8_S8

    oclib_async_serial_to_ready_valid #(.Width($bits(bIn.data)),
                                        .ResetSync(ResetSync),
                                        .ResetPipeline(ResetPipeline))
    uCONV_A_B (.clock(clock), .reset(reset),
               .inData(aIn.data), .inAck(aOut.ack),
               .outData(bOut.data), .outValid(bOut.valid), .outReady(bIn.ready));

    oclib_ready_valid_to_async_serial #(.Width($bits(bIn.data)),
                                        .ResetSync(ResetSync),
                                        .ResetPipeline(ResetPipeline))
    uCONV_B_A (.clock(clock), .reset(reset),
               .inData(bIn.data), .inValid(bIn.valid), .inReady(bOut.ready),
               .outData(aOut.data), .outAck(aIn.ack));
  end
  else begin
      `OC_STATIC_ERROR($sformatf("Don't know how to handle this combination: A type: %s, B type: %s",
                                 $typename(BcTypeA), $typename(BcTypeB) ));
  end

endmodule // oclib_bc_bidi_adapter
