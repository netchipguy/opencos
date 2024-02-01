
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_ready_valid_pipeline
  #(parameter integer Width = 1,
    parameter integer Length = 2,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input                    clock,
   input                    reset,
   input logic [Width-1:0]  inData,
   input                    inValid,
   output logic             inReady,
   output logic [Width-1:0] outData,
   output logic             outValid,
   input                    outReady
   );

  logic [Width-1:0]      stageData [Length-1:0]; // stageData[0] is the data coming out of stage 0
  logic                  stageValid [Length-1:0]; // stageValid[0] is the valid coming out of stage 0
  logic                  stageReady [Length-1:0]; // stageReady[0] is the ready going in to stage 0

  if (Length == 0) begin
    assign outData = inData;
    assign outValid = inValid;
    assign inReady = outReady;
  end
  else begin
    for (genvar stage=0; stage<Length; stage++) begin
      logic              localInReady;
      oclib_ready_valid_retime #(.Width(Width), .SyncCycles(SyncCycles),
                                 .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
      uRETIME (.clock(clock), .reset(reset),
               .inData((stage==0) ? inData : stageData[stage-1]),
               .inValid((stage==0) ? inValid : stageValid[stage-1]),
               .inReady(localInReady),
               .outData(stageData[stage]),
               .outValid(stageValid[stage]),
               .outReady(stageReady[stage]));
      if (stage == 0) assign inReady                           = localInReady;
      else            assign stageReady[stage ? (stage-1) : 0] = localInReady;
    end
    assign outData = stageData[Length-1];
    assign outValid = stageValid[Length-1];
    assign stageReady[Length-1] = outReady;
  end

endmodule // oclib_ready_valid_pipeline
