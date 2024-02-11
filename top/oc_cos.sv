
// SPDX-License-Identifier: MPL-2.0

`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_cos
  #(
    // **************************************************************
    // ***                EXTERNAL CONFIGURATION                  ***
    // Interfaces to the chip top
    // **************************************************************

    // *** MISC ***
    parameter integer Seed = 0,
    parameter bit     EnableUartControl = 0,

    // *** REFCLOCK ***
    parameter integer RefClockCount = 1,
    `OC_LOCALPARAM_SAFE(RefClockCount),
    parameter integer RefClockHz [0:RefClockCount-1] = {100_000_000},

    // *** TOP CLOCK ***
    parameter integer ClockTop = oc_top_pkg::ClockIdSingleEndedRef(0),

    // *** LED ***
    parameter integer LedCount = 3,
    `OC_LOCALPARAM_SAFE(LedCount),

    // *** UART ***
    parameter integer UartCount = 2,
    `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = {115200, 115200},
    parameter integer UartControl = 0,
    // **************************************************************
    // ***                INTERNAL CONFIGURATION                  ***
    // Configuring OC_COS internals which board can override in
    // target-specific ways
    // **************************************************************

    // *** Format of Top-Level CSR bus ***
    parameter         type CsrTopType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrTopFbType = oclib_pkg::bc_8b_bidi_s
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

  // *******************************************************************************
  // *** REFCLOCK ***
  localparam integer ClockTopHz = RefClockHz[ClockTop]; // should be ~100MHz, some IP cannot go faster
  logic                             clockTop;
  assign clockTop = clockRef[ClockTop];

  // *******************************************************************************
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

  // *******************************************************************************
  // *** UART CONTROL ***

  localparam                        type UartBcType = oclib_pkg::bc_8b_bidi_s;
  UartBcType uartBcOut, uartBcIn;

  if (EnableUartControl) begin
    oc_uart_control #(.ClockHz(ClockTopHz),
                      .Baud(UartBaud[UartControl]),
                      .BcType(UartBcType))
    uCONTROL (.clock(clockTop), .reset(resetTop),
              .resetOut(resetFromUartControl),
              .uartRx(uartRx[UartControl]), .uartTx(uartTx[UartControl]),
              .bcOut(uartBcOut), .bcIn(uartBcIn));
  end
  else begin
    assign resetFromUartControl = 1'b0;
    assign blink = 1'b0;
  end

  // *******************************************************************************
  // *** TOP_CSR_SPLIT ***

  localparam integer NumCsrTop = 1; // just oc_led for now

  CsrTopType csrTop [NumCsrTop];
  CsrTopFbType csrTopFb [NumCsrTop];
  logic              resetFromTopCsrSplitter;

  oclib_csr_tree_splitter #(.CsrInType(UartBcType), .CsrInFbType(UartBcType),
                            .CsrOutType(CsrTopType), .CsrOutFbType(CsrTopFbType),
                            .Outputs(NumCsrTop) )
  uTOP_CSR_SPLITTER (.clock(clockTop), .reset(resetTop),
                     .resetRequest(resetFromTopCsrSplitter),
                     .in(uartBcOut), .inFb(uartBcIn),
                     .out(csrTop), .outFb(csrTopFb));

  // *******************************************************************************
  // *** LED ***

  oc_led #(.ClockHz(ClockTopHz), .LedCount(LedCount),
           .CsrType(CsrTopType), .CsrFbType(CsrTopFbType))
  uLED (.clock(clockTop), .reset(resetTop),
        .ledOut(ledOut),
        .csr(csrTop[0]), .csrFb(csrTopFb[0]));


  // *******************************************************************************
  // *** idle unused UARTs for now ***

  for (genvar i=0; i<UartCount; i++) begin
    if (i != UartControl) begin
      assign uartTx[i] = 1'b1;
    end
  end

endmodule // oc_cos
