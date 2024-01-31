
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_ready_valid_retime #(parameter integer Width = 1,
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

  logic                         resetSync;
  logic                         resetQ;
  oclib_synchronizer #(.Enable(ResetSync)) uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));
  oclib_pipeline #(.Length(ResetPipeline)) uRESET_PIPE (.clock(clock), .in(resetSync), .out(resetQ));

  logic [Width-1:0]      firstData;
  logic                  firstValid;
  logic [Width-1:0]      secondData;
  logic                  secondValid;

  always_ff @(posedge clock) begin
    if (resetQ) begin
      firstValid <= 1'b0;
      secondValid <= 1'b0;
    end
    else begin
      if (inReady) begin
        firstValid <= inValid;
        firstData <= inData;
        if (!outReady) begin
          secondValid <= firstValid;
          secondData <= firstData;
        end
      end
      if (outReady) begin
        secondValid <= 1'b0;
      end
    end
  end

  assign inReady = ~secondValid;
  assign outData = (secondValid ? secondData : firstData);
  assign outValid = (secondValid || firstValid);

endmodule // oclib_ready_valid_retime
