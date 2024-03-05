
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_axim_pipeline #(
                             parameter     type AximType = oclib_pkg::axi4m_256_s,
                             parameter     type AximFbType = oclib_pkg::axi4m_256_fb_s,
                             parameter int Length = 0,
                             parameter int SyncCycles = 3,
                             parameter bit ResetSync = oclib_pkg::False,
                             parameter int ResetPipeline = 0
                             )
(
 input  clock,
 input  reset,
 input  AximType in,
 output AximFbType inFb,
 output AximType out,
 input  AximFbType outFb
 );

  logic                             resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  oclib_ready_valid_pipeline #(.Width($bits(in.ar)), .Length(Length))
  uAR_PIPE (.clock(clock), .reset(resetSync),
            .inData(in.ar), .inValid(in.arvalid), .inReady(inFb.arready),
            .outData(out.ar), .outValid(out.arvalid), .outReady(outFb.arready));

  oclib_ready_valid_pipeline #(.Width($bits(in.aw)), .Length(Length))
  uAW_PIPE (.clock(clock), .reset(resetSync),
            .inData(in.aw), .inValid(in.awvalid), .inReady(inFb.awready),
            .outData(out.aw), .outValid(out.awvalid), .outReady(outFb.awready));

  oclib_ready_valid_pipeline #(.Width($bits(in.w)), .Length(Length))
  uW_PIPE (.clock(clock), .reset(resetSync),
            .inData(in.w), .inValid(in.wvalid), .inReady(inFb.wready),
            .outData(out.w), .outValid(out.wvalid), .outReady(outFb.wready));

  oclib_ready_valid_pipeline #(.Width($bits(inFb.r)), .Length(Length))
  uR_PIPE (.clock(clock), .reset(resetSync),
           .inData(outFb.r), .inValid(outFb.rvalid), .inReady(out.rready),
           .outData(inFb.r), .outValid(inFb.rvalid), .outReady(in.rready));

  oclib_ready_valid_pipeline #(.Width($bits(inFb.b)), .Length(Length))
  uB_PIPE (.clock(clock), .reset(resetSync),
           .inData(outFb.b), .inValid(outFb.bvalid), .inReady(out.bready),
           .outData(inFb.b), .outValid(inFb.bvalid), .outReady(in.bready));

endmodule // oclib_axim_pipeline
