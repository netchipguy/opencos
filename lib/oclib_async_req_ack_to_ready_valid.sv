
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_async_req_ack_to_ready_valid
  #(
    parameter integer Width = 8,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input                    clock,
   input                    reset,
   input [Width-1:0]        inData,
   input                    inReq,
   output logic             inAck,
   output logic [Width-1:0] outData,
   output logic             outValid,
   input                    outReady
   );

  logic                     resetSync;
  logic                     resetQ;
  oclib_synchronizer #(.Enable(ResetSync)) uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));
  oclib_pipeline #(.Length(ResetPipeline)) uRESET_PIPE (.clock(clock), .in(resetSync), .out(resetQ));

  // synchronize the incoming async signals
  logic [Width-1:0]         inDataSync;
  logic                     inReqSync;
  oclib_synchronizer #(.Width(Width+1)) uIN_SYNC (.clock(clock), .in({inReq, inData}), .out({inReqSync, inDataSync}));

  always_ff @(posedge clock) begin
    if (resetQ) begin
      outData <= '0;
      outValid <= 1'b0;
      inAck <= 1'b0;
    end
    else begin
      outValid <= (outValid && !outReady);
      inAck <= (inAck ? inReqSync : // if ACK already 1, lower when REQ lowers
                (inReqSync && !outValid)); // else, raise if REQ=1 and VALID=0 (i.e. not busy)
      if (inAck && !inReqSync) begin
        outData <= inDataSync;
        outValid <= 1'b1;
      end
    end // else: !if(resetQ)
  end // always_ff @ (posedge clock)

endmodule // oclib_ready_valid_to_async_req_ack
