
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_bc_bidi_to_words
 #(
   parameter         type BcType = oclib_pkg::bc_8b_bidi_s,
   parameter integer WordInWidth = 64,
   parameter integer WordOutWidth = 64,
   parameter integer ShiftInFanout = 16,
   parameter integer ShiftOutFanout = 16,
   parameter integer SyncCycles = 3,
   parameter bit     ResetSync = oclib_pkg::False,
   parameter integer ResetPipeline = 0
  )
  (
   input                           clock,
   input                           reset,
   input                           BcType bcIn,
   output                          BcType bcOut,
   output logic [WordOutWidth-1:0] wordOutData,
   output logic                    wordOutValid,
   input                           wordOutReady,
   input [WordInWidth-1:0]         wordInData,
   input                           wordInValid,
   output logic                    wordInReady
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // convert BC to 8-bit sync
  oclib_pkg::bc_8b_bidi_s bcInSync, bcOutSync;
  oclib_bc_bidi_adapter #(.BcAType(BcType), .BcBType(oclib_pkg::bc_8b_bidi_s))
  uBC_ADAPTER (.clock(clock), .reset(resetSync),
               .aIn(bcIn), .aOut(bcOut),
               .bOut(bcInSync), .bIn(bcOutSync) );

  // convert BC to words
  oclib_pkg::bc_8b_s bcInUni, bcOutUni;
  oclib_pkg::bc_8b_fb_s bcInUniFb, bcOutUniFb;

  oclib_bc_to_word #(.WordWidth(WordOutWidth), .ShiftFanout(ShiftOutFanout))
  uBC_TO_WORD (.clock(clock), .reset(resetSync),
//               .bc('{data:bcInSync.data,valid:bcInSync.valid}), .bcFb('{ready:bcOutSync.ready}),
               .bc(bcInUni), .bcFb(bcInUniFb),
               .wordData(wordOutData), .wordValid(wordOutValid), .wordReady(wordOutReady));

  oclib_word_to_bc #(.WordWidth(WordInWidth), .ShiftFanout(ShiftInFanout))
  uWORD_TO_BC (.clock(clock), .reset(resetSync),
//               .bc('{data:bcOutSync.data,valid:bcOutSync.valid}), .bcFb('{ready:bcInSync.ready}),
               .bc(bcOutUni), .bcFb(bcOutUniFb),
               .wordData(wordInData), .wordValid(wordInValid), .wordReady(wordInReady));

  assign bcInUni.data = bcInSync.data;
  assign bcInUni.valid = bcInSync.valid;
  assign bcOutSync.ready = bcInUniFb.ready;

  assign bcOutSync.data = bcOutUni.data;
  assign bcOutSync.valid = bcOutUni.valid;
  assign bcOutUniFb.ready = bcInSync.ready;

endmodule // oclib_bc_bidi_to_words
