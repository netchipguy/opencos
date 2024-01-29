
// SPDX-License-Identifier: MPL-2.0

`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"

module oc_cos
  #(
    // *** MISC ***
    parameter integer Seed = 0,
    parameter bit EnableUartControl = 0,
    // *** REFCLOCK ***
    parameter integer RefClockCount = 1,
    `OC_LOCALPARAM_SAFE(RefClockCount),
    parameter integer RefClockHz [0:RefClockCount-1] = {100_000_000},
    // *** TOP CLOCK ***
    parameter integer ClockTop = oc_top_pkg::ClockIdSingleEndedRef(0),
    // *** LED ***
    parameter integer LedCount = 0,
    `OC_LOCALPARAM_SAFE(LedCount),
    // *** UART ***
    parameter integer UartCount = 0,
    `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = {115200},
    parameter integer UartControl = 0
    )
  (
   // *** REFCLOCK ***
   input [RefClockCountSafe-1:0]    clockRef,
   // *** RESET ***
   input                            hardReset,
   // *** LED ***
   output logic [LedCountSafe-1:0]  ledOut,
   // *** UART ***
   input [UartCountSafe-1:0]        uartRx,
   output logic [UartCountSafe-1:0] uartTx
   );

  // *** REFCLOCK ***
  localparam integer ClockTopHz = RefClockHz[ClockTop]; // should be ~100MHz, some IP cannot go faster
  logic                             clockTop;
  assign clockTop = clockRef[ClockTop];

  // *** RESET AND TIMING ***
  logic                             resetFromUartControl;
  logic                             resetTop;

  // If we have UART based control, we stretch reset to be pretty long, so that if we send a reset command
  // over the UART, or we power up, etc, we hold reset for at least one UART bit time (to allow bus to idle)
  localparam                        TopResetCycles = (EnableUartControl ?
                                                      ((ClockTopHz / UartBaud[UartControl]) + 50) :
                                                      128);

  oclib_reset #(.StartPipeCycles(8), .ResetCycles(TopResetCycles))
  uRESET (.clock(clockTop), .in(hardReset || resetFromUartControl), .out(resetTop));

  oclib_pkg::chip_status_s          chipStatus;

  oc_chip_status #(.ClockHz(ClockTopHz))
  uSTATUS (.clock(clockTop), .reset(resetTop), .chipStatus(chipStatus));

  // *** UART CONTROL ***
  logic                             blink;

  if (EnableUartControl) begin
    oc_uart_control #(.ClockHz(ClockTopHz),
                      .Baud(UartBaud[UartControl]))
    uCONTROL (.clock(clockTop), .reset(resetTop),
              .resetOut(resetFromUartControl),
              .blink(blink),
              .uartRx(uartRx[UartControl]), .uartTx(uartTx[UartControl]) );
  end
  else begin
    assign resetFromUartControl = 1'b0;
    assign blink = 1'b0;
  end

  // *** CONTROL MUX ***



  // *** TEMP ***

  logic [31:0]  count = Seed;
  always @(posedge clockTop) begin
    if (hardReset) begin
      count <= '0;
      ledOut <= 3'b101;
    end
    else begin
      count <= (count + 1);
      ledOut <= count[29:27] | {3{blink}};
    end
  end

  // idle SC UART for now
  assign uartTx[1] = 1'b1;

endmodule // oc_cos
