
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_async_req_ack_to_ready_valid
  #(
    parameter integer Width = 8,
    parameter integer SyncCycles = 3,
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

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // synchronize the incoming async signals
  logic [Width-1:0]         inDataSync;
  logic                     inReqSync;
  oclib_synchronizer #(.Width(Width+1), .SyncCycles(SyncCycles))
  uIN_SYNC (.clock(clock), .in({inReq, inData}), .out({inReqSync, inDataSync}));

  always_ff @(posedge clock) begin
    if (resetSync) begin
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
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_async_req_ack_to_ready_valid
