
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_ready_valid_to_async_serial
  #(
    parameter integer Width = 8,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input              clock,
   input              reset,
   input [Width-1:0]  inData,
   input              inValid,
   output logic       inReady,
   output logic [1:0] outData,
   input              outAck
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // synchronize the incoming async signals
  logic                     outAckSync;
  oclib_synchronizer #(.Width(1), .SyncCycles(SyncCycles))
  uACK_SYNC (.clock(clock), .in(outAck), .out(outAckSync));

  localparam                CounterWidth = $clog2(Width);
  logic [CounterWidth-1:0]  counter;
  enum                      logic [1:0] { StIdle, StSend, StWait } state;

  // NOTE: technically, I think this isn't following proper ready/valid protocol, in that it uses inData
  // without giving inReady.  Technically inData can change while inValid stays high, and the value on the
  // bus when inReady is asserted is the one "transferred".  Here we save a stage of flops by assuming
  // inData doesn't change, but we could add a param to comply better if needed for some future partner.

  always_ff @(posedge clock) begin
    if (resetSync) begin
      inReady <= 1'b0;
      outData <= 2'b00;
      counter <= '0;
      state <= StIdle;
    end
    else begin
      case (state)
        StIdle : begin
          if (inValid && !inReady) begin
            outData <= (outData ^ {inData[counter], !inData[counter]});
            counter <= (counter + 'd1);
            state <= StSend;
          end
          inReady <= 1'b0;
        end
        StSend : begin
          if (outAckSync == (^outData)) begin
            // remote side has seen latest data
            outData <= (outData ^ {inData[counter], !inData[counter]});
            counter <= (counter + 'd1);
            if (counter == (Width-1)) begin
              state <= StWait;
            end
          end
        end
        StWait : begin
          if (outAckSync == (^outData)) begin
            state <= StIdle;
            inReady <= 1'b1;
          end
          counter <= '0;
        end
      endcase // case (state)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_ready_valid_to_async_serial
