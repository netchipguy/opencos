
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_ready_valid_to_async_req_ack
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
   input                    inValid,
   output logic             inReady,
   output logic [Width-1:0] outData,
   output logic             outReq,
   input                    outAck
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // synchronize the incoming async signals
  logic          outAckSync;
  oclib_synchronizer #(.Width(1), .SyncCycles(SyncCycles))
  uACK_SYNC (.clock(clock), .in(outAck), .out(outAckSync));

  enum           logic [1:0] { StIdle, StReq, StWait } state;

  always_ff @(posedge clock) begin
    if (resetSync) begin
      inReady <= 1'b0;
      outData <= '0;
      outReq <= 1'b0;
      state <= StIdle;
    end
    else begin
      case (state)
        StIdle : begin
          if (inValid && inReady) begin
            inReady <= 1'b0;
            outData <= inData;
            outReq <= 1'b1;
            state <= StReq;
          end
          else begin
            inReady <= 1'b1;
          end
        end
        StReq : begin
          if (outAckSync) begin
            outReq <= 1'b0;
            state <= StWait;
          end
        end
        StWait : begin
          if (!outAckSync) begin
            inReady <= 1'b1;
            state <= StIdle;
          end
        end
      endcase // case (state)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_ready_valid_to_async_req_ack
