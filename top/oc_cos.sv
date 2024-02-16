
// SPDX-License-Identifier: MPL-2.0

`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"
`include "lib/oclib_uart_pkg.sv"

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
    parameter integer DiffRefClockCount = 0,
                      `OC_LOCALPARAM_SAFE(DiffRefClockCount),
    parameter integer DiffRefClockHz [0:DiffRefClockCountSafe-1] = '{DiffRefClockCountSafe{156_250_000}}, // freq, per DiffRefClock

    // *** TOP CLOCK ***
    parameter integer ClockTop = oc_top_pkg::ClockIdSingleEndedRef(0),

    // *** PLL ***
    parameter integer PllCount = 1,
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
    parameter integer ChipMonCount = 0,
                      `OC_LOCALPARAM_SAFE(ChipMonCount),
    parameter bit     ChipMonCsrEnable [ChipMonCountSafe-1:0] = '{ ChipMonCountSafe { oclib_pkg::True } },
    parameter bit     ChipMonI2CEnable [ChipMonCountSafe-1:0] = '{ ChipMonCountSafe { oclib_pkg::True } },

    // *** IIC ***
    parameter integer IicCount = 0,
                      `OC_LOCALPARAM_SAFE(IicCount),
    parameter integer IicOffloadEnable = 0,

    // *** LED ***
    parameter integer LedCount = 0,
                      `OC_LOCALPARAM_SAFE(LedCount),

    // *** GPIO ***
    parameter integer GpioCount = 0,
                      `OC_LOCALPARAM_SAFE(GpioCount),

    // *** FAN ***
    parameter integer FanCount = 0,
                      `OC_LOCALPARAM_SAFE(FanCount),
     // *** UART ***
    parameter integer UartCount = 1,
                      `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = {115200},
    parameter integer UartControl = 0,

    // *******************************************************************************
    // ***                         INTERNAL CONFIGURATION                          ***
    // Configuring OC_COS internals which board can override in target-specific ways
    // *******************************************************************************

    // *** Physical type of Top-Level CSR bus (can be csr_*_s or bc_*_s) ***
    parameter         type CsrTopType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrTopFbType = oclib_pkg::bc_8b_bidi_s,
    // *** Message carried on Top-Level CSR bus (must be csr_*_s) ***
    parameter         type CsrTopProtocol = oclib_pkg::csr_32_tree_s,

    // *** Default reset pipelining for top blocks (which will be on a 100-200MHz refclk)
    parameter int     DefaultTopResetPipeline = 2
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
   output logic [LedCountSafe-1:0]     ledOut,
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

  // *******************************************************************************
  // *** INTERNAL FEATUERS ***

  // *** PROTECT ***
  parameter integer                    ProtectCount = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_PROTECT_COUNT,0);
  `OC_LOCALPARAM_SAFE(ProtectCount);
  logic [ProtectCountSafe-1:0] protectUnlocked;

  // *** DUMMY ***
  parameter integer                    DummyCount = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_COUNT,0);
  `OC_LOCALPARAM_SAFE(DummyCount);
  parameter integer                    DummyDatapathCount = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_COUNT,1);
  parameter integer                    DummyDatapathWidth = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_WIDTH,32);
  parameter integer                    DummyDatapathLogicLevels = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_LOGIC_LEVELS,8);
  parameter integer                    DummyDatapathPipeStages = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_PIPE_STAGES,8);
  parameter integer                    DummyDatapathLutInputs = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_LUT_INPUTS,4);

  // *******************************************************************************
  // *** RESOURCE CALCULATIONS ***

  localparam integer             BlockFirstChipMon = 0;
  localparam integer             BlockFirstIic = (BlockFirstChipMon + ChipMonCount);
  localparam integer             BlockFirstLed = (BlockFirstIic + IicCount);
  localparam integer             BlockFirstGpio = (BlockFirstLed + (LedCount ? 1 : 0)); // all LEDs are on one IP
  localparam integer             BlockFirstFan = (BlockFirstGpio + (GpioCount ? 1 : 0)); // all GPIOs are on one IP
  localparam integer             BlockFirstProtect = (BlockFirstFan + (FanCount ? 1 : 0)); // all FANs are on one IP
  localparam integer             BlockFirstDummy = (BlockFirstProtect + ProtectCount);
  localparam integer             BlockTopCount = (BlockFirstDummy + DummyCount);
  localparam integer             BlockUserCount = 0;
  localparam integer             BlockCount = (BlockTopCount + BlockUserCount);
  `OC_LOCALPARAM_SAFE(BlockCount);

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
  localparam integer             UartErrorWidth = oclib_uart_pkg::ErrorWidth;
  logic [UartErrorWidth-1:0]     uartError;

  if (EnableUartControl) begin : uart_control
    oc_uart_control
      #(.ClockHz(ClockTopHz),
        .Baud(UartBaud[UartControl]),
        .UartControlBcType(UartControlBcType),
        .UartControlProtocol(CsrTopProtocol),
        .BlockTopCount(BlockTopCount),
        .BlockUserCount(BlockUserCount),
        .ResetSync(oclib_pkg::False) )
    uCONTROL (.clock(clockTop), .reset(resetTop),
              .resetOut(resetFromUartControl), .uartError(uartError),
              .uartRx(uartRx[UartControl]), .uartTx(uartTx[UartControl]),
              .bcOut(uartBcOut), .bcIn(uartBcIn));
  end
  else begin
    assign resetFromUartControl = 1'b0;
    assign blink = 1'b0;
  end

  // *******************************************************************************
  // *** TOP_CSR_SPLIT ***

  CsrTopType                     csrTop [BlockCountSafe];
  CsrTopFbType                   csrTopFb [BlockCountSafe];
  logic                          resetFromTopCsrSplitter;

  oclib_csr_tree_splitter #(.CsrInType(UartControlBcType), .CsrInFbType(UartControlBcType),
                            .CsrInProtocol(CsrTopProtocol),
                            .CsrOutType(CsrTopType), .CsrOutFbType(CsrTopFbType),
                            .CsrOutProtocol(CsrTopProtocol),
                            .Outputs(BlockCount) )
  uTOP_CSR_SPLITTER (.clock(clockTop), .reset(resetTop),
                     .resetRequest(resetFromTopCsrSplitter),
                     .in(uartBcOut), .inFb(uartBcIn),
                     .out(csrTop), .outFb(csrTopFb));

  // *******************************************************************************
  // *** CHIPMON ***

  logic [ChipMonCountSafe-1:0]   chipMonThermalWarning;
  logic [ChipMonCountSafe-1:0]   chipMonThermalError;
  logic                          chipMonMergedThermalWarning;
  logic                          chipMonMergedThermalError;
  for (genvar i=0; i<ChipMonCount; i++) begin : chipmon
    oc_chipmon #(.ClockHz(ClockTopHz),
                 .CsrType(CsrTopType), .CsrFbType(CsrTopFbType), .CsrProtocol(CsrTopProtocol),
                 .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uCHIPMON (.clock(clockTop), .reset(resetTop),
              .csr(csrTop[BlockFirstChipMon+i]), .csrFb(csrTopFb[BlockFirstChipMon+i]),
              .scl(chipMonScl[i]), .sclTristate(chipMonSclTristate[i]),
              .sda(chipMonSda[i]), .sdaTristate(chipMonSdaTristate[i]),
              .thermalWarning(chipMonThermalWarning[i]), .thermalError(chipMonThermalError[i]));
  end
  if (ChipMonCount==0) begin
    assign chipMonThermalWarning = '0;
    assign chipMonThermalError = '0;
  end
  assign chipMonMergedThermalWarning = (|chipMonThermalWarning);
  assign chipMonMergedThermalError = (|chipMonThermalError);

  // *******************************************************************************
  // *** IIC ***

  for (genvar i=0; i<IicCount; i++) begin : iic
    oc_iic #(.ClockHz(ClockTopHz), .OffloadEnable(IicOffloadEnable),
             .CsrType(CsrTopType), .CsrFbType(CsrTopFbType), .CsrProtocol(CsrTopProtocol),
             .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uIIC (.clock(clockTop), .reset(resetTop),
          .csr(csrTop[BlockFirstIic+i]), .csrFb(csrTopFb[BlockFirstIic+i]),
          .iicScl(iicScl), .iicSclTristate(iicSclTristate),
          .iicSda(iicSda), .iicSdaTristate(iicSdaTristate));
  end
  if (IicCount == 0) begin
    assign iicSclTristate = { IicCountSafe { 1'b1 }};
    assign iicSdaTristate = { IicCountSafe { 1'b1 }};
  end

  // *******************************************************************************
  // *** LED ***

  if (LedCount) begin : led
    oc_led #(.ClockHz(ClockTopHz), .LedCount(LedCount),
             .CsrType(CsrTopType), .CsrFbType(CsrTopFbType), .CsrProtocol(CsrTopProtocol),
             .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uLED (.clock(clockTop), .reset(resetTop),
          .csr(csrTop[BlockFirstLed]), .csrFb(csrTopFb[BlockFirstLed]),
          .ledOut(ledOut));
  end
  else begin
    assign ledOut = '0;
  end

  // *******************************************************************************
  // *** GPIO ***

  if (GpioCount) begin
    oc_gpio #(.ClockHz(ClockTopHz), .GpioCount(GpioCount),
              .CsrType(CsrTopType), .CsrFbType(CsrTopFbType), .CsrProtocol(CsrTopProtocol),
              .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uGPIO (.clock(clockTop), .reset(resetTop),
           .csr(csrTop[BlockFirstGpio]), .csrFb(csrTopFb[BlockFirstGpio]),
           .gpioOut(gpioOut), .gpioTristate(gpioTristate), .gpioIn(gpioIn));
  end
  else begin
    assign gpioOut = '0;
    assign gpioTristate = '1;
  end

  // *******************************************************************************
  // *** FAN ***

  if (FanCount) begin
    oc_fan #(.ClockHz(ClockTopHz), .FanCount(FanCount),
              .CsrType(CsrTopType), .CsrFbType(CsrTopFbType), .CsrProtocol(CsrTopProtocol),
              .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uFAN (.clock(clockTop), .reset(resetTop),
          .csr(csrTop[BlockFirstGpio]), .csrFb(csrTopFb[BlockFirstGpio]),
          .fanPwm(fanPwm), .fanSense(fanSense));
  end
  else begin
    assign fanPwm = '0;
  end

  // *******************************************************************************
  // *** PROTECT ***

  for (genvar i=0; i<ProtectCount; i++) begin : protect
    oc_protect #(.ClockHz(ClockTopHz),
                 .CsrType(CsrTopType), .CsrFbType(CsrTopFbType), .CsrProtocol(CsrTopProtocol),
                 .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uPROTECT (.clock(clockTop), .reset(resetTop),
              .csr(csrTop[BlockFirstProtect+i]), .csrFb(csrTopFb[BlockFirstProtect+i]),
              .unlocked(protectUnlocked[i]));
  end

  // *******************************************************************************
  // *** DUMMY ***

  for (genvar i=0; i<DummyCount; i++) begin : dummy
    oc_dummy #(.DatapathCount(DummyDatapathCount), .DatapathWidth(DummyDatapathWidth),
               .DatapathLogicLevels(DummyDatapathLogicLevels), .DatapathPipeStages(DummyDatapathPipeStages),
               .DatapathLutInputs(DummyDatapathLutInputs),
               .CsrType(CsrTopType), .CsrFbType(CsrTopFbType), .CsrProtocol(CsrTopProtocol),
               .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uDUMMY (.clock(clockTop), .reset(resetTop),
            .csr(csrTop[BlockFirstDummy+i]), .csrFb(csrTopFb[BlockFirstDummy+i]));
  end

  // *******************************************************************************
  // *** Merge Error Status ***

  assign thermalError = 1'b0;
  assign thermalWarning = chipMonMergedThermalWarning;

  // *******************************************************************************
  // *** idle unused UARTs for now ***

  for (genvar i=0; i<UartCount; i++) begin
    if (i != UartControl) begin
      assign uartTx[i] = 1'b1;
    end
  end

endmodule // oc_cos
