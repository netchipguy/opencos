
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_axim_fifo #(
                         parameter     type AximType = oclib_pkg::axi4m_256_s,
                         parameter     type AximFbType = oclib_pkg::axi4m_256_fb_s,
                         parameter int Depth = 32,
                         parameter int InputDepth = Depth,
                         parameter int OutputDepth = Depth,
                         parameter int ArDepth = InputDepth,
                         parameter int AwDepth = InputDepth,
                         parameter int WDepth = InputDepth,
                         parameter int RDepth = OutputDepth,
                         parameter int BDepth = OutputDepth,
                         parameter int AlmostFull = (Depth-8),
                         parameter int InputAlmostFull = (InputDepth-8),
                         parameter int OutputAlmostFull = (OutputDepth-8),
                         parameter int ArAlmostFull = InputAlmostFull,
                         parameter int AwAlmostFull = InputAlmostFull,
                         parameter int WAlmostFull = InputAlmostFull,
                         parameter int RAlmostFull = OutputAlmostFull,
                         parameter int BAlmostFull = OutputAlmostFull,
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

  oclib_fifo #(.Width($bits(in.ar)), .Depth(ArDepth), .AlmostFull(ArAlmostFull))
  uAR_FIFO (.clock(clock), .reset(resetSync), .almostFull(arAlmostFull), .almostEmpty(),
            .inData(in.ar), .inValid(in.arvalid), .inReady(inFb.arready),
            .outData(out.ar), .outValid(out.arvalid), .outReady(outFb.arready));

  oclib_fifo #(.Width($bits(in.aw)), .Depth(AwDepth), .AlmostFull(AwAlmostFull))
  uAW_FIFO (.clock(clock), .reset(resetSync), .almostFull(awAlmostFull), .almostEmpty(),
            .inData(in.aw), .inValid(in.awvalid), .inReady(inFb.awready),
            .outData(out.aw), .outValid(out.awvalid), .outReady(outFb.awready));

  oclib_fifo #(.Width($bits(in.w)), .Depth(WDepth), .AlmostFull(WAlmostFull))
  uW_FIFO (.clock(clock), .reset(resetSync), .almostFull(wAlmostFull), .almostEmpty(),
           .inData(in.w), .inValid(in.wvalid), .inReady(inFb.wready),
           .outData(out.w), .outValid(out.wvalid), .outReady(outFb.wready));

  oclib_fifo #(.Width($bits(inFb.r)), .Depth(RDepth), .AlmostFull(RAlmostFull))
  uR_FIFO (.clock(clock), .reset(resetSync), .almostFull(rAlmostFull), .almostEmpty(),
           .inData(outFb.r), .inValid(outFb.rvalid), .inReady(out.rready),
           .outData(inFb.r), .outValid(inFb.rvalid), .outReady(in.rready));

  oclib_fifo #(.Width($bits(inFb.b)), .Depth(BDepth), .AlmostFull(BAlmostFull))
  uB_FIFO (.clock(clock), .reset(resetSync), .almostFull(bAlmostFull), .almostEmpty(),
           .inData(outFb.b), .inValid(outFb.bvalid), .inReady(out.bready),
           .outData(inFb.b), .outValid(inFb.bvalid), .outReady(in.bready));

endmodule // oclib_axim_fifo
