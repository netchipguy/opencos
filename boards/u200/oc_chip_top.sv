
// SPDX-License-Identifier: MPL-2.0

`include "boards/u200/oc_board_defines.vh"
`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"

module oc_chip_top
  #(
    // *** MISC ***
    parameter integer Seed = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_SEED,0), // seed to generate varying implementation results
    parameter bit     EnableUartControl = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_ENABLE_UART_CONTROL,1),
    // *** REFCLOCK ***
    parameter integer RefClockCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_REFCLOCK_COUNT,1),
    `OC_LOCALPARAM_SAFE(RefClockCount), // we won't need this, though, since it's mandatory to have one refclk for top
    parameter integer RefClockHz [0:RefClockCount-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_REFCLOCK_HZ,{156250000}),
    // *** TOP CLOCK ***
    parameter integer ClockTop = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_CLOCK_TOP,oc_top_pkg::ClockIdSingleEndedRef(0)),
    // *** LED ***
    parameter integer LedCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_LED_COUNT,3),
    `OC_LOCALPARAM_SAFE(LedCount),
    // *** UART ***
    parameter integer UartCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_COUNT,2),
    `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_BAUD,{460800,115200}),
    parameter integer UartControl = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL,0)
    )
  (
   // *** REFCLOCK ***
   input  USER_SI570_CLOCK_P, USER_SI570_CLOCK_N, // this is our generic refclk
   // *** LED ***
   output STATUS_LED0_FPGA, // red, bottom
   output STATUS_LED1_FPGA, // yellow, middle
   output STATUS_LED2_FPGA, // green, top
   // *** UART ***
   output USB_UART_RX,
   input  USB_UART_TX,
   input  FPGA_RXD_MSP,
   output FPGA_TXD_MSP
  );

  // *** REFCLK ***
  `OC_STATIC_ASSERT(RefClockCount>0);
  `OC_STATIC_ASSERT(RefClockCount<2);
  (* dont_touch = "yes" *)
  logic [RefClockCountSafe-1:0] clockRef;
  IBUFDS uIBUF_USER_SI570_CLOCK (.O(clockRef[0]), .I(USER_SI570_CLOCK_P), .IB(USER_SI570_CLOCK_N));

  // *** LED ***
  `OC_STATIC_ASSERT(LedCount<=3);
  (* dont_touch = "yes" *)
  logic [LedCountSafe-1:0]  ledOut, debugLed;
  if (LedCount>0) OBUF uIOBUF_STATUS_LED0_FPGA (.O(STATUS_LED0_FPGA), .I(ledOut[0]) );
  if (LedCount>1) OBUF uIOBUF_STATUS_LED1_FPGA (.O(STATUS_LED1_FPGA), .I(ledOut[1]) );
  if (LedCount>2) OBUF uIOBUF_STATUS_LED2_FPGA (.O(STATUS_LED2_FPGA), .I(ledOut[2]) );

  // *** UART ****
  `OC_STATIC_ASSERT(UartCount<=2);
  (* dont_touch = "yes" *)
  logic [UartCountSafe-1:0]     uartRx, uartTx, debugUartTx;

  if (UartCount>0) begin : uart0
    IBUF uIBUF_FPGA_RXD_MSP (.O(uartRx[1]), .I(FPGA_RXD_MSP));
    OBUF uOBUF_FPGA_TXD_MSP (.O(FPGA_TXD_MSP), .I(uartTx[1] && !debugUartTx[1]));
  end
  if (UartCount>1) begin : uart1
    IBUF uIBUF_USB_UART_TX (.O(uartRx[0]), .I(USB_UART_TX));
    OBUF uOBUF_USB_UART_RX (.O(USB_UART_RX), .I(uartTx[0] && !debugUartTx[0]));
  end



  // *** TOP DEBUG ***
  // The top level debug is for checking incoming clocks and resets, any board level errors in/out
  // (temperature etc), LED (monitor/drive), UART (monitor/drive).
  logic                     debugReset;

`ifdef OC_BOARD_TOP_DEBUG

  logic [27:0]            clockRefTopDivide = '0;
  always_ff @(posedge clockRef[ClockTop]) clockRefTopDivide <= (clockRefTopDivide + 'd1);

  `OC_DEBUG_VIO(uVIO, clockRef[ClockTop], 32, 32,
                { ~ledOut,ledOut,
                  debugReset, clockRefTopDivide[27],
                  debugUartTx, uartRx, uartTx},
                { debugLed, debugReset, debugUartTx });

`else // !`ifdef OC_CHIP_TOP_INCLUDE_VIO_DEBUG
  assign debugReset = '0;
  assign debugUartTx = '0;
  assign debugLed = '0;
`endif // !`ifdef OC_CHIP_TOP_INCLUDE_VIO_DEBUG

  // *******************************************
  // *****           COS INSTANCE          *****
  // *******************************************

  oc_cos #(
           // *** MISC ***
           .Seed(Seed),
           .EnableUartControl(EnableUartControl),
           // *** REFCLOCK ***
           .RefClockCount(RefClockCount),
           .RefClockHz(RefClockHz),
           // *** TOP CLOCK ***
           .ClockTop(ClockTop),
           // *** LED ***
           .LedCount(LedCount),
           // *** UART ***
           .UartCount(UartCount),
           .UartBaud(UartBaud),
           .UartControl(UartControl)
          )
  uCOS (
        // *** REFCLOCK ***
        .clockRef(clockRef),
        // *** RESET ***
        .hardReset(debugReset),
        // *** LED ***
        .ledOut(ledOut),
        // *** UART ***
        .uartRx(uartRx),
        .uartTx(uartTx)
        );

endmodule // oc_chip_top
