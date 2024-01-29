
// SPDX-License-Identifier: MPL-2.0

module oclib_uart_tx #(
                       parameter integer ClockHz = 100_000_000,
                       parameter integer Baud = 115_200,
                       parameter integer BaudCycles = (ClockHz / Baud),
                       parameter integer FifoDepth = 32
                     )
  (
   input        clock,
   input        reset,
   input [7:0]  txData,
   input        txValid,
   output logic txReady,
   output logic tx
   );

  localparam BaudCounterW = $clog2(BaudCycles);

  logic [BaudCounterW-1:0] baudCounter;
  logic                    baudCounterTC;
  enum                     logic [1:0] { StIdle, StStart, StData, StStop } state;
  logic [2:0]              bitCounter;

  logic [7:0]              fifoData;
  logic                    fifoValid;
  logic                    fifoReady;

  oclib_fifo #(.Width(8), .Depth(FifoDepth))
  uFIFO (.clock(clock), .reset(reset),
         .inData(txData), .inValid(txValid), .inReady(txReady),
         .outData(fifoData), .outValid(fifoValid), .outReady(fifoReady));

  always @(posedge clock) begin
    if (reset) begin
      tx <= 1'b1;
      fifoReady <= 1'b0;
      baudCounter <= '0;
      bitCounter <= '0;
      baudCounterTC <= 1'b0;
      state <= StIdle;
    end
    else begin
      baudCounter <= (baudCounterTC ? '0 : (baudCounter + 'd1));
      baudCounterTC <= (baudCounter == (BaudCycles-2));
      fifoReady <= 1'b0;
      case (state)
        StIdle : begin
          bitCounter <= '0;
          if (baudCounterTC && fifoValid) begin
            tx <= 1'b0; // start bit
            state <= StStart;
          end
        end
        StStart : begin
          if (baudCounterTC) begin
            bitCounter <= (bitCounter + 'd1); // will be going 0->1 as it points to NEXT bit
            tx <= fifoData[bitCounter]; // load bit 0, coded to share gates with next state
            state <= StData;
          end
        end
        StData : begin
          if (baudCounterTC) begin
            bitCounter <= (bitCounter + 'd1);
            if (bitCounter == 'd0) begin // if the counter has wrapped, time to send the STOP
              tx <= 1'b1; // stop bit
              state <= StIdle;
              fifoReady <= 1'b1;
            end
            else begin
              tx <= fifoData[bitCounter];
            end
          end
        end
      endcase // case (state)
    end
  end

endmodule // oclib_uart_tx
