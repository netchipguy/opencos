
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_uart_pkg.sv"

module oclib_uart
  #(
    parameter integer ClockHz = 100_000_000,
    parameter integer Baud = 115_200,
    parameter         type BcType = oclib_pkg::bc_8b_bidi_s,
    parameter integer BaudCycles = (ClockHz / Baud),
    parameter integer DebounceCycles = (BaudCycles / 16),
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0,
    parameter integer TxFifoDepth = 32,
    parameter integer RxFifoDepth = 0,
    parameter integer ErrorWidth = oclib_uart_pkg::ErrorWidth
    )
  (
   input                   clock,
   input                   reset,
   input                   rx,
   output                  tx,
   input                   BcType bcIn,
   output                  BcType bcOut,
   output [ErrorWidth-1:0] error
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // The uart tx/rx library components use a generic data/valid/ready protocol.
  // These two can be plugged straight into a bc_8b_bidi_s channel.  It can be
  // a little confusing thinking about the naming of the ready, and helps to use
  // the bcFrom*/bcTo* naming.  Seeing uart_tx receive data on bcToUart.data and
  // send backpressure on bcFromUart.ready feels natural, much better than seeing
  // uart_tx receive data on bcTxUart.data and send backpressure on bcRxUart.ready.

  oclib_pkg::bc_8b_bidi_s bcFromUart;
  oclib_pkg::bc_8b_bidi_s bcToUart;

  oclib_uart_tx #(.ClockHz(ClockHz), .Baud(Baud), .BaudCycles(BaudCycles),
                  .FifoDepth(TxFifoDepth))
  uTX (.clock(clock), .reset(resetSync), .tx(tx),
       .txData(bcToUart.data), .txValid(bcToUart.valid), .txReady(bcFromUart.ready));

  oclib_uart_rx #(.ClockHz(ClockHz), .Baud(Baud), .BaudCycles(BaudCycles), .ErrorWidth(ErrorWidth),
                  .DebounceCycles(DebounceCycles), .FifoDepth(RxFifoDepth))
  uRX (.clock(clock), .reset(resetSync), .error(error), .rx(rx),
       .rxData(bcFromUart.data), .rxValid(bcFromUart.valid), .rxReady(bcToUart.ready));

  oclib_bc_bidi_adapter #(.BcAType(BcType), .BcBType(oclib_pkg::bc_8b_bidi_s))
  uBC (.clock(clock), .reset(resetSync),
       .aIn(bcIn), .aOut(bcOut),
       .bIn(bcFromUart), .bOut(bcToUart));

endmodule // oclib_uart
