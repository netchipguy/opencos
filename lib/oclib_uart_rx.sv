
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_uart_pkg.sv"
`include "lib/oclib_pkg.sv"

module oclib_uart_rx
  #(
    parameter integer ClockHz = 100_000_000,
    parameter integer Baud = 115_200,
    parameter integer BaudCycles = (ClockHz / Baud), // i.e. 868
    parameter integer DebounceCycles = (BaudCycles / 16), // i.e. 54
    parameter integer FifoDepth = 0,
    parameter integer ErrorWidth = oclib_uart_pkg::ErrorWidth,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input                         clock,
   input                         reset,
   input                         clearError = 1'b0,
   output logic [ErrorWidth-1:0] error,
   input                         rx,
   output logic [7:0]            rxData,
   output logic                  rxValid,
   input                         rxReady
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  /* Design Philosophy

   1) We debounce the input fairly aggressively, delaying transitions by 1/16th of a baud in order
   to filter noise esp during switching.
   ---X---XXX---X_XX-X______X__________XX-X_X-X-------------
   becomes
   ------------------------_________________________--------

   2) When we see leading edge of a start bit, we delay by half a baud, then restart the baud timer (*).
   -------------------X_________START_________X-----------D0----------X-----D1----
   State:  StIdle      |   StStart  |  StData
   BaudCtr:   0  0   0  1... 0.5B->(*) 0  1  2  ... 1.0B->(*) 1   2   3
   BaudCtrTC:                                              *
   BaudCtrHalfTC:                   *          *                      *
   BitCtr:    0  0   0  0   0  0    0    0   0   0    0   0  |  1   1   1

   3) BitCtr indicates the next bit to be latched.  We stay in data state bit until we
   latch bit 7, then transition to capturing the STOP bit, then transition to idle.
   --------D6---------X___________D7_________X-----------STOP----------XXXXXXXXXXXXXX
   State:  StData                   |  StStop                | StIdle  |? StStart?
   BaudCtr: (*) 0  1 +   + 1.0B->(*) 0 1 2  3  4  .. 1.0B->(*) 0 1 2 3  ...
   BaudCtrTC:                                              *
   BaudCtrHalfTC:     *                       *                      *
   BitCtr:  |  7    7     7    7   |   0   0     0    0    0     0   0    0   0

   3) We assert rxValid as soon as we've latched D7, and we assert it when we see
   rxReady. We are tolerant with rxReady taking a while, and only consider it an
   error if we need to reassert it.  This enables back-to-back connection to a
   oclib_uart_tx which will take one less baud time to give ready.
   --------D6---------X___________D7_________X-----------STOP----------XXXXXXXXXXXXXX
   State:  StData                   |  StStop                | StIdle  |? StStart?
   BaudCtr: (*) 0  1 +   + 1.0B->(*) 0 1 2  3  4  .. 1.0B->(*) 0 1 2 3  ...
   BitCtr:  |  7    7     7    7   |   0   0     0    0    0     0   0    0   0
   RxValid _________________________/---------------------------------------\_____ (A)
   RxReady _____________________________________________________________/------\__ (A)
   RxValid -------------\___________/--------------------------------------------- (B)
   RxReady _________/------\______________________________________________________ (B)

   error[0] : runt stop bit
   error[1] : no stop bit
   error[2] : rxReady not seen
   */

  logic                    rxDebounced;
  oclib_debounce #(.DebounceCycles(DebounceCycles), .SyncCycles(SyncCycles))
  uINPUT_DEBOUNCE (.clock(clock), .reset(resetSync), .in(rx), .out(rxDebounced));

  localparam BaudCounterW = $clog2(BaudCycles);
  logic [BaudCounterW-1:0] baudCounter;
  logic                    baudCounterTC;
  logic                    baudCounterHalfTC;
  enum                     logic [1:0] { StIdle, StStart, StData, StStop } state;
  logic [2:0]              bitCounter;
  logic [7:0]              shiftData;

  logic [7:0]              fifoData;
  logic                    fifoValid;
  logic                    fifoReady;

  always @(posedge clock) begin
    if (resetSync) begin
      fifoValid <= 1'b0;
      fifoData <= '0;
      shiftData <= '0;
      error <= '0;
      baudCounter <= '0;
      bitCounter <= '0;
      baudCounterTC <= 1'b0;
      baudCounterHalfTC <= 1'b0;
      state <= StIdle;
    end
    else begin
      baudCounter <= (baudCounterTC ? '0 : (baudCounter + 'd1));
      baudCounterTC <= (baudCounter == (BaudCycles-2));
      baudCounterHalfTC <= (baudCounter == ((BaudCycles/2)-2));
      fifoValid <= (fifoValid && ~fifoReady);
      error <= (clearError ? '0 : error);
      case (state)
        StIdle : begin
          bitCounter <= '0;
          baudCounter <= '0;
          if (rxDebounced == '0) begin
            state <= StStart;
          end
        end
        StStart : begin
          bitCounter <= '0;
          if (baudCounterHalfTC) begin
            baudCounter <= '0;
            state <= StData;
            if (rxDebounced != 1'b0) begin
              error[oclib_uart_pkg::ErrorInvalidStart] <= 1'b1;
            end
          end
        end
        StData : begin
          if (baudCounterTC) begin
            shiftData <= { rxDebounced, shiftData[7:1] };
            bitCounter <= (bitCounter + 'd1);
            if (bitCounter == 'd7) begin
              state <= StStop;
              fifoValid <= 1'b1;
              fifoData <= { rxDebounced, shiftData[7:1] };
              if (fifoValid) begin
                error[oclib_uart_pkg::ErrorOverflow] <= 1'b1;
              end
            end
          end
        end
        StStop : begin
          if (baudCounterTC) begin
            if (rxDebounced != 1'b1) begin
              error[oclib_uart_pkg::ErrorInvalidStop] <= 1'b1;
            end
            state <= StIdle;
          end
        end
      endcase // case (state)
    end // else: !if(resetSync)
  end // always @ (posedge clock)

  oclib_fifo #(.Width(8), .Depth(FifoDepth))
  uFIFO (.clock(clock), .reset(resetSync),
         .inData(fifoData), .inValid(fifoValid), .inReady(fifoReady),
         .outData(rxData), .outValid(rxValid), .outReady(rxReady));

endmodule // oclib_uart_rx
