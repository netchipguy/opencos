
// SPDX-License-Identifier: MPL-2.0

`include "boards/u200/oc_board_defines.vh"
`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_chip_top
  #(
    // *** MISC ***
    parameter integer Seed = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_SEED,0), // seed to generate varying implementation results
    parameter bit     EnableUartControl = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_ENABLE_UART_CONTROL,1),

    // *** REFCLOCK ***
    parameter integer RefClockCount = 1,
                      `OC_LOCALPARAM_SAFE(RefClockCount), // we won't need this, it's mandatory to have one refclk for top
    parameter integer RefClockHz [0:RefClockCount-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_REFCLOCK_HZ,{156250000}),
    parameter integer DiffRefClockCount = 2,
                      `OC_LOCALPARAM_SAFE(DiffRefClockCount),
    parameter integer DiffRefClockHz [0:DiffRefClockCountSafe-1] = '{DiffRefClockCountSafe{161132812}}, // freq, per DiffRefClock

    // *** TOP CLOCK ***
    parameter integer ClockTop = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_CLOCK_TOP,oc_top_pkg::ClockIdSingleEndedRef(0)),

    // *** PLL ***
    parameter integer PllCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PLL_COUNT,1),
                      `OC_LOCALPARAM_SAFE(PllCount),
    parameter integer PllCountMax = 8,
    parameter integer PllClockRef [0:PllCountSafe-1] = '{ PllCountSafe { 0 } }, // reference clock, per PLL
    parameter bit     PllCsrEnable [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::False } }, // whether to include CSRs, per PLL
    parameter bit     PllMeasureEnable [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::False } }, // enable clock measure, per PLL
    parameter integer PllClockHz [0:PllCountMax-1] = '{ // per PLL
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL0_CLK_HZ,400_000_000),
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL1_CLK_HZ,350_000_000),
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL2_CLK_HZ,300_000_000),
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL3_CLK_HZ,250_000_000),
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL4_CLK_HZ,200_000_000),
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL5_CLK_HZ,166_666_666),
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL6_CLK_HZ,150_000_000),
                                                        `OC_VAL_ASDEFINED_ELSE(TARGET_PLL7_CLK_HZ,133_333_333) },

    // *** CHIPMON ***
    parameter integer ChipMonCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_CHIPMON_COUNT,1),
                      `OC_LOCALPARAM_SAFE(ChipMonCount),
    parameter bit     ChipMonCsrEnable [ChipMonCountSafe-1:0] = '{ ChipMonCountSafe { oclib_pkg::True } },
    parameter bit     ChipMonI2CEnable [ChipMonCountSafe-1:0] = '{ ChipMonCountSafe { oclib_pkg::True } },

    // *** IIC ***
    parameter integer IicCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_IIC_COUNT,1),
                      `OC_LOCALPARAM_SAFE(IicCount),
    parameter integer IicOffloadEnable = `OC_VAL_IFDEF(OC_BOARD_IIC_OFFLOAD_ENABLE),

    // *** LED ***
    parameter integer LedCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_LED_COUNT,3),
                      `OC_LOCALPARAM_SAFE(LedCount),

    // *** GPIO ***
    parameter integer GpioCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_GPIO_COUNT,17),
                      `OC_LOCALPARAM_SAFE(GpioCount),

    // *** FAN ***
    parameter integer FanCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_FAN_COUNT,0),
                      `OC_LOCALPARAM_SAFE(FanCount),

    // *** UART ***
    parameter integer UartCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_COUNT,2),
                      `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_BAUD,{460800,115200}),
    parameter integer UartControl = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL,0)
    )
  (
   // *** REFCLOCK ***
   input       USER_SI570_CLOCK_P, USER_SI570_CLOCK_N, // this is our generic refclk
   input       QSFP0_CLOCK_P, QSFP0_CLOCK_N,
   input       QSFP1_CLOCK_P, QSFP1_CLOCK_N,
   // *** IIC ***
   inout       I2C_FPGA_SCL,
   inout       I2C_FPGA_SDA,
    // *** LED ***
   output      STATUS_LED0_FPGA, // red, bottom
   output      STATUS_LED1_FPGA, // yellow, middle
   output      STATUS_LED2_FPGA, // green, top
   // *** GPIO ***
   inout       QSFP0_RESETL, QSFP0_MODPRSL, QSFP0_INTL, QSFP0_LPMODE, QSFP0_MODSELL, QSFP0_REFCLK_RESET,
   inout [1:0] QSFP0_FS,
   inout       QSFP1_RESETL, QSFP1_MODPRSL, QSFP1_INTL, QSFP1_LPMODE, QSFP1_MODSELL, QSFP1_REFCLK_RESET,
   inout [1:0] QSFP1_FS,
   inout       I2C_MAIN_RESETN,
   // *** UART ***
   input       USB_UART_TX, // NOTE: directionality wrong in u200.xdc comments... USB_UART_TX is INPUT (online docs are correct)
   output      USB_UART_RX,
   input       FPGA_RXD_MSP,
   output      FPGA_TXD_MSP
  );

  // *** REFCLK ***
  `OC_STATIC_ASSERT(RefClockCount>0);
  `OC_STATIC_ASSERT(RefClockCount<2);
  (* dont_touch = "yes" *)
  logic [RefClockCountSafe-1:0] clockRef;
  IBUFDS uIBUF_USER_SI570_CLOCK (.O(clockRef[0]), .I(USER_SI570_CLOCK_P), .IB(USER_SI570_CLOCK_N));

  logic [DiffRefClockCount-1:0] clockDiffRefP;
  logic [DiffRefClockCount-1:0] clockDiffRefN;

  assign clockDiffRefP[0] = QSFP0_CLOCK_P;
  assign clockDiffRefN[0] = QSFP0_CLOCK_N;
  assign clockDiffRefP[1] = QSFP1_CLOCK_P;
  assign clockDiffRefN[1] = QSFP1_CLOCK_N;

  // *** CHIPMON ***
  logic [ChipMonCountSafe-1:0]  chipMonScl;
  logic [ChipMonCountSafe-1:0]  chipMonSclTristate;
  logic [ChipMonCountSafe-1:0]  chipMonSda;
  logic [ChipMonCountSafe-1:0]  chipMonSdaTristate;
  assign chipMonScl = 1'b1;
  assign chipMonSda = 1'b1;

  // *** IIC ***
  `OC_STATIC_ASSERT(IicCount<=1);
  logic [IicCountSafe-1:0]  iicScl;
  logic [IicCountSafe-1:0]  iicSclTristate;
  logic [IicCountSafe-1:0]  iicSda;
  logic [IicCountSafe-1:0]  iicSdaTristate;
  if (IicCount) begin
    IOBUF uIOBUF_I2C_FPGA_SCL (.IO(I2C_FPGA_SCL), .I(1'b0), .T(iicSclTristate[0]),  .O(iicScl[0]) );
    IOBUF uIOBUF_I2C_FPGA_SDA (.IO(I2C_FPGA_SDA), .I(1'b0), .T(iicSdaTristate[0]),  .O(iicSda[0]) );
  end

  // *** LED ***
  `OC_STATIC_ASSERT(LedCount<=3);
  (* dont_touch = "yes" *)
  logic [LedCountSafe-1:0]  ledOut, debugLed;
  if (LedCount>0) OBUF uIOBUF_STATUS_LED0_FPGA (.O(STATUS_LED0_FPGA), .I(ledOut[0]) );
  if (LedCount>1) OBUF uIOBUF_STATUS_LED1_FPGA (.O(STATUS_LED1_FPGA), .I(ledOut[1]) );
  if (LedCount>2) OBUF uIOBUF_STATUS_LED2_FPGA (.O(STATUS_LED2_FPGA), .I(ledOut[2]) );

  // **** GPIO ***
  logic [GpioCountSafe-1:0]  gpioOut;
  logic [GpioCountSafe-1:0]  gpioTristate;
  logic [GpioCountSafe-1:0]  gpioIn;
  if (GpioCount) begin
    IOBUF uIOBUF_QSFP0_RESETL       (.IO(QSFP0_RESETL),       .I(gpioOut[ 0]), .T(gpioTristate[ 0]), .O(gpioIn[ 0]));
    IOBUF uIOBUF_QSFP0_MODPRSL      (.IO(QSFP0_MODPRSL),      .I(gpioOut[ 1]), .T(gpioTristate[ 1]), .O(gpioIn[ 1]));
    IOBUF uIOBUF_QSFP0_INTL         (.IO(QSFP0_INTL),         .I(gpioOut[ 2]), .T(gpioTristate[ 2]), .O(gpioIn[ 2]));
    IOBUF uIOBUF_QSFP0_LPMODE       (.IO(QSFP0_LPMODE),       .I(gpioOut[ 3]), .T(gpioTristate[ 3]), .O(gpioIn[ 3]));
    IOBUF uIOBUF_QSFP0_MODSELL      (.IO(QSFP0_MODSELL),      .I(gpioOut[ 4]), .T(gpioTristate[ 4]), .O(gpioIn[ 4]));
    IOBUF uIOBUF_QSFP0_FS_0         (.IO(QSFP0_FS[0]),        .I(gpioOut[ 5]), .T(gpioTristate[ 5]), .O(gpioIn[ 5]));
    IOBUF uIOBUF_QSFP0_FS_1         (.IO(QSFP0_FS[1]),        .I(gpioOut[ 6]), .T(gpioTristate[ 6]), .O(gpioIn[ 6]));
    IOBUF uIOBUF_QSFP0_REFCLK_RESET (.IO(QSFP0_REFCLK_RESET), .I(gpioOut[ 7]), .T(gpioTristate[ 7]), .O(gpioIn[ 7]));
    IOBUF uIOBUF_QSFP1_RESETL       (.IO(QSFP1_RESETL),       .I(gpioOut[ 8]), .T(gpioTristate[ 8]), .O(gpioIn[ 8]));
    IOBUF uIOBUF_QSFP1_MODPRSL      (.IO(QSFP1_MODPRSL),      .I(gpioOut[ 9]), .T(gpioTristate[ 9]), .O(gpioIn[ 9]));
    IOBUF uIOBUF_QSFP1_INTL         (.IO(QSFP1_INTL),         .I(gpioOut[10]), .T(gpioTristate[10]), .O(gpioIn[10]));
    IOBUF uIOBUF_QSFP1_LPMODE       (.IO(QSFP1_LPMODE),       .I(gpioOut[11]), .T(gpioTristate[11]), .O(gpioIn[11]));
    IOBUF uIOBUF_QSFP1_MODSELL      (.IO(QSFP1_MODSELL),      .I(gpioOut[12]), .T(gpioTristate[12]), .O(gpioIn[12]));
    IOBUF uIOBUF_QSFP1_FS_0         (.IO(QSFP1_FS[0]),        .I(gpioOut[13]), .T(gpioTristate[13]), .O(gpioIn[13]));
    IOBUF uIOBUF_QSFP1_FS_1         (.IO(QSFP1_FS[1]),        .I(gpioOut[14]), .T(gpioTristate[14]), .O(gpioIn[14]));
    IOBUF uIOBUF_QSFP1_REFCLK_RESET (.IO(QSFP1_REFCLK_RESET), .I(gpioOut[15]), .T(gpioTristate[15]), .O(gpioIn[15]));
    IOBUF uIOBUF_I2C_MAIN_RESETN    (.IO(I2C_MAIN_RESETN),    .I(gpioOut[16]), .T(gpioTristate[16]), .O(gpioIn[16]));
  end

  // *** UART ****
  `OC_STATIC_ASSERT(UartCount<=2);
  (* dont_touch = "yes" *)
  logic [UartCountSafe-1:0]     uartRx, uartTx, debugUartTx;

  if (UartCount>0) begin : uart1
    // NOTE: directionality of these are wrong in u200.xdc comments... USB_UART_TX is an INPUT (online docs are correct)
    IBUF uIBUF_USB_UART_TX (.O(uartRx[0]), .I(USB_UART_TX));
    OBUF uOBUF_USB_UART_RX (.O(USB_UART_RX), .I(uartTx[0] && !debugUartTx[0]));
  end
  if (UartCount>1) begin : uart0
    IBUF uIBUF_FPGA_RXD_MSP (.O(uartRx[1]), .I(FPGA_RXD_MSP));
    OBUF uOBUF_FPGA_TXD_MSP (.O(FPGA_TXD_MSP), .I(uartTx[1] && !debugUartTx[1]));
  end



  // *** TOP DEBUG ***
  // The top level debug is for checking incoming clocks and resets, any board level errors in/out
  // (temperature etc), LED (monitor/drive), UART (monitor/drive).
  logic                     debugReset;
  logic                     simulationReset = 0;

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
           .DiffRefClockCount(DiffRefClockCount),
           .DiffRefClockHz(DiffRefClockHz),
           // *** TOP CLOCK ***
           .ClockTop(ClockTop),
           // *** PLL ***
           .PllCount(PllCount),
           .PllCountMax(PllCountMax),
           .PllClockRef(PllClockRef),
           .PllCsrEnable(PllCsrEnable),
           .PllMeasureEnable(PllMeasureEnable),
           .PllClockHz(PllClockHz),
           // *** CHIPMON ***
           .ChipMonCount(ChipMonCount),
           .ChipMonCsrEnable(ChipMonCsrEnable),
           .ChipMonI2CEnable(ChipMonI2CEnable),
           // *** IIC ***
           .IicCount(IicCount),
           .IicOffloadEnable(IicOffloadEnable),
           // *** LED ***
           .LedCount(LedCount),
           // *** GPIO ***
           .GpioCount(GpioCount),
           // *** UART ***
           .UartCount(UartCount),
           .UartBaud(UartBaud),
           .UartControl(UartControl)
          )
  uCOS (
        // *** REFCLOCK ***
        .clockRef(clockRef),
        .clockDiffRefP(clockDiffRefP), .clockDiffRefN(clockDiffRefN),
        // *** RESET ***
        .hardReset(debugReset||simulationReset),
        // *** CHIPMON ***
        .chipMonScl(chipMonScl), .chipMonSclTristate(chipMonSclTristate),
        .chipMonSda(chipMonSda), .chipMonSdaTristate(chipMonSdaTristate),
        // *** IIC ***
        .iicScl(iicScl), .iicSclTristate(iicSclTristate),
        .iicSda(iicSda), .iicSdaTristate(iicSdaTristate),
        // *** LED ***
        .ledOut(ledOut),
        // *** GPIO ***
        .gpioOut(gpioOut), .gpioTristate(gpioTristate), .gpioIn(gpioIn),
        // *** UART ***
        .uartRx(uartRx),
        .uartTx(uartTx)
        );

endmodule // oc_chip_top
