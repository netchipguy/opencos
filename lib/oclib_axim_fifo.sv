
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_axim_fifo #(
                         parameter     type AximType = oclib_pkg::axi4m_256_s,
                         parameter     type AximFbType = oclib_pkg::axi4m_256_fb_s,
                         parameter int Depth = 32,
                         parameter int AlmostFull = (Depth-8),
                         parameter int SyncCycles = 3,
                         parameter bit ResetSync = oclib_pkg::False,
                         parameter int ResetPipeline = 0
                         )
(
 input        clock,
 input        reset,
 output logic arAlmostFull,
 output logic awAlmostFull,
 output logic wAlmostFull,
 output logic rAlmostFull,
 output logic bAlmostFull,
 input        AximType in,
 output       AximFbType inFb,
 output       AximType out,
 input        AximFbType outFb
 );

  logic resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  oclib_fifo #(.Width($bits(in.ar)), .Depth(Depth))
  uAR_FIFO (.clock(clock), .reset(resetSync), .almostFull(arAlmostFull),
            .inData(in.ar), .inValid(in.arvalid), .inReady(inFb.arready),
            .outData(out.ar), .outValid(out.arvalid), .outReady(outFb.arready));

  oclib_fifo #(.Width($bits(in.aw)), .Depth(Depth))
  uAW_FIFO (.clock(clock), .reset(resetSync), .almostFull(awAlmostFull),
            .inData(in.aw), .inValid(in.awvalid), .inReady(inFb.awready),
            .outData(out.aw), .outValid(out.awvalid), .outReady(outFb.awready));

  oclib_fifo #(.Width($bits(in.w)), .Depth(Depth))
  uW_FIFO (.clock(clock), .reset(resetSync), .almostFull(wAlmostFull),
           .inData(in.w), .inValid(in.wvalid), .inReady(inFb.wready),
           .outData(out.w), .outValid(out.wvalid), .outReady(outFb.wready));

  oclib_fifo #(.Width($bits(inFb.r)), .Depth(Depth))
  uR_FIFO (.clock(clock), .reset(resetSync), .almostFull(rAlmostFull),
           .inData(outFb.r), .inValid(outFb.rvalid), .inReady(out.rready),
           .outData(inFb.r), .outValid(inFb.rvalid), .outReady(in.rready));

  oclib_fifo #(.Width($bits(inFb.b)), .Depth(Depth))
  uB_FIFO (.clock(clock), .reset(resetSync), .almostFull(bAlmostFull),
           .inData(outFb.b), .inValid(outFb.bvalid), .inReady(out.bready),
           .outData(inFb.b), .outValid(inFb.bvalid), .outReady(in.bready));

endmodule // oclib_axim_fifo
