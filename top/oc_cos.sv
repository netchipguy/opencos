
// SPDX-License-Identifier: MPL-2.0

`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_cos
  #(
    // *******************************************************************************
    // ***                         EXTERNAL CONFIGURATION                          ***
    // Interfaces to the chip top
    // *******************************************************************************

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

    // *******************************************************************************
    // ***                         INTERNAL CONFIGURATION                          ***
    // Configuring OC_COS internals which board can override in target-specific ways
    // *******************************************************************************

    // *** Format of Top-Level CSR bus ***
    parameter         type CsrTopType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrTopFbType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrTopProtocol = oclib_pkg::csr_32_tree_s,
    parameter         type CsrTopFbProtocol = oclib_pkg::csr_32_tree_fb_s
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
  // *** RESOURCE CALCULATIONS ***

  localparam integer             BlockFirstLed = 0;
  localparam integer             BlockTopCount = (BlockFirstLed + (LedCount ? 1 : 0)); // we drive all LEDs from one IP
  localparam integer             BlockUserCount = 0;
  localparam integer             BlockCount = (BlockTopCount + BlockUserCount);

  // *******************************************************************************
  // *** REFCLOCK ***
  localparam integer             ClockTopHz = RefClockHz[ClockTop]; // should be ~100MHz, some IP cannot go faster
  logic                          clockTop;
  assign clockTop = clockRef[ClockTop];

  // *******************************************************************************
  // *** RESET AND TIMING ***
  logic                          resetFromUartControl;
  logic                          resetTop;

  // If we have UART based control, we stretch reset to be pretty long, so that if we send a reset command
  // over the UART, or we power up, etc, we hold reset for at least one UART bit time (to allow bus to idle)
  localparam                     TopResetCycles = (EnableUartControl ?
                                                   ((ClockTopHz / UartBaud[UartControl]) + 50) :
                                                   128);

  oclib_reset #(.StartPipeCycles(8), .ResetCycles(TopResetCycles))
  uRESET (.clock(clockTop), .in(hardReset || resetFromUartControl), .out(resetTop));

  oclib_pkg::chip_status_s       chipStatus;

  oc_chip_status #(.ClockHz(ClockTopHz))
  uSTATUS (.clock(clockTop), .reset(resetTop), .chipStatus(chipStatus));

  // *******************************************************************************
  // *** UART CONTROL ***

  // this is between uart
  localparam                     type UartControlBcType = oclib_pkg::bc_8b_bidi_s;
  UartControlBcType              uartBcOut, uartBcIn;

  if (EnableUartControl) begin : uart_control
    oc_uart_control #(.ClockHz(ClockTopHz),
                      .Baud(UartBaud[UartControl]),
                      .UartControlBcType(UartControlBcType),
                      .UartControlProtocol(CsrTopProtocol),
                      .BlockTopCount(BlockTopCount),
                      .BlockUserCount(BlockUserCount),
                      .ResetSync(oclib_pkg::False) )
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

  CsrTopType                     csrTop [BlockCount];
  CsrTopFbType                   csrTopFb [BlockCount];
  logic                          resetFromTopCsrSplitter;

  oclib_csr_tree_splitter #(.CsrInType(UartControlBcType), .CsrInFbType(UartControlBcType),
                            .CsrOutType(CsrTopType), .CsrOutFbType(CsrTopFbType),
                            .Outputs(BlockCount) )
  uTOP_CSR_SPLITTER (.clock(clockTop), .reset(resetTop),
                     .resetRequest(resetFromTopCsrSplitter),
                     .in(uartBcOut), .inFb(uartBcIn),
                     .out(csrTop), .outFb(csrTopFb));

  // *******************************************************************************
  // *** LED ***

  if (LedCount) begin : led
    oc_led #(.ClockHz(ClockTopHz), .LedCount(LedCount),
             .CsrType(CsrTopType), .CsrFbType(CsrTopFbType))
    uLED (.clock(clockTop), .reset(resetTop),
          .csr(csrTop[BlockFirstLed]), .csrFb(csrTopFb[BlockFirstLed]),
          .ledOut(ledOut));
  end
  else begin
    assign ledOut = '0;
  end

  // *******************************************************************************
  // *** idle unused UARTs for now ***

  for (genvar i=0; i<UartCount; i++) begin
    if (i != UartControl) begin
      assign uartTx[i] = 1'b1;
    end
  end

endmodule // oc_cos
