
// SPDX-License-Identifier: MPL-2.0

`include "boards/u200/oc_board_defines.vh"
`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_chip_harness
  #(
    // *** MISC ***
    parameter integer Seed = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_SEED,0), // seed to generate varying implementation results
    // *** REFCLOCK ***
    parameter integer RefClockCount = 1,
                      `OC_LOCALPARAM_SAFE(RefClockCount), // we won't need this, it's mandatory to have one refclk for top
    parameter integer RefClockHz [0:RefClockCount-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_REFCLOCK_HZ,{156_250_000}),
    parameter integer DiffRefClockCount = 2,
                      `OC_LOCALPARAM_SAFE(DiffRefClockCount),
    parameter integer DiffRefClockHz [0:DiffRefClockCountSafe-1] = '{DiffRefClockCountSafe{161_132_812}}, // freq, per DiffRefClock
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
    parameter integer UartBaud [0:UartCountSafe-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_BAUD,{460_800,115_200}),
    parameter integer UartControl = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL,0)

    )
  (
  // *** REFCLOCK ***
   input [RefClockCountSafe-1:0]       clockRef,
   input [DiffRefClockCount-1:0]       clockDiffRefP, clockDiffRefN,
   // *** RESET ***
   input                               hardReset,
   // *** CHIPMON ***
   input [ChipMonCountSafe-1:0]        chipMonScl = {ChipMonCountSafe{1'b1}},
   output logic [ChipMonCountSafe-1:0] chipMonSclTristate,
   input [ChipMonCountSafe-1:0]        chipMonSda = {ChipMonCountSafe{1'b1}},
   output logic [ChipMonCountSafe-1:0] chipMonSdaTristate,
   // *** IIC ***
   input [IicCountSafe-1:0]            iicScl = {IicCountSafe{1'b1}},
   output logic [IicCountSafe-1:0]     iicSclTristate,
   input [IicCountSafe-1:0]            iicSda = {IicCountSafe{1'b1}},
   output logic [IicCountSafe-1:0]     iicSdaTristate,
   // *** LED ***
   output [LedCountSafe-1:0]           ledOut,
   // *** GPIO ***
   output logic [GpioCountSafe-1:0]    gpioOut,
   output logic [GpioCountSafe-1:0]    gpioTristate,
   input [GpioCountSafe-1:0]           gpioIn = {GpioCountSafe{1'b0}},
   // *** FAN ***
   output logic [FanCountSafe-1:0]     fanPwm,
   input [FanCountSafe-1:0]            fanSense = {FanCountSafe{1'b0}},
   // *** UART ***
   input [UartCountSafe-1:0]           uartRx,
   output logic [UartCountSafe-1:0]    uartTx,
   // *** MISC ***
   output logic                        thermalWarning,
   output logic                        thermalError
   );

  always @(hardReset) uDUT.simulationReset = hardReset;

  oc_chip_top #(.Seed(Seed))
  uDUT (
        .USER_SI570_CLOCK_P(clockRef[0]), .USER_SI570_CLOCK_N(~clockRef[0]),
        .QSFP0_CLOCK_P(clockDiffRefP[0]), .QSFP0_CLOCK_N(clockDiffRefN[0]),
        .QSFP1_CLOCK_P(clockDiffRefP[1]), .QSFP1_CLOCK_N(clockDiffRefN[1]),
        .I2C_FPGA_SCL(), .I2C_FPGA_SDA(),
        .STATUS_LED0_FPGA(ledOut[0]), .STATUS_LED1_FPGA(ledOut[1]), .STATUS_LED2_FPGA(ledOut[2]),
        // NOTE: directionality wrong in u200.xdc comments... USB_UART_TX is INPUT (online docs are correct)
        .USB_UART_TX(uartRx[0]), .USB_UART_RX(uartTx[0]),
        .FPGA_RXD_MSP(uartRx[1]), .FPGA_TXD_MSP(uartTx[1])
        );

endmodule // oc_chip_harness
