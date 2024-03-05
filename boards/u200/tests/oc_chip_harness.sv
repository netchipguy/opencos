
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
    parameter integer DiffRefClockCount = 3,
                      `OC_LOCALPARAM_SAFE(DiffRefClockCount),
    parameter integer DiffRefClockHz [0:DiffRefClockCountSafe-1] = '{161_132_812,
                                                                     161_132_812,
                                                                     100_000_000}, // freq per DiffRefClock
    // *** TOP CLOCK ***
    parameter integer ClockTop = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_CLOCK_TOP,oc_top_pkg::ClockIdSingleEndedRef(0)),

    // *** PLL ***
    parameter integer PllCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PLL_COUNT,1),
                      `OC_LOCALPARAM_SAFE(PllCount),
    parameter integer PllCountMax = 8,
    parameter integer PllClockRef [0:PllCountSafe-1] = '{ PllCountSafe { 0 } }, // reference clock, per PLL
    parameter bit     PllCsrEnable [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // whether to include CSRs, per PLL
    parameter bit     PllMeasureEnable [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // enable clock measure, per PLL
    parameter bit     PllThrottleMap [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // throttle map, per PLL
    parameter bit     PllAutoThrottle [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // thermal auto throttle, per PLL
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
    parameter integer UartBaud [0:UartCountSafe-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_BAUD,{10_000_000,115_200}),
    parameter bit     UartControlEnable = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL_ENABLE,1),
    parameter integer UartControlSelect = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL_SELECT,0),

    // *** PCIE ***
    parameter integer PcieCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_COUNT,1),
                      `OC_LOCALPARAM_SAFE(PcieCount),
    parameter integer PcieWidth [PcieCountSafe-1:0] = '{ PcieCountSafe { 1 } },
    parameter integer PcieWidthMax = 16,
    parameter integer PcieGen [PcieCountSafe-1:0] = '{ PcieCountSafe { 3 } },
    parameter integer PcieDiffRefClock [PcieCountSafe-1:0] = '{ PcieCountSafe { 2 } }, // PCIE_REFCLK_P is diffrefclk #2
    parameter bit     PcieControlEnable = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_CONTROL_ENABLE,0),
    parameter integer PcieControlSelect = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_CONTROL_SELECT,0)
    )
  (
  // *** REFCLOCK ***
   input [RefClockCountSafe-1:0]                       clockRef,
   input [DiffRefClockCount-1:0]                       clockDiffRefP, clockDiffRefN,
   // *** RESET ***
   input                                               hardReset,
   // *** CHIPMON ***
   input [ChipMonCountSafe-1:0]                        chipMonScl = {ChipMonCountSafe{1'b1}},
   output logic [ChipMonCountSafe-1:0]                 chipMonSclTristate,
   input [ChipMonCountSafe-1:0]                        chipMonSda = {ChipMonCountSafe{1'b1}},
   output logic [ChipMonCountSafe-1:0]                 chipMonSdaTristate,
   // *** IIC ***
   input [IicCountSafe-1:0]                            iicScl = {IicCountSafe{1'b1}},
   output logic [IicCountSafe-1:0]                     iicSclTristate,
   input [IicCountSafe-1:0]                            iicSda = {IicCountSafe{1'b1}},
   output logic [IicCountSafe-1:0]                     iicSdaTristate,
   // *** LED ***
   output [LedCountSafe-1:0]                           ledOut,
   // *** GPIO ***
   output logic [GpioCountSafe-1:0]                    gpioOut,
   output logic [GpioCountSafe-1:0]                    gpioTristate,
   input [GpioCountSafe-1:0]                           gpioIn = {GpioCountSafe{1'b0}},
   // *** FAN ***
   output logic [FanCountSafe-1:0]                     fanPwm,
   input [FanCountSafe-1:0]                            fanSense = {FanCountSafe{1'b0}},
   // *** UART ***
   input [UartCountSafe-1:0]                           uartRx,
   output logic [UartCountSafe-1:0]                    uartTx,
   // *** PCIe ***
   input [PcieCountSafe-1:0]                           pcieReset,
   output logic [PcieCountSafe-1:0] [PcieWidthMax-1:0] pcieTxP,
   output logic [PcieCountSafe-1:0] [PcieWidthMax-1:0] pcieTxN,
   input [PcieCountSafe-1:0] [PcieWidthMax-1:0]        pcieRxP = { PcieCountSafe * PcieWidthMax { 1'b0 } },
   input [PcieCountSafe-1:0] [PcieWidthMax-1:0]        pcieRxN = { PcieCountSafe * PcieWidthMax { 1'b1 } },
   // *** MISC ***
   output logic                                        thermalWarning,
   output logic                                        thermalError
   );

  always @(hardReset) uDUT.simulationReset = hardReset;

  oc_chip_top #(.Seed(Seed), .UartBaud(UartBaud)) // the baud is the only thing we override
  uDUT (
        // *** REFCLOCK ***
        .USER_SI570_CLOCK_P(clockRef[0]), .USER_SI570_CLOCK_N(~clockRef[0]),
        .QSFP0_CLOCK_P(clockDiffRefP[0]), .QSFP0_CLOCK_N(clockDiffRefN[0]),
        .QSFP1_CLOCK_P(clockDiffRefP[1]), .QSFP1_CLOCK_N(clockDiffRefN[1]),
        .PCIE_REFCLK_P(clockDiffRefP[2]), .PCIE_REFCLK_N(clockDiffRefN[2]),
        .I2C_FPGA_SCL(), .I2C_FPGA_SDA(),
        // *** RESET ***
        // *** CHIPMON ***
        // *** IIC ***
        // *** LED ***
        .STATUS_LED0_FPGA(ledOut[0]), .STATUS_LED1_FPGA(ledOut[1]), .STATUS_LED2_FPGA(ledOut[2]),
        // *** GPIO ***
        // *** UART ***
        // NOTE: directionality wrong in u200.xdc comments... USB_UART_TX is INPUT (online docs are correct)
        .USB_UART_TX(uartRx[0]), .USB_UART_RX(uartTx[0]),
        .FPGA_RXD_MSP(uartRx[1]), .FPGA_TXD_MSP(uartTx[1]),
        // *** PCIe ***
`ifdef OC_BOARD_PCIE_X1
        .PEX_RX0_P(pcieRxP[0][0]), .PEX_RX0_N(pcieRxN[0][0]),
        .PEX_TX0_P(pcieTxP[0][0]), .PEX_TX0_N(pcieTxN[0][0]),
`endif
`ifdef OC_BOARD_PCIE_X2
        .PEX_RX1_P(pcieRxP[0][1]), .PEX_RX1_N(pcieRxN[0][1]),
        .PEX_TX1_P(pcieTxP[0][1]), .PEX_TX1_N(pcieTxN[0][1]),
`endif
`ifdef OC_BOARD_PCIE_X4
        .PEX_RX2_P(pcieRxP[0][2]), .PEX_RX2_N(pcieRxN[0][2]), .PEX_RX3_P(pcieRxP[0][3]), .PEX_RX3_N(pcieRxN[0][3]),
        .PEX_TX2_P(pcieTxP[0][2]), .PEX_TX2_N(pcieTxN[0][2]), .PEX_TX3_P(pcieTxP[0][3]), .PEX_TX3_N(pcieTxN[0][3]),
`endif
`ifdef OC_BOARD_PCIE_X8
        .PEX_RX4_P(pcieRxP[0][4]), .PEX_RX4_N(pcieRxN[0][4]), .PEX_RX5_P(pcieRxP[0][5]), .PEX_RX5_N(pcieRxN[0][5]),
        .PEX_RX6_P(pcieRxP[0][6]), .PEX_RX6_N(pcieRxN[0][6]), .PEX_RX7_P(pcieRxP[0][7]), .PEX_RX7_N(pcieRxN[0][7]),
        .PEX_TX4_P(pcieTxP[0][4]), .PEX_TX4_N(pcieTxN[0][4]), .PEX_TX5_P(pcieTxP[0][5]), .PEX_TX5_N(pcieTxN[0][5]),
        .PEX_TX6_P(pcieTxP[0][6]), .PEX_TX6_N(pcieTxN[0][6]), .PEX_TX7_P(pcieTxP[0][7]), .PEX_TX7_N(pcieTxN[0][7]),
`endif
`ifdef OC_BOARD_PCIE_X16
        .PEX_RX8_P (pcieRxP[0][ 8]), .PEX_RX8_N (pcieRxN[0][ 8]), .PEX_RX9_P (pcieRxP[0][ 9]), .PEX_RX9_N (pcieRxN[0][ 9]),
        .PEX_RX10_P(pcieRxP[0][10]), .PEX_RX10_N(pcieRxN[0][10]), .PEX_RX11_P(pcieRxP[0][11]), .PEX_RX11_N(pcieRxN[0][11]),
        .PEX_RX12_P(pcieRxP[0][12]), .PEX_RX12_N(pcieRxN[0][12]), .PEX_RX13_P(pcieRxP[0][13]), .PEX_RX13_N(pcieRxN[0][13]),
        .PEX_RX14_P(pcieRxP[0][14]), .PEX_RX14_N(pcieRxN[0][14]), .PEX_RX15_P(pcieRxP[0][15]), .PEX_RX15_N(pcieRxN[0][15]),
        .PEX_TX8_P (pcieTxP[0][ 8]), .PEX_TX8_N (pcieTxN[0][ 8]), .PEX_TX9_P (pcieTxP[0][ 9]), .PEX_TX9_N (pcieTxN[0][ 9]),
        .PEX_TX10_P(pcieTxP[0][10]), .PEX_TX10_N(pcieTxN[0][10]), .PEX_TX11_P(pcieTxP[0][11]), .PEX_TX11_N(pcieTxN[0][11]),
        .PEX_TX12_P(pcieTxP[0][12]), .PEX_TX12_N(pcieTxN[0][12]), .PEX_TX13_P(pcieTxP[0][13]), .PEX_TX13_N(pcieTxN[0][13]),
        .PEX_TX14_P(pcieTxP[0][14]), .PEX_TX14_N(pcieTxN[0][14]), .PEX_TX15_P(pcieTxP[0][15]), .PEX_TX15_N(pcieTxN[0][15]),
`endif
        .PCIE_PERST(!pcieReset[0])
        // *** MISC ***
        );

endmodule // oc_chip_harness
