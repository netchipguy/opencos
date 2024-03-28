
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
    parameter integer  Seed = 0,

    // *** REFCLOCK ***
    parameter integer  RefClockCount = 1,
                       `OC_LOCALPARAM_SAFE(RefClockCount),
    parameter integer  RefClockHz [0:RefClockCount-1] = {100_000_000},
    parameter integer  DiffRefClockCount = 0,
                       `OC_LOCALPARAM_SAFE(DiffRefClockCount),
    parameter integer  DiffRefClockHz [0:DiffRefClockCountSafe-1] = '{DiffRefClockCountSafe{156_250_000}}, // freq, per DiffRefClock

    // *** TOP CLOCK ***
    parameter integer  ClockTop = oc_top_pkg::ClockIdSingleEndedRef(0),

    // *** PLL ***
    parameter integer  PllCount = 1,
                       `OC_LOCALPARAM_SAFE(PllCount),
    parameter integer  PllCountMax = 8,
    localparam integer PllClocksEach = 1,
    parameter integer  PllClockRef [0:PllCountSafe-1] = '{ PllCountSafe { 0 } }, // reference clock, per PLL
    parameter bit      PllCsrEnable [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // whether to include CSRs, per PLL
    parameter bit      PllMeasureEnable [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // clock measure, per PLL
    parameter bit      PllThrottleMap [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // throttle map, per PLL
    parameter bit      PllAutoThrottle [0:PllCountSafe-1] = '{ PllCountSafe { oclib_pkg::True } }, // thermal auto throttle, per PLL
    parameter integer  PllClockHz [0:PllCountMax-1] = '{ // per PLL
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL0_CLK_HZ,400_000_000),
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL1_CLK_HZ,350_000_000),
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL2_CLK_HZ,300_000_000),
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL3_CLK_HZ,250_000_000),
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL4_CLK_HZ,200_000_000),
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL5_CLK_HZ,166_666_666),
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL6_CLK_HZ,150_000_000),
                       `OC_VAL_ASDEFINED_ELSE(TARGET_PLL7_CLK_HZ,133_333_333) },

    // *** CHIPMON ***
    parameter integer  ChipMonCount = 0,
                       `OC_LOCALPARAM_SAFE(ChipMonCount),
    parameter bit      ChipMonCsrEnable [ChipMonCountSafe-1:0] = '{ ChipMonCountSafe { oclib_pkg::True } },
    parameter bit      ChipMonI2CEnable [ChipMonCountSafe-1:0] = '{ ChipMonCountSafe { oclib_pkg::True } },

    // *** IIC ***
    parameter integer  IicCount = 0,
                       `OC_LOCALPARAM_SAFE(IicCount),
    parameter integer  IicOffloadEnable = 0,

    // *** LED ***
    parameter integer  LedCount = 0,
                       `OC_LOCALPARAM_SAFE(LedCount),

    // *** GPIO ***
    parameter integer  GpioCount = 0,
                       `OC_LOCALPARAM_SAFE(GpioCount),

    // *** FAN ***
    parameter integer  FanCount = 0,
                       `OC_LOCALPARAM_SAFE(FanCount),
     // *** UART ***
    parameter integer  UartCount = 1,
                       `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer  UartBaud [0:UartCountSafe-1] = {115200},
    parameter bit      UartControlEnable = oclib_pkg::False,
    parameter bit      UartControlAxil = oclib_pkg::False,
    parameter integer  UartControlSelect = 0,

    // *** PCIe ***
    parameter integer  PcieCount = 0,
                       `OC_LOCALPARAM_SAFE(PcieCount),
    parameter integer  PcieWidth [PcieCountSafe-1:0] = '{ PcieCountSafe { 1 } },
    parameter integer  PcieWidthMax = 16,
    parameter integer  PcieGen [PcieCountSafe-1:0] = '{ PcieCountSafe { 3 } },
    parameter integer  PcieDiffRefClock [PcieCountSafe-1:0] = '{ PcieCountSafe { 0 } },
    parameter bit      PcieControlEnable = oclib_pkg::False,
    parameter integer  PcieControlSelect = 0,

    // *******************************************************************************
    // ***                         INTERNAL CONFIGURATION                          ***
    // Configuring OC_COS internals which board can override in target-specific ways
    // *******************************************************************************

    // *** Physical type of Top-Level CSR bus (can be csr_*_s or bc_*_s) ***
    parameter          type TopCsrType = oclib_pkg::bc_8b_bidi_s,
    parameter          type TopCsrFbType = oclib_pkg::bc_8b_bidi_s,
    // *** Message carried on Top-Level CSR bus (must be csr_*_s) ***
    parameter          type TopCsrProtocol = oclib_pkg::csr_32_tree_s,
    parameter          type TopCsrFbProtocol = oclib_pkg::csr_32_tree_fb_s,
    // *** we create these versions so we can do imperfect-but-helpful type comparisons
    localparam int     TopCsrTypeW = $bits(TopCsrType),
    localparam int     TopCsrFbTypeW = $bits(TopCsrFbType),
    localparam int     TopCsrProtocolW = $bits(TopCsrProtocol),
    localparam int     TopCsrFbProtocolW = $bits(TopCsrFbProtocol),

    // *** Default reset pipelining for top blocks (which will be on a 100-200MHz refclk)
    parameter int      DefaultTopResetPipeline = 2

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
   output logic [LedCountSafe-1:0]                     ledOut,
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

  // *******************************************************************************
  // *** INTERNAL FEATURES ***

  // getting warnings about these being converted to localparam, which was not the intention...
  // they are here because they aren't anything to do with interfaces, like the params up top.
  // I guess they prob need to move up there?

  // Or maybe they ARE localparams.  Set by define, not by param passing, so that we can count
  // on having both.  That seems to be rational except for an uneasy feeling because params are
  // much cleaner than defines

  // *** PROTECT ***
  parameter integer              ProtectCount = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_PROTECT_COUNT,0);
  `OC_LOCALPARAM_SAFE(ProtectCount);

  logic [ProtectCountSafe-1:0]   protectUnlocked;

  // *** DUMMY ***
  parameter integer              DummyCount = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_COUNT,0);
  `OC_LOCALPARAM_SAFE(DummyCount);
  parameter bit [DummyCountSafe-1:0] DummyUsePllClock = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_USE_PLL_CLOCK,
                                                                               {DummyCountSafe{1'b0}});
  parameter bit [DummyCountSafe-1:0] DummyUseRefClock = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_USE_REF_CLOCK,
                                                                               {DummyCountSafe{1'b0}});
  parameter [DummyCountSafe-1:0] [7:0] DummyClockSelect = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_CLOCK_SELECT,
                                                                                 {DummyCountSafe{8'd0}});
  parameter integer              DummyDatapathCount = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_COUNT,1);
  parameter integer              DummyDatapathWidth = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_WIDTH,32);
  parameter integer              DummyDatapathLogicLevels = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_LOGIC_LEVELS,8);
  parameter integer              DummyDatapathPipeStages = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_PIPE_STAGES,8);
  parameter integer              DummyDatapathLutInputs = `OC_VAL_ASDEFINED_ELSE(OC_TARGET_DUMMY_DATAPATH_LUT_INPUTS,4);

  // *******************************************************************************
  // ***                        USERSPACE CONFIGURATION                          ***
  // *******************************************************************************
  parameter int                  UserAxils = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXILS,0);
  `OC_LOCALPARAM_SAFE(UserAxils);

  localparam integer             UserCsrCount = `OC_VAL_ASDEFINED_ELSE(OC_USER_CSR_COUNT,0);
  localparam integer             UserAximSourceCount = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIM_SOURCE_COUNT,0);
  localparam integer             UserAximSinkCount = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIM_SINK_COUNT,0);
  localparam integer             UserAxisSourceCount = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIS_SOURCE_COUNT,0);
  localparam integer             UserAxisSinkCount = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIS_SINK_COUNT,0);
  localparam type UserCsrType = `OC_VAL_ASDEFINED_ELSE(OC_USER_CSR_TYPE, oclib_pkg::axil_32_s);
  localparam type UserCsrFbType = `OC_VAL_ASDEFINED_ELSE(OC_USER_CSR_TYPE, oclib_pkg::axil_32_fb_s);
  localparam type UserAximSourceType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIM_SOURCE_TYPE, oclib_pkg::axi4m_256_s);
  localparam type UserAximSourceFbType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIM_SOURCE_FB_TYPE, oclib_pkg::axi4m_256_fb_s);
  localparam type UserAximSinkType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIM_SINK_TYPE, oclib_pkg::axi4m_256_s);
  localparam type UserAximSinkFbType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIM_SINK_FB_TYPE, oclib_pkg::axi4m_256_fb_s);
  localparam type UserAxisSourceType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIS_SOURCE_TYPE, oclib_pkg::axi4st_64_s);
  localparam type UserAxisSourceFbType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIS_SOURCE_FB_TYPE, oclib_pkg::axi4st_64_fb_s);
  localparam type UserAxisSinkType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIS_SINK_TYPE, oclib_pkg::axi4st_64_s);
  localparam type UserAxisSinkFbType = `OC_VAL_ASDEFINED_ELSE(OC_USER_AXIS_SINK_FB_TYPE, oclib_pkg::axi4st_64_fb_s);

  `OC_LOCALPARAM_SAFE(UserCsrCount);
  `OC_LOCALPARAM_SAFE(UserAximSourceCount);
  `OC_LOCALPARAM_SAFE(UserAximSinkCount);
  `OC_LOCALPARAM_SAFE(UserAxisSourceCount);
  `OC_LOCALPARAM_SAFE(UserAxisSinkCount);

  UserCsrType                    userCsr [0:UserCsrCountSafe-1];
  UserCsrFbType                  userCsrFb [0:UserCsrCountSafe-1];
  logic                          clockUserCsr [0:UserCsrCountSafe-1];
  logic                          resetUserCsr [0:UserCsrCountSafe-1];

  // *******************************************************************************
  // *** RESOURCE CALCULATIONS ***

  function int PllCsrCount(input int through = PllCount);
    int c;
    c = 0;
    for (int i=0; i<through; i++) c += PllCsrEnable[i];
    return c;
  endfunction

  localparam integer             BlockFirstPll = 0;
  localparam integer             BlockFirstChipMon = (BlockFirstPll + PllCsrCount());
  localparam integer             BlockFirstIic = (BlockFirstChipMon + ChipMonCount);
  localparam integer             BlockFirstLed = (BlockFirstIic + IicCount);
  localparam integer             BlockFirstGpio = (BlockFirstLed + (LedCount ? 1 : 0)); // all LEDs are on one IP
  localparam integer             BlockFirstFan = (BlockFirstGpio + (GpioCount ? 1 : 0)); // all GPIOs are on one IP
  localparam integer             BlockFirstProtect = (BlockFirstFan + (FanCount ? 1 : 0)); // all FANs are on one IP
  localparam integer             BlockFirstDummy = (BlockFirstProtect + ProtectCount);
  localparam integer             BlockFirstPcie = (BlockFirstDummy + DummyCount);
  localparam integer             BlockTopCount = (BlockFirstPcie + PcieCount);
  localparam integer             BlockFirstUser = BlockTopCount;
  localparam integer             BlockFirstUserCsr = BlockFirstUser;
  localparam integer             BlockUserCount = ((BlockFirstUserCsr + UserCsrCount) - BlockFirstUser);
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
  logic                          resetFromPcieControl;
  logic                          resetFromPcie;
  logic                          resetTop;

  // If we have UART based control, we stretch reset to be pretty long, so that if we send a reset command
  // over the UART, or we power up, etc, we hold reset for at least one UART bit time (to allow bus to idle)
  localparam                     TopResetCycles = (UartControlEnable ?
                                                   ((ClockTopHz / UartBaud[UartControlSelect]) + 50) :
                                                   128);

  oclib_reset #(.StartPipeCycles(8), .ResetCycles(TopResetCycles))
  uRESET (.clock(clockTop),
          .in(hardReset || resetFromUartControl || resetFromPcieControl || resetFromPcie),
          .out(resetTop));

  oclib_pkg::chip_status_s       chipStatus;

  oc_chip_status #(.ClockHz(ClockTopHz))
  uSTATUS (.clock(clockTop), .reset(resetTop), .chipStatus(chipStatus));

  // *******************************************************************************
  // *** TOP CONTROL MUXING ***

  // ControlBcType is between axil_control and csr_tree_splitter
  localparam                     type ControlBcType = oclib_pkg::bc_8b_bidi_s;
  ControlBcType                  uartBcOut, uartBcIn, controlBcIn;
  ControlBcType                  pcieBcOut, pcieBcIn, controlBcOut;

  if (PcieControlEnable && UartControlEnable) begin : top_bc_mux
    oclib_bc_mux #(.BcType(ControlBcType))
    uCONTROL_BC_MUX (.clock(clockTop), .reset(resetTop),
                     .aIn(uartBcOut), .aOut(uartBcIn),
                     .bIn(pcieBcOut), .bOut(pcieBcIn),
                     .muxOut(controlBcOut), .muxIn(controlBcIn) );
  end
  else if (PcieControlEnable) begin
    assign controlBcOut = pcieBcOut;
    assign pcieBcIn = controlBcIn;
  end
  else if (UartControlEnable) begin
    assign controlBcOut = uartBcOut;
    assign uartBcIn = controlBcIn;
  end
  else begin
    assign controlBcOut = '0;
  end

  // *******************************************************************************
  // *** TOP_CSR_SPLIT ***

  TopCsrType                     topCsr [BlockCountSafe];
  TopCsrFbType                   topCsrFb [BlockCountSafe];
  logic                          resetFromTopCsrSplitter;

  oclib_csr_tree_splitter #(.CsrInType(ControlBcType), .CsrInFbType(ControlBcType),
                            .CsrInProtocol(TopCsrProtocol),
                            .CsrOutType(TopCsrType), .CsrOutFbType(TopCsrFbType),
                            .CsrOutProtocol(TopCsrProtocol),
                            .Outputs(BlockCount) )
  uTOP_CSR_SPLITTER (.clock(clockTop), .reset(resetTop),
                     .resetRequest(resetFromTopCsrSplitter),
                     .in(controlBcOut), .inFb(controlBcIn),
                     .out(topCsr), .outFb(topCsrFb));

  // *******************************************************************************
  // *** PLL ***

  logic [PllCountSafe-1:0] [PllClocksEach-1:0] clockPll;
  logic [PllCountSafe-1:0] [PllClocksEach-1:0] resetPll;
  for (genvar i=0; i<PllCount; i++) begin : pll
    oc_pll #(.RefClockHz(RefClockHz[i]), .OutClockCount(PllClocksEach),
             .Out0Hz(PllClockHz[i]),
             .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
             .MeasureEnable(PllMeasureEnable[i]),
             .ThrottleMap(PllThrottleMap[i]),
             .AutoThrottle(PllAutoThrottle[i]),
             .CsrEnable(PllCsrEnable[i]),
             .ResetSync(oclib_pkg::True))
    uPLL (.clock(clockTop), .reset(resetTop), .clockRef(clockRef[PllClockRef[i]]),
          .clockOut(clockPll[i][PllClocksEach-1:0]), .resetOut(resetPll[i][PllClocksEach-1:0]),
          .csr(topCsr[BlockFirstPll+PllCsrCount(i)]), .csrFb(topCsrFb[BlockFirstPll+PllCsrCount(i)]),
          .thermalWarning(thermalWarning), .thermalError(thermalError));
  end


  // *******************************************************************************
  // *** CHIPMON ***

  logic [ChipMonCountSafe-1:0]   chipMonThermalWarning;
  logic [ChipMonCountSafe-1:0]   chipMonThermalError;
  logic [ChipMonCountSafe-1:0]   chipMonAlertTristate;
  logic                          chipMonMergedThermalWarning;
  logic                          chipMonMergedThermalError;
  logic                          chipMonMergedAlertTristate;
  for (genvar i=0; i<ChipMonCount; i++) begin : chipmon
    oc_chipmon #(.ClockHz(ClockTopHz),
                 .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
                 .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uCHIPMON (.clock(clockTop), .reset(resetTop),
              .csr(topCsr[BlockFirstChipMon+i]), .csrFb(topCsrFb[BlockFirstChipMon+i]),
              .scl(chipMonScl[i]), .sclTristate(chipMonSclTristate[i]),
              .sda(chipMonSda[i]), .sdaTristate(chipMonSdaTristate[i]),
              .thermalWarning(chipMonThermalWarning[i]), .thermalError(chipMonThermalError[i]),
              .alertTristate(chipMonAlertTristate[i]));
  end
  if (ChipMonCount==0) begin
    assign chipMonThermalWarning = '0;
    assign chipMonThermalError = '0;
    assign chipMonAlertTristate = '0;
  end
  assign chipMonMergedThermalWarning = (|chipMonThermalWarning);
  assign chipMonMergedThermalError = (|chipMonThermalError);
  assign chipMonMergedAlertTristate = (|chipMonAlertTristate);

  // *******************************************************************************
  // *** IIC ***

  for (genvar i=0; i<IicCount; i++) begin : iic
    oc_iic #(.ClockHz(ClockTopHz), .OffloadEnable(IicOffloadEnable),
             .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
             .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uIIC (.clock(clockTop), .reset(resetTop),
          .csr(topCsr[BlockFirstIic+i]), .csrFb(topCsrFb[BlockFirstIic+i]),
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
             .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
             .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uLED (.clock(clockTop), .reset(resetTop),
          .csr(topCsr[BlockFirstLed]), .csrFb(topCsrFb[BlockFirstLed]),
          .ledOut(ledOut));
  end
  else begin
    assign ledOut = '0;
  end

  // *******************************************************************************
  // *** GPIO ***

  if (GpioCount) begin : gpio
    oc_gpio #(.ClockHz(ClockTopHz), .GpioCount(GpioCount),
              .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
              .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uGPIO (.clock(clockTop), .reset(resetTop),
           .csr(topCsr[BlockFirstGpio]), .csrFb(topCsrFb[BlockFirstGpio]),
           .gpioOut(gpioOut), .gpioTristate(gpioTristate), .gpioIn(gpioIn));
  end
  else begin
    assign gpioOut = '0;
    assign gpioTristate = '1;
  end

  // *******************************************************************************
  // *** FAN ***

  if (FanCount) begin : fan
    oc_fan #(.ClockHz(ClockTopHz), .FanCount(FanCount),
             .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
             .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uFAN (.clock(clockTop), .reset(resetTop),
          .csr(topCsr[BlockFirstFan]), .csrFb(topCsrFb[BlockFirstFan]),
          .fanPwm(fanPwm), .fanSense(fanSense));
  end
  else begin
    assign fanPwm = '0;
  end

  // *******************************************************************************
  // *** PROTECT ***

  for (genvar i=0; i<ProtectCount; i++) begin : protect
    oc_protect #(.ClockHz(ClockTopHz),
                 .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
                 .ResetSync(oclib_pkg::False), .ResetPipeline(DefaultTopResetPipeline))
    uPROTECT (.clock(clockTop), .reset(resetTop),
              .csr(topCsr[BlockFirstProtect+i]), .csrFb(topCsrFb[BlockFirstProtect+i]),
              .unlocked(protectUnlocked[i]));
  end

  // *******************************************************************************
  // *** DUMMY ***

  for (genvar i=0; i<DummyCount; i++) begin : dummy
    localparam integer UsePllClock = DummyUsePllClock[i];
    logic              clockDummy;
    logic              resetDummy;
    logic              resetSyncRequired;
    assign clockDummy = (DummyUsePllClock[i] ? clockPll[DummyClockSelect[i]][0] : // only first clock output for now
                         DummyUseRefClock[i] ? clockRef[DummyClockSelect[i]] :
                         clockTop);
    assign resetDummy = (DummyUsePllClock[i] ? resetPll[DummyClockSelect[i]][0] :
                         DummyUseRefClock[i] ? resetTop : // this line requires a sync, set via param...
                         resetTop);
    oc_dummy #(.DatapathCount(DummyDatapathCount), .DatapathWidth(DummyDatapathWidth),
               .DatapathLogicLevels(DummyDatapathLogicLevels), .DatapathPipeStages(DummyDatapathPipeStages),
               .DatapathLutInputs(DummyDatapathLutInputs),
               .UseClockDummy(DummyUsePllClock[i]),
               .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
               .ResetSync(DummyUseRefClock[i] && !DummyUsePllClock[i]), // see comment above
               .ResetPipeline(DefaultTopResetPipeline))
    uDUMMY (.clock(clockTop), .reset(resetTop),
            .clockDummy(clockDummy), .resetDummy(resetDummy),
            .csr(topCsr[BlockFirstDummy+i]), .csrFb(topCsrFb[BlockFirstDummy+i]));
  end

  // *******************************************************************************
  // *** PCIE ***

  localparam type PcieAxilType = `OC_VAL_ASDEFINED_ELSE(OC_PCIE_AXIL_TYPE, oclib_pkg::axil_32_s);
  localparam type PcieAxilFbType = `OC_VAL_ASDEFINED_ELSE(OC_PCIE_AXIL_FB_TYPE, oclib_pkg::axil_32_fb_s);

  PcieAxilType pcieAxil [PcieCount-1:0];
  PcieAxilFbType pcieAxilFb [PcieCount-1:0];
  logic clockPcieAxil [PcieCount-1:0];
  logic resetPcieAxil [PcieCount-1:0];

  for (genvar i=0; i<PcieCount; i++) begin : pcie

    logic clockRawAxil, resetRawAxil;
    PcieAxilType rawAxil;
    PcieAxilFbType rawAxilFb;

    // for now we only support AXIL; it won't be hard to translate when we need it...
    `OC_STATIC_ASSERT(type(UserCsrType) == type(oclib_pkg::axil_32_s));

    oc_pcie #(.PcieWidth(PcieWidth[i]),
              .CsrType(TopCsrType), .CsrFbType(TopCsrFbType), .CsrProtocol(TopCsrProtocol),
              .ResetSync(oclib_pkg::False),
              .ResetPipeline(DefaultTopResetPipeline))
    uPCIE (.clock(clockTop), .reset(resetTop),
           .pcieReset(pcieReset[i]), // input from pin
           .txP(pcieTxP[i][PcieWidth[i]-1:0]), .txN(pcieTxN[i][PcieWidth[i]-1:0]),
           .rxP(pcieRxP[i][PcieWidth[i]-1:0]), .rxN(pcieRxN[i][PcieWidth[i]-1:0]),
           .clockRefP(clockDiffRefP[PcieDiffRefClock[i]]), .clockRefN(clockDiffRefN[PcieDiffRefClock[i]]),
           .clockAxil(clockRawAxil), .resetAxil(resetRawAxil),
           .axil(rawAxil), .axilFb(rawAxilFb),
           .csr(topCsr[BlockFirstPcie+i]), .csrFb(topCsrFb[BlockFirstPcie+i]) );

    assign clockPcieAxil[i] = clockRawAxil;
    assign resetPcieAxil[i] = resetRawAxil;

    // if this PCIe is the control channel, we reset the chip along with the PCIe bus, and we instantiate the bridge
    if (PcieControlEnable && (i==PcieControlSelect)) begin : control

      UserCsrType axilOut;
      UserCsrFbType axilOutFb;

      oc_axil_control #(.ClockHz(ClockTopHz),
                        .UseClockAxil(oclib_pkg::True),
                        .AxilType(UserCsrType), .AxilFbType(UserCsrFbType),
                        .BcType(ControlBcType), .BcProtocol(TopCsrProtocol),
                        .BlockTopCount(BlockTopCount),
                        .BlockUserCount(BlockUserCount),
                        .UserCsrCount(UserCsrCount),
                        .UserAximSourceCount(UserAximSourceCount),
                        .UserAximSinkCount(UserAximSinkCount),
                        .UserAxisSourceCount(UserAxisSourceCount),
                        .UserAxisSinkCount(UserAxisSinkCount),
                        .AddressBits(17), // TODO: make this configurable, right now BAR0 is always 128KB
                        .PassThrough(i < UserCsrCount))
      uAXIL_CONTROL (.clock(clockTop), .reset(resetTop), .resetOut(resetFromPcieControl),
                     .clockAxil(clockRawAxil), .resetAxil(resetRawAxil),
                     .axil(rawAxil), .axilFb(rawAxilFb),
                     .axilOut(pcieAxil[i]), .axilOutFb(pcieAxilFb[i]),
                     .bcIn(pcieBcIn), .bcOut(pcieBcOut));

      assign resetFromPcie = resetRawAxil; // the whole chip will take reset from PCIe slot if it's in control
    end
    else begin
      // we aren't tapping into this AXIL
      assign pcieAxil[i] = rawAxil;
      assign rawAxilFb = pcieAxilFb[i];
    end

  end // for (genvar i=0; i<PcieCount; i++) begin : pcie

  // if we don't have a PCIe at all, or not enabled PCIe control, or selected an invalid port, tie off the reset
  if ((PcieCount == 0) || (!PcieControlEnable) || (PcieControlSelect >= PcieCount)) begin
    assign resetFromPcie = 1'b0;
  end

  // *******************************************************************************
  // *** UART CONTROL ***

  localparam integer             UartErrorWidth = oclib_uart_pkg::ErrorWidth;
  logic [UartErrorWidth-1:0]     uartError;

  if (UartControlEnable) begin : uart_control
    oc_uart_control #(.ClockHz(ClockTopHz),
                      .Baud(UartBaud[UartControlSelect]),
                      .BcType(ControlBcType), .BcProtocol(TopCsrProtocol),
                      .BlockTopCount(BlockTopCount),
                      .BlockUserCount(BlockUserCount),
                      .UserCsrCount(UserCsrCount),
                      .UserAximSourceCount(UserAximSourceCount),
                      .UserAximSinkCount(UserAximSinkCount),
                      .UserAxisSourceCount(UserAxisSourceCount),
                      .UserAxisSinkCount(UserAxisSinkCount),
                      .ResetSync(oclib_pkg::False) )
    uCONTROL (.clock(clockTop), .reset(resetTop),
              .resetOut(resetFromUartControl), .uartError(uartError),
              .uartRx(uartRx[UartControlSelect]), .uartTx(uartTx[UartControlSelect]),
              .bcOut(uartBcOut), .bcIn(uartBcIn));
  end
  else begin
    assign resetFromUartControl = 1'b0;
  end

  // *******************************************************************************
  // *** USER SPACE CSRS

  UserCsrType                    bcUserCsr [0:UserCsrCountSafe-1];
  UserCsrFbType                  bcUserCsrFb [0:UserCsrCountSafe-1];

  for (genvar i=0; i<UserCsrCount; i++) begin : user_csr

    // for each AXIL, we always have a way to access from the BC bus.  At some point we'll have
    // a switch to enable this, it shouldn't be mandatory esp for production

    oclib_csr_adapter #(.CsrInType(TopCsrType),
                        .CsrInFbType(TopCsrFbType),
                        .CsrInProtocol(TopCsrProtocol),
                        .CsrOutType(UserCsrType),
                        .CsrOutFbType(UserCsrFbType),
                        .UseClockOut(oclib_pkg::True))
    uCSR_ADAPTER (.clock(clockTop),
                  .reset(resetTop),
                  .clockOut(clockUserCsr[i]), // these will get assigned below
                  .resetOut(resetUserCsr[i]),
                  .in(topCsr[BlockFirstUserCsr+i]),
                  .inFb(topCsrFb[BlockFirstUserCsr+i]),
                  .out(bcUserCsr[i]),
                  .outFb(bcUserCsrFb[i]));

    if (i < PcieCount) begin

      // we have a PCIe Axil driving this CSR port.  Mux it in with the BC bus driver.
      // expect this decision to get more complex, i.e. more controls and an AXIL interconnect

      assign clockUserCsr[i] = clockPcieAxil[i];
      assign resetUserCsr[i] = resetPcieAxil[i];

      oclib_axil_mux #(.AxilType(UserCsrType),
                       .AxilFbType(UserCsrFbType))
      uAXIL_MUX (.clock(clockUserCsr[i]),
                 .reset(resetUserCsr[i]),
                 .in('{bcUserCsr[i],pcieAxil[i]}),
                 .inFb('{bcUserCsrFb[i],pcieAxilFb[i]}),
                 .out(userCsr[i]),
                 .outFb(userCsrFb[i]));
    end
    else begin

      // this AXIL interface is not coming from PCIe, so we tie it to a PLL if one is configured
      // (for now there's no other reason to enable a PLL).  It will work to have N PLLs driving
      // N AXIs, or 1 PLL driving all.  We will clearly be needing some finer grained control over all
      // this...
      assign clockUserCsr[i] = ((i < PllCount) ? clockPll[i] : (PllCount>0) ? clockPll[0] : clockTop);
      assign resetUserCsr[i] = ((i < PllCount) ? resetPll[i] : (PllCount>0) ? resetPll[0] : resetTop);

      assign userCsr[i] = bcUserCsr[i];
      assign bcUserCsrFb[i] = userCsrFb[i];

    end

  end // for (genvar i=0; i<UserCsrCount; i++) begin : user_csr


  // for now we are just instantiating memory tester

  localparam type MemoryBistAximType = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_AXIM_TYPE, oclib_pkg::axi4m_256_s);
  localparam type MemoryBistAximFbType = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_AXIM_FB_TYPE, oclib_pkg::axi4m_256_fb_s);
  localparam int MemoryBistPortCount = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_PORT_COUNT,1);
  localparam int MemoryBistMemoryBytes = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_RAM_BYTES,65536);

  for (genvar i=0; i<UserCsrCount; i++) begin : user_space

    logic          clockAxim;
    logic          resetAxim;
    MemoryBistAximType [MemoryBistPortCount-1:0] axim;
    MemoryBistAximFbType [MemoryBistPortCount-1:0] aximFb;

    assign clockAxim = ((i < PllCount) ? clockPll[i] : (PllCount>0) ? clockPll[0] : clockTop);
    assign resetAxim = ((i < PllCount) ? resetPll[i] : (PllCount>0) ? resetPll[0] : resetTop);

    oclib_memory_bist #(.AximPorts(MemoryBistPortCount),
                        .AximType(MemoryBistAximType), .AximFbType(MemoryBistAximFbType))
    uMBIST (.reset(resetUserCsr[i] || resetAxim),
            .clockAxil(clockUserCsr[i]),
            .clockAxim(clockAxim),
            .axil(userCsr[i]), .axilFb(userCsrFb[i]),
            .axim(axim), .aximFb(aximFb));

    for (genvar j=0; j<MemoryBistPortCount; j++) begin : mbist_rams
      oclib_axim_ram #(.Bits(8*MemoryBistMemoryBytes),
                       .AximType(MemoryBistAximType), .AximFbType(MemoryBistAximFbType))
      uAXIM_RAM (.clock(clockAxim), .reset(resetAxim),
                 .axim(axim[j]), .aximFb(aximFb[j]));
    end

  end

  // *******************************************************************************
  // *** Merge Error Status ***

  assign thermalError = 1'b0;
  assign thermalWarning = chipMonMergedThermalWarning;

  // *******************************************************************************
  // *** idle unused UARTs for now ***

  for (genvar i=0; i<UartCount; i++) begin
    if (i != UartControlSelect) begin
      assign uartTx[i] = 1'b1;
    end
  end

endmodule // oc_cos
