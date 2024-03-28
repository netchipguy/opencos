
// SPDX-License-Identifier: MPL-2.0

`include "top/oc_top_pkg.sv"
`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"
`include "sim/ocsim_pkg.sv"

// Some useful defines
// OC_SIM_VERBOSE
// OC_SIM_LONG
// OC_CHIP_HARNESS_TEST

module oc_cos_test
  #(
    // *******************************************************************************
    // ***                         EXTERNAL CONFIGURATION                          ***
    // Interfaces to the chip top
    // *******************************************************************************

    // *** MISC ***
    parameter integer Seed = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_SEED,0),

    // *** REFCLOCK ***
    parameter integer RefClockCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_REFCLOCK_COUNT,1),
                      `OC_LOCALPARAM_SAFE(RefClockCount),
    parameter integer RefClockHz [0:RefClockCount-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_REFCLOCK_HZ,
                                                                              '{156_250_000}),
    parameter integer DiffRefClockCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_DIFFREFCLOCK_COUNT,3),
                      `OC_LOCALPARAM_SAFE(DiffRefClockCount),
    parameter integer DiffRefClockHz [0:DiffRefClockCountSafe-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_DIFFREFCLOCK_HZ,
                                                                                          '{161_132_812,
                                                                                            161_132_812,
                                                                                            100_000_000 }),

    // *** TOP CLOCK ***
    parameter integer ClockTop = oc_top_pkg::ClockIdSingleEndedRef(0),

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
    parameter integer FanCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_FAN_COUNT,1),
                      `OC_LOCALPARAM_SAFE(FanCount),

    // *** UART ***
    parameter integer UartCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_COUNT,2),
                      `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_BAUD,{10_000_000,115_200}),
    parameter bit     UartControlEnable = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL_ENABLE,1),
    parameter bit     UartControlAxil = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL_AXIL,1),
    parameter integer UartControlSelect = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_UART_CONTROL_SELECT,0),

    // *** PCIe ***
    parameter integer PcieCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_COUNT,1),
                      `OC_LOCALPARAM_SAFE(PcieCount),
    parameter integer PcieWidth [PcieCountSafe-1:0] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_WIDTH, '{ PcieCountSafe { 1 } }),
    parameter integer PcieWidthMax = 16,
    parameter integer PcieGen [PcieCountSafe-1:0] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_GEN, '{ PcieCountSafe { 3 } }),
    parameter integer PcieDiffRefClock [PcieCountSafe-1:0] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_DIFFREFCLK, // PCIE_REFCLK_P is #2
                                                                                    '{ PcieCountSafe { 2 } }),
    parameter bit     PcieControlEnable = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_CONTROL_ENABLE,(PcieCount?1:0)),
    parameter integer PcieControlSelect = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_PCIE_CONTROL_SELECT,0),

    // *******************************************************************************
    // ***                         INTERNAL CONFIGURATION                          ***
    // Configuring OC_COS internals which board can override in target-specific ways
    // *******************************************************************************

    // *** Format of Top-Level CSR bus ***
    parameter         type TopCsrType = oclib_pkg::bc_8b_bidi_s,
    parameter         type TopCsrFbType = oclib_pkg::bc_8b_bidi_s,
    parameter         type TopCsrProtocol = oclib_pkg::csr_32_tree_s,
    parameter         type TopCsrFbProtocol = oclib_pkg::csr_32_tree_fb_s,
    // *** we create these versions so we can do imperfect-but-helpful type comparisons
    localparam int     TopCsrTypeW = $bits(TopCsrType),
    localparam int     TopCsrFbTypeW = $bits(TopCsrFbType),
    localparam int     TopCsrProtocolW = $bits(TopCsrProtocol),
    localparam int     TopCsrFbProtocolW = $bits(TopCsrFbProtocol),

    // *******************************************************************************
    // ***                        TESTBENCH CONFIGURATION                          ***
    // *******************************************************************************
    parameter integer Verbose = `OC_VAL_ASDEFINED_ELSE(OC_SIM_VERBOSE, 1)
    )
  ();

  // *** TESTBENCH STATUS ***
  logic               error = 0;

  // *** REFCLOCK ***
  logic [RefClockCountSafe-1:0] clockRef;
  logic [DiffRefClockCount-1:0] clockDiffRefP, clockDiffRefN;
  // *** RESET ***
  logic                         hardReset;
  // *** CHIPMON ***
  logic [ChipMonCountSafe-1:0]  chipMonScl = {ChipMonCountSafe{1'b1}};
  logic [ChipMonCountSafe-1:0]  chipMonSclTristate;
  logic [ChipMonCountSafe-1:0]  chipMonSda = {ChipMonCountSafe{1'b1}};
  logic [ChipMonCountSafe-1:0]  chipMonSdaTristate;
   // *** IIC ***
  logic [IicCountSafe-1:0]      iicScl = {IicCountSafe{1'b1}};
  logic [IicCountSafe-1:0]      iicSclTristate;
  logic [IicCountSafe-1:0]      iicSda = {IicCountSafe{1'b1}};
  logic [IicCountSafe-1:0]      iicSdaTristate;
  // *** LED ***
  logic [LedCountSafe-1:0]      ledOut;
  // *** GPIO ***
  logic [GpioCountSafe-1:0]     gpioOut;
  logic [GpioCountSafe-1:0]     gpioTristate;
  logic [GpioCountSafe-1:0]     gpioIn = {GpioCountSafe{1'b0}};
  // *** FAN ***
  logic [FanCountSafe-1:0]      fanPwm;
  logic [FanCountSafe-1:0]      fanSense = {FanCountSafe{1'b0}};
  // *** UART ***
  logic [UartCountSafe-1:0]     uartRx;
  logic [UartCountSafe-1:0]     uartTx;
   // *** PCIe ***
  logic [PcieCountSafe-1:0]     pcieReset;
  logic [PcieCountSafe-1:0] [PcieWidthMax-1:0] pcieTxP;
  logic [PcieCountSafe-1:0] [PcieWidthMax-1:0] pcieTxN;
  logic [PcieCountSafe-1:0] [PcieWidthMax-1:0] pcieRxP = { PcieCountSafe * PcieWidthMax { 1'b0 } };
  logic [PcieCountSafe-1:0] [PcieWidthMax-1:0] pcieRxN = { PcieCountSafe * PcieWidthMax { 1'b1 } };
  // *** MISC ***
  logic                         thermalWarning;
  logic                         thermalError;


  integer                       blockTopCount = -1;
  integer                       blockUserCount = -1;


  // *** REFCLOCK ***
  for (genvar i=0; i<RefClockCount; i++) begin
    ocsim_clock #(.ClockHz(RefClockHz[i])) uCLOCK (.clock(clockRef[i]));
  end
  for (genvar i=0; i<DiffRefClockCount; i++) begin
    ocsim_clock #(.ClockHz(DiffRefClockHz[i])) uDIFFCLOCK (.clock(clockDiffRefP[i]));
    assign clockDiffRefN[i] = ~clockDiffRefP[i];
  end

  // *** RESET ***
  ocsim_reset uHARD_RESET (.clock(clockRef[0]), .reset(hardReset));

  // *** PCIe ***
  task PcieReset ( input time period = 100ns, input int slot = -1 );
    if (slot == -1) pcieReset = {PcieCountSafe{1'b1}};
    else            pcieReset[slot] = 1'b1;
    #(period);
    if (slot == -1) pcieReset = {PcieCountSafe{1'b0}};
    else            pcieReset[slot] = 1'b0;
  endtask

  initial PcieReset();

  // *** UART ***
  ocsim_uart #(.Baud(UartBaud[UartControlSelect]), .Verbose(Verbose))
  uCONTROL_UART (.rx(uartTx[UartControlSelect]), .tx(uartRx[UartControlSelect]));

  // in OC_COS testing mode (default), we pass params from above and the DUT conforms to what
  // we setup.  In BOARD testing mode, we don't override the board params, just config the TB
  // to match the board.  It's up to us to config the TB as needed to match the board.  It
  // shouldn't require different defines for the TB vs BOARD params, but we may have to revisit.

`ifdef OC_CHIP_HARNESS_TEST

  `define OC_COS uHARNESS.uDUT.uCOS

  oc_chip_harness #(.Seed(Seed))
  uHARNESS (
            .clockRef(clockRef),
            .clockDiffRefP(clockDiffRefP), .clockDiffRefN(clockDiffRefN),
            .hardReset(hardReset),
            .chipMonScl(chipMonScl),
            .chipMonSclTristate(chipMonSclTristate),
            .chipMonSda(chipMonSda),
            .chipMonSdaTristate(chipMonSdaTristate),
            .ledOut(ledOut),
            .uartRx(uartRx),
            .uartTx(uartTx),
            .pcieReset(pcieReset),
            .pcieTxP(pcieTxP),
            .pcieTxN(pcieTxN),
            .pcieRxP(pcieRxP),
            .pcieRxN(pcieRxN),
            .thermalWarning(thermalWarning),
            .thermalError(thermalError)
            );

`else // !`ifdef OC_CHIP_HARNESS_TEST

  `define OC_COS uDUT

  oc_cos #(.Seed(Seed),
           .RefClockCount(RefClockCount),
           .RefClockHz(RefClockHz),
           .DiffRefClockCount(DiffRefClockCount),
           .DiffRefClockHz(DiffRefClockHz),
           .ClockTop(ClockTop),
           .PllCount(PllCount),
           .PllClockRef(PllClockRef),
           .PllCsrEnable(PllCsrEnable),
           .PllMeasureEnable(PllMeasureEnable),
           .PllThrottleMap(PllThrottleMap),
           .PllAutoThrottle(PllAutoThrottle),
           .PllClockHz(PllClockHz),
           .ChipMonCount(ChipMonCount),
           .ChipMonCsrEnable(ChipMonCsrEnable),
           .ChipMonI2CEnable(ChipMonI2CEnable),
           .IicCount(IicCount),
           .IicOffloadEnable(IicOffloadEnable),
           .LedCount(LedCount),
           .GpioCount(GpioCount),
           .FanCount(FanCount),
           .UartCount(UartCount),
           .UartBaud(UartBaud),
           .UartControlEnable(UartControlEnable),
           .UartControlAxil(UartControlAxil),
           .UartControlSelect(UartControlSelect),
           .PcieCount(PcieCount),
           .PcieWidth(PcieWidth),
           .PcieGen(PcieGen),
           .PcieDiffRefClock(PcieDiffRefClock),
           .PcieControlEnable(PcieControlEnable),
           .PcieControlSelect(PcieControlSelect),
           .TopCsrType(TopCsrType),
           .TopCsrFbType(TopCsrFbType),
           .TopCsrProtocol(TopCsrProtocol))
  uDUT (
        .clockRef(clockRef),
        .clockDiffRefP(clockDiffRefP), .clockDiffRefN(clockDiffRefN),
        .hardReset(hardReset),
        .chipMonScl(chipMonScl),
        .chipMonSclTristate(chipMonSclTristate),
        .chipMonSda(chipMonSda),
        .chipMonSdaTristate(chipMonSdaTristate),
        .iicScl(iicScl),
        .iicSclTristate(iicSclTristate),
        .iicSda(iicSda),
        .iicSdaTristate(iicSdaTristate),
        .ledOut(ledOut),
        .gpioOut(gpioOut),
        .gpioTristate(gpioTristate),
        .gpioIn(gpioIn),
        .fanPwm(fanPwm),
        .fanSense(fanSense),
        .uartRx(uartRx),
        .uartTx(uartTx),
        .pcieReset(pcieReset),
        .pcieTxP(pcieTxP),
        .pcieTxN(pcieTxN),
        .pcieRxP(pcieRxP),
        .pcieRxN(pcieRxN),
        .thermalWarning(thermalWarning),
        .thermalError(thermalError)
        );

`endif // !`ifdef OC_CHIP_HARNESS_TEST

  task TestConfirmParams;

    // we make sure that all params are matching between TB and DUT.  In OC_CHIP_HARNESS_TEST case, it's
    // very important to make sure TB is setup to match the DUT, since DUT is configured by board DEPS
    // order to exactly match what is built.  In !OC_CHIP_HARNESS_TEST, we really are just making sure
    // that all params are being passed and we don't forget one.

`define OC_CONFIRM_PARAM_INTEGER(x) \
    `OC_ANNOUNCE_PARAM_INTEGER(x); \
    `OC_ASSERT_EQUAL(x, `OC_COS . x);

`define OC_CONFIRM_PARAM_MISC(x) \
    `OC_ANNOUNCE_PARAM_MISC(x); \
    `OC_ASSERT_EQUAL(x, `OC_COS . x);

`define OC_CONFIRM_PARAM_TYPE(x) \
    `OC_ASSERT_EQUAL(x``W, `OC_COS.x``W);

`ifdef OC_CHIP_HARNESS_TEST
    $display("%t %m: OC_CHIP_HARNESS_TEST mode: oc_cos expected to be found at uHARNESS.uDUT.uCOS", $realtime);
`else
    $display("%t %m: OC_COS_TEST mode: oc_cos expected to be found at uDUT", $realtime);
`endif

    `OC_CONFIRM_PARAM_INTEGER(Seed);
    `OC_CONFIRM_PARAM_INTEGER(RefClockCount);
    `OC_CONFIRM_PARAM_MISC   (RefClockHz);
    `OC_CONFIRM_PARAM_INTEGER(DiffRefClockCount);
    `OC_CONFIRM_PARAM_MISC   (DiffRefClockHz);
    `OC_CONFIRM_PARAM_INTEGER(ClockTop);
    `OC_CONFIRM_PARAM_INTEGER(PllCount);
    `OC_CONFIRM_PARAM_INTEGER(PllCountMax);
    `OC_CONFIRM_PARAM_INTEGER(PllClocksEach);
    `OC_CONFIRM_PARAM_MISC   (PllClockRef);
    `OC_CONFIRM_PARAM_MISC   (PllCsrEnable);
    `OC_CONFIRM_PARAM_MISC   (PllMeasureEnable);
    `OC_CONFIRM_PARAM_MISC   (PllThrottleMap);
    `OC_CONFIRM_PARAM_MISC   (PllAutoThrottle);
    `OC_CONFIRM_PARAM_MISC   (PllClockHz);
    `OC_CONFIRM_PARAM_INTEGER(ChipMonCount);
    `OC_CONFIRM_PARAM_MISC   (ChipMonCsrEnable);
    `OC_CONFIRM_PARAM_MISC   (ChipMonI2CEnable);
    `OC_CONFIRM_PARAM_INTEGER(IicCount);
    `OC_CONFIRM_PARAM_INTEGER(IicOffloadEnable);
    `OC_CONFIRM_PARAM_INTEGER(LedCount);
    `OC_CONFIRM_PARAM_INTEGER(GpioCount);
    `OC_CONFIRM_PARAM_INTEGER(FanCount);
    `OC_CONFIRM_PARAM_INTEGER(UartCount);
    `OC_CONFIRM_PARAM_MISC   (UartBaud);
    `OC_CONFIRM_PARAM_INTEGER(UartControlEnable);
    `OC_CONFIRM_PARAM_INTEGER(UartControlAxil);
    `OC_CONFIRM_PARAM_INTEGER(UartControlSelect);
    `OC_CONFIRM_PARAM_INTEGER(PcieCount);
    `OC_CONFIRM_PARAM_MISC   (PcieWidth);
    `OC_CONFIRM_PARAM_MISC   (PcieGen);
    `OC_CONFIRM_PARAM_MISC   (PcieDiffRefClock);
    `OC_CONFIRM_PARAM_INTEGER(PcieControlEnable);
    `OC_CONFIRM_PARAM_INTEGER(PcieControlSelect);
    `OC_CONFIRM_PARAM_TYPE   (TopCsrType);
    `OC_CONFIRM_PARAM_TYPE   (TopCsrFbType);
    `OC_CONFIRM_PARAM_TYPE   (TopCsrProtocol);
    `OC_ANNOUNCE_PARAM_INTEGER(Verbose);
    `OC_ANNOUNCE_PARAM_INTEGER(`OC_COS.UserAxils);

  endtask


  // The following APIs pass byte accesses to the serialization layer (UART, PCIe, etc)

  logic         enableUartControl;
  logic         txEnterCR;
  logic         txEnterLF;
  logic         rxEnterCR;
  logic         rxEnterLF;

  initial begin
    enableUartControl = !PcieControlEnable;
    txEnterCR = 1'b1;
    txEnterLF = 1'b0;
    rxEnterCR = 1'b1;
    rxEnterLF = 1'b1;
  end

  // TODO: can we get rid of the concept of "expect" and just block on receive, making it synchronous?  I can see expect for
  // high bandwidth AXI testing (DMA etc) but not for this control channel and UART stuff.

`ifdef OC_TOOL_VIVADO
  `define AXIM_SOURCE `OC_COS . \pcie[0].uPCIE . \sim_model.uSIM_AXIM_SOURCE
`else
  `define AXIM_SOURCE `OC_COS .pcie[0].uPCIE.sim_model.uSIM_AXIM_SOURCE
`endif

  // if the above paths don't work, set this to at least be able to build design and see what paths SHOULD look like...
  //`define SKIP_AXIM_SOURCE

  int userCsrCurrent = 0;

  task UserCsrWrite32(input [31:0] address, input [31:0] data, input int number=-1);
    if (number==-1) number = userCsrCurrent;
    `OC_ASSERT(number < (`OC_COS . UserCsrCount));
    if (number == 0) begin
`ifndef SKIP_AXIM_SOURCE `AXIM_SOURCE.Write32(address, data); `endif
    end
    else begin
      TopCsrWrite(.block((`OC_COS . BlockFirstUserCsr) + number), .space(0), .address(address), .data(data));
    end
  endtask

  task UserCsrReadCheck32(input [31:0] address, input [31:0] data, input [31:0] mask=32'hffffffff, input int number=-1);
    if (number==-1) number = userCsrCurrent;
    `OC_ASSERT(number < (`OC_COS . UserCsrCount));
    if (number == 0) begin
`ifndef SKIP_AXIM_SOURCE `AXIM_SOURCE.ReadCheck32(address, data); `endif
    end
    else begin
      TopCsrReadCheck(.block(`OC_COS . BlockFirstUserCsr + number), .space(0), .address(address), .data(data), .mask(mask));
    end
  endtask

  task UserCsrRead32(input [31:0] address, output logic [31:0] data, input int number=-1);
    if (number==-1) number = userCsrCurrent;
    `OC_ASSERT(number < (`OC_COS . UserCsrCount));
    if (number == 0) begin
`ifndef SKIP_AXIM_SOURCE `AXIM_SOURCE.Read32(address, data); `endif
    end
    else begin
      TopCsrRead(.block(`OC_COS . BlockFirstUserCsr + number), .space(0), .address(address), .data(data));
    end
  endtask

  localparam [31:0] PcieDataPort = 'h0001_ff00;
  localparam [31:0] PcieControlPort = 'h0001_ff80;

  task ControlSend ( input [7:0] b );
    logic [31:0] data;
    if (enableUartControl) uCONTROL_UART.Send(b);
    else begin
      if (Verbose) $display("%t %m: Sending Byte: %02x (%s)", $realtime, b, ocsim_pkg::CharToString(b));
      UserCsrWrite32(.address(PcieDataPort), .data(b), .number(`OC_COS . PcieControlSelect));
    end
  endtask // ControlSend

  task ControlExpect ( input [7:0] b );
    logic [31:0] data;
    if (enableUartControl) uCONTROL_UART.Expect(b);
    else begin
      if (Verbose) $display("%t %m: Expecting Byte: %02x (%s)", $realtime, b, ocsim_pkg::CharToString(b));
      UserCsrRead32(.address(PcieDataPort), .data(data), .number(`OC_COS . PcieControlSelect));
      `OC_ASSERT_EQUAL(data,{24'h000001,b});
    end
  endtask // ControlExpect

  task ControlReceive ( output logic [7:0] b, input integer maxNS = 1000000 );
    logic [31:0] data;
    realtime     stopTime;
    stopTime = $realtime + (1ns * maxNS);
    if (enableUartControl) uCONTROL_UART.Receive(b, maxNS/10);
    else begin
      if (Verbose) $display("%t %m: Receiving Byte...", $realtime);
      UserCsrRead32(.address(PcieDataPort), .data(data), .number(`OC_COS . PcieControlSelect));
      b = data[7:0];
      `OC_ASSERT_EQUAL(data[31:8],24'h000001);
      if (Verbose) $display("%t %m: Received Byte: %02x (%s)", $realtime, b, ocsim_pkg::CharToString(b));
    end
  endtask // ControlReceive

  task ControlReceiveCheck ( input [7:0] v, input integer maxNS = 1000000 );
    logic [7:0] d;
    ControlReceive(d, maxNS);
    `OC_ASSERT_EQUAL(d,v);
  endtask // ControlReceiveCheck

  task ControlWaitForIdle( integer maxNS = 1000000 );
    realtime     stopTime;
    stopTime = $realtime + (1ns * maxNS);
    if (enableUartControl) uCONTROL_UART.WaitForIdle(maxNS/10);
    // we don't have an expect queue in PCIe mode
  endtask // ControlWaitForIdle

  task ControlExpectIdle( integer NS = 10000 );
    logic [31:0] data;
    realtime     stopTime;
    stopTime = $realtime + (1ns * NS);
    if (enableUartControl) uCONTROL_UART.ExpectIdle(NS/10);
    else begin
      if (Verbose) $display("%t %m: Checking idle for %0dns", $realtime, NS);
      while ($realtime < stopTime) begin
        UserCsrRead32(.address(PcieControlPort), .data(data), .number(`OC_COS . PcieControlSelect));
        `OC_ASSERT_EQUAL(data&32'h000a_0000,32'h0000_0000); // check bcIn.valid and bcOut.valid are zero
      end
    end
  endtask // ControlWaitForIdle

  // The following APIs perform multiple operations to the above, to work on INTs, STRINGs, etc

  task ControlSendEnter();
    if (txEnterCR) ControlSend(8'h0d);
    if (txEnterLF) ControlSend(8'h0a);
  endtask // ControlSendEnter

  task ControlSendString ( input string s );
    for (int i=0; i<s.len(); i++) ControlSend(s[i]);
  endtask // SendString

  task ControlSendmultiple ( input [7:0] b [$] );
    if (Verbose) $display("%t %m: Sending %0d Bytes...", $realtime, b.size());
    for (int i=0; i<b.size(); i++) ControlSend(b[i]);
  endtask // SendMultiple

  task ControlExpectEnter();
    if (rxEnterCR) ControlExpect(8'h0d);
    if (rxEnterLF) ControlExpect(8'h0a);
  endtask // ControlExpectEnter

  task ControlExpectString ( input string s );
    for (int i=0; i<s.len(); i++) ControlExpect(s[i]);
  endtask // ControlExpectRxByte

  task ControlExpectMultiple ( input [7:0] b [$] );
    if (Verbose) $display("%t %m: Expecting %0d Bytes...", $realtime, b.size());
    for (int i=0; i<b.size(); i++) ControlExpect(b[i]);
  endtask // ControlExpectMultiple

  task ControlReceiveEnter();
    if (rxEnterCR) ControlReceiveCheck(8'h0d);
    if (rxEnterLF) ControlReceiveCheck(8'h0a);
  endtask // ReceiveEnter

  task ControlSendInt ( input [63:0] v, input binaryMode = 0, input integer len );
    int c;
    bit done;
    c = '0;
    done = 0;
    while (!done) begin
        if (binaryMode) begin
          ControlSend((v >> (8*(len-1-c))) & 8'hff);
          if (c++ >= (len-1)) done = 1;
        end
        else begin
          ControlSend(oclib_pkg::HexToAsciiNibble(v >> (4*((len*2)-1-c))) & 8'hf);
          if (c++ >= ((2*len)-1)) done = 1;
        end
    end
  endtask // ControlSendInt

  task ControlSendInt8 ( input [7:0] v, input binaryMode = 0 );
    ControlSendInt({'0,v}, binaryMode, 1);
  endtask // ControlSendInt8

  task ControlSendInt16 ( input [15:0] v, input binaryMode = 0 );
    ControlSendInt({'0,v}, binaryMode, 2);
  endtask // ControlSendInt16

  task ControlSendInt32 ( input [31:0] v, input binaryMode = 0 );
    ControlSendInt({'0,v}, binaryMode, 4);
  endtask // ControlSendInt32

  task ControlSendInt64 ( input [63:0] v, input binaryMode = 0 );
    ControlSendInt(v, binaryMode, 8);
  endtask // ControlSendInt64

  task ControlReceiveInt ( output [63:0] v, input integer maxNS = 1000000, input binaryMode = 0, input integer len );
    int i;
    int c;
    bit done;
    logic [7:0] temp8;
    logic [63:0] temp64;
    i = '0;
    c = '0;
    done = 0;
    temp64 = 'X;
    while (!done) begin
      ControlReceive(temp8, maxNS/4);
      if (binaryMode) begin
        temp64 = { temp64[55:0], temp8 };
        if (c++ >= (len-1)) done = 1;
      end
      else begin
        temp64 = { temp64[59:0], oclib_pkg::AsciiToHexNibble(temp8) };
        if (c++ >= ((2*len)-1)) done = 1;
      end
      if (done) v = temp64;
    end
  endtask // ControlReceiveInt

  task ControlReceiveInt8 ( output [7:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    logic [63:0] o;
    ControlReceiveInt( o, maxNS, binaryMode, 1);
    v = o[7:0];
  endtask // ControlReceiveInt8

  task ControlReceiveInt16 ( output [15:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    logic [63:0] o;
    ControlReceiveInt( o, maxNS, binaryMode, 2);
    v = o[15:0];
  endtask // ControlReceiveInt16

  task ControlReceiveInt32 ( output [31:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    logic [63:0] o;
    ControlReceiveInt( o, maxNS, binaryMode, 4);
    v = o[31:0];
  endtask // ControlReceiveInt32

  task ControlReceiveInt64 ( output [63:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    ControlReceiveInt( v, maxNS, binaryMode, 8);
  endtask // ControlReceiveInt64

  string topCsrName;
  initial topCsrName = $sformatf("%m.TopCsr");

  task TopCsrRead(input [oclib_pkg::BlockIdBits-1:0] block,
               input [oclib_pkg::SpaceIdBits-1:0] space,
               input [31:0]                       address,
               output logic [31:0]                data);
    TopCsrProtocol csr;
    TopCsrFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %s: Read     ....   <= [%02x][%1x][%08x]", $realtime, topCsrName, block, space, address);
    csr = '0;
    csr.toblock = block;
    csr.space = space;
    csr.read = 1;
    csr.address = address;
    csr.wdata = '0;
    payloadRequest = csr;
    ControlSend("B");
    ControlSend(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) ControlSend(payloadRequest[i]);
    ControlReceiveCheck(ResponseBytes+1);
    for (int i=0; i<ResponseBytes; i++) ControlReceive(payloadResponse[i]);
    csrFb = payloadResponse;
    `OC_ASSERT_EQUAL(csrFb.ready,1);
    `OC_ASSERT_EQUAL(csrFb.error,0);
    data = csrFb.rdata;
    $display("%t %s:        %08x <= [%02x][%1x][%08x] (OK)", $realtime, topCsrName, data, block, space, address);
    ControlWaitForIdle();
    ControlSendEnter();
    TestExpectPrompt();
  endtask

  task TopCsrReadCheck(input [oclib_pkg::BlockIdBits-1:0] block,
                    input [oclib_pkg::SpaceIdBits-1:0] space,
                    input [31:0]                       address,
                    input [31:0]                       data,
                    input [31:0]                       mask = 32'hffffffff,
                    input                              ready = 1,
                    input                              error = 0);
    TopCsrProtocol csr;
    TopCsrFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;
    string                          maskString;

    if (mask == 32'hffffffff) maskString = "";
    else maskString = $sformatf(" (Mask = %08x)", mask);
    $display("%t %s: Expect %08x <= [%02x][%1x][%08x]%s", $realtime, topCsrName, data, block, space, address, maskString);
    csr = '0;
    csr.read = 1;
    csr.toblock = block;
    csr.space = space;
    csr.address = address;
    csr.wdata = '0;
    payloadRequest = csr;
    ControlSend("B");
    ControlSend(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) ControlSend(payloadRequest[i]);
    ControlReceiveCheck(ResponseBytes+1);
    for (int i=0; i<ResponseBytes; i++) ControlReceive(payloadResponse[i]);
    csrFb = payloadResponse;
    `OC_ASSERT_EQUAL(csrFb.ready, ready);
    `OC_ASSERT_EQUAL(csrFb.error, error);
    if ((csrFb.rdata & mask) !== (data & mask)) begin
      $display("%t %s: ERROR: %08x <= [%02x][%1x][%08x] (Mismatch bits:%08x)", $realtime, topCsrName,
               csrFb.rdata, block, space, address, ((csrFb.rdata ^ data) & mask) );
      `OC_ERROR("CSR read mismatch error");
    end
    $display("%t %s:        %08x <= [%02x][%1x][%08x] (OK, Match)", $realtime, topCsrName, data, block, space, address);
    ControlWaitForIdle();
    ControlSendEnter();
    TestExpectPrompt();
  endtask

  task TopCsrWrite(input [oclib_pkg::BlockIdBits-1:0] block,
                input [oclib_pkg::SpaceIdBits-1:0] space,
                input [31:0]                       address,
                input [31:0]                       data,
                input [31:0]                       rdata = '0,
                input                              ready = 1,
                input                              error = 0);
    TopCsrProtocol csr;
    TopCsrFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %s: Write  %08x => [%02x][%1x][%08x]", $realtime, topCsrName, data, block, space, address);
    csr = '0;
    csr.write = 1;
    csr.toblock = block;
    csr.space = space;
    csr.address = address;
    csr.wdata = data;
    payloadRequest = csr;
    ControlSend("B");
    ControlSend(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) ControlSend(payloadRequest[i]);
    ControlReceiveCheck(ResponseBytes+1);
    for (int i=0; i<ResponseBytes; i++) ControlReceive(payloadResponse[i]);
    csrFb = payloadResponse;
    `OC_ASSERT_EQUAL(csrFb.ready, ready);
    `OC_ASSERT_EQUAL(csrFb.error, error);
    `OC_ASSERT_EQUAL(csrFb.rdata, rdata);
    $display("%t %s:        %08x => [%02x][%1x][%08x] (OK)", $realtime, topCsrName, data, block, space, address);
    ControlWaitForIdle();
    ControlSendEnter();
    TestExpectPrompt();
  endtask // TopCsrWrite

  // The following APIs look for OC control specific things (prompts, errors, etc)

  task TestExpectBanner();
    ControlExpect(8'h0d);
    ControlExpect(8'h0a);
    ControlExpectString("* OPENCOS *");
    TestExpectPrompt();
  endtask // TestExpectBanner

  task TestExpectError();
    ControlExpect(8'h0d);
    ControlExpect(8'h0a);
    ControlExpectString("ERROR");
    TestExpectPrompt();
  endtask // TestExpectError

  task TestExpectPrompt();
    ControlExpect(8'h0d);
    ControlExpect(8'h0a);
    ControlExpectString("OC>");
    ControlWaitForIdle();
  endtask // TestExpectPrompt

  task TestExpectIdle();
    ControlExpectIdle();
  endtask // TestExpectIdle

  // The following APIs are whole testcases that are called in the initial block

  task TestSanity();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sanity check comms", $realtime);
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: *** SANITY: Expect to receive prompt", $realtime);
    TestExpectBanner();
    $display("%t %m: *** SANITY: Check that it stays idle", $realtime);
    TestExpectIdle();
  endtask // TestSanity

  task TestReset();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 64x'~' to reset the DUT", $realtime);
    $display("%t %m: ******************************************", $realtime);
    for (int i=0; i<64; i++) begin
      ControlSend("~");
    end
    $display("%t %m: Expect to receive prompt again", $realtime);
    TestExpectBanner();
    TestExpectIdle();
  endtask // TestReset

  task TestBlankLines();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending '<CR><LF>' to get new prompt from the DUT (3 times)", $realtime);
    $display("%t %m: ******************************************", $realtime);
    repeat (3) begin
      ControlSendEnter();
      TestExpectPrompt();
      TestExpectIdle();
   end
  endtask

  task TestSyntaxError();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 'ABC' syntax error to the DUT", $realtime);
    $display("%t %m: ******************************************", $realtime);
    ControlSend("A");
    ControlSend("B");
    ControlSend("C");
    $display("%t %m: Checking there's no response yet", $realtime);
    TestExpectIdle();
    $display("%t %m: Sending '<Enter>'", $realtime);
    ControlSendEnter();
    TestExpectError();
    TestExpectIdle();
  endtask // TestSyntaxError

  task TestControlC();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 'ABC' then <Ctrl-C> to avoid error", $realtime);
    $display("%t %m: ******************************************", $realtime);
    ControlSend("A");
    ControlSend("B");
    ControlSend("C");
    $display("%t %m: Checking there's no response yet", $realtime);
    TestExpectIdle();
    $display("%t %m: Sending '<Ctrl-C>'", $realtime);
    ControlSend(8'h03);
    ControlExpect("^");
    ControlExpect("C");
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestControlC

  task TestTimers();
    logic [31:0] temp32;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Requesting Timers", $realtime);
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: ** ASCII Mode **", $realtime);
    ControlSend("t");
    ControlSendEnter();
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: Uptime since reload: %08x", $realtime, temp32);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: Uptime since reset : %08x", $realtime, temp32);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: Cycles since reset : %08x", $realtime, temp32);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: Cycles under reset : %08x", $realtime, temp32);
    TestExpectPrompt();
    TestExpectIdle();
    $display("%t %m: ** BINARY Mode **", $realtime);
    ControlSend("T");
    ControlSendEnter();
    ControlReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Uptime since reload: %08x", $realtime, temp32);
    ControlReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Uptime since reset : %08x", $realtime, temp32);
    ControlReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Cycles since reset : %08x", $realtime, temp32);
    ControlReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Cycles under reset : %08x", $realtime, temp32);
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestTimers

  task TestInfo();
    logic [31:0] temp32;
    int          i;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Requesting Info", $realtime);
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: ** ASCII Mode **", $realtime);
    ControlSend("i");
    ControlSendEnter();
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: InfoVersion        :       %02x", $realtime, temp32[31:24]);
    $display("%t %m: BuilderID          :   %06x", $realtime, temp32[23:0]);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: BitstreamID        : %08x", $realtime, temp32);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: BuildDate          : %08x", $realtime, temp32);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: BuildTime          :    %02x:%02x", $realtime, temp32[31:24], temp32[23:16]);
    $display("%t %m: TargetVendor       :     %04x", $realtime, temp32[15:0]);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: TargetLibrary      :     %04x", $realtime, temp32[31:16]);
    $display("%t %m: TargetBoard        :     %04x", $realtime, temp32[15:0]);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: BlockTopCount      :     %04x", $realtime, temp32[31:16]);
    $display("%t %m: BlockUserCount     :     %04x", $realtime, temp32[15:0]);
    blockTopCount = temp32[31:16];
    blockUserCount = temp32[15:0];
    for (i=0; i<2; i++) begin
      ControlReceiveEnter();
      ControlReceiveInt32(temp32);
    end
    for (i=0; i<4; i++) begin
      ControlReceiveEnter();
      ControlReceiveInt32(temp32);
      $display("%t %m: UserSpace%1x         : %08x", $realtime, i, temp32);
    end
    for (i=0; i<4; i++) begin
      ControlReceiveEnter();
      ControlReceiveInt32(temp32);
      $display("%t %m: BuildUUID%1x         : %08x", $realtime, i, temp32);
    end
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestInfo

  task TestUserSpace();
    // for now it's just assumed to be membist
    for (int i=0; i< (`OC_COS . UserCsrCount); i++) begin
      userCsrCurrent = i;
      TestUserMemoryBist();
    end
  endtask // TestUserSpace

  localparam type MemoryBistAximType = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_AXIM_TYPE, oclib_pkg::axi4m_256_s);
  localparam type MemoryBistAximFbType = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_AXIM_FB_TYPE, oclib_pkg::axi4m_256_fb_s);
  localparam int MemoryBistPortCount = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_PORT_COUNT,1);
  localparam int MemoryBistMemoryBytes = `OC_VAL_ASDEFINED_ELSE(OC_MEMORY_BIST_RAM_BYTES,65536);

  MemoryBistAximType mtat;
  localparam int MemoryBistDataWidth = $bits(mtat.w.data);
  localparam int MemoryBistDataBytes = (MemoryBistDataWidth/8);

  localparam int MemoryBistAddressBits = $clog2(MemoryBistMemoryBytes);
  localparam int MemoryBistPortNumberBits = $clog2(MemoryBistPortCount);

  task TestUserMemoryBist();
    logic [31:0] data;
    string       m;
    m = $sformatf("%m");
    $display("%t %s: ******************************************", $realtime, m);
    $display("%t %s: Testing User Memory BIST application", $realtime, m);
    $display("%t %s: ******************************************", $realtime, m);

    $display("%t %s: *** Memory BIST sanity check comms", $realtime, m);
    UserCsrReadCheck32(32'h0000_0000, 32'h80000000);
    UserCsrReadCheck32(32'h0000_0034, 32'h4d454d54);
    UserCsrWrite32    (32'h0000_0034, 32'h00000000);
    UserCsrReadCheck32(32'h0000_0034, 32'h4d454d54);
    UserCsrWrite32    (32'h0000_0000, 32'h00ffff00);
    UserCsrReadCheck32(32'h0000_0000, 32'h80ffff00);

    $display("%t %s: *** Memory BIST read timers", $realtime, m);
    UserCsrRead32(32'h0000_0300, data);
    $display("%t %s: ReloadSeconds:        %0d", $realtime, m, data);
    UserCsrRead32(32'h0000_0304, data);
    $display("%t %s: ResetSeconds:         %0d", $realtime, m, data);
    UserCsrRead32(32'h0000_0308, data);
    $display("%t %s: AxilWrites            %0d", $realtime, m, data);
    UserCsrRead32(32'h0000_030c, data);
    $display("%t %s: AxilReads             %0d", $realtime, m, data);
    UserCsrRead32(32'h0000_0310, data);
    $display("%t %s: CyclesUnderReset      %0d", $realtime, m, data);
    UserCsrRead32(32'h0000_0314, data);
    $display("%t %s: CyclesSinceReset      %0d", $realtime, m, data);
    UserCsrRead32(32'h0000_0038, data);
    $display("%t %s: AxiCyclesUnderReset   %0d", $realtime, m, data);
    UserCsrRead32(32'h0000_003c, data);
    $display("%t %s: AxiCyclesSinceReset   %0d", $realtime, m, data);

    $display("%t %s: *** Memory BIST single write", $realtime, m);
    MemoryBistWrite(.pattern(1));
    $display("%t %s: *** Memory BIST single read", $realtime, m);
    MemoryBistRead(.pattern(1));

    $display("%t %s: *** Memory BIST burst write", $realtime, m);
    MemoryBistWrite(.pattern(1), .opCount(256));
    $display("%t %s: *** Memory BIST burst read", $realtime, m);
    MemoryBistRead(.pattern(1), .opCount(256));

  endtask // TestUserMemoryBist

  task MemoryBistWrite(
                       input int          pattern = 'd0, // default is not setting pattern
                       input int          opCount = 'd1,
                       input logic [31:0] ports = ((1<<MemoryBistPortCount)-1),
                       input logic [63:0] address = 'd0,
                       input logic [63:0] addressInc = (MemoryBistDataWidth/8),
                       input logic [63:0] addressIncMask = (MemoryBistMemoryBytes-1),
                       input int          portShift = (MemoryBistAddressBits-MemoryBistPortNumberBits-1),
                       input int          portShiftMask = (MemoryBistPortCount-1)
                       );
    logic [31:0] temp32;
    if ((pattern & 'hff) == 1) begin
      // write pattern
      for (int i=1; i<=8; i++) begin
        temp32 = ((pattern == 1) ? {8{i[3:0]}} : i);
        UserCsrWrite32('h0100 + ((i-1)*4), temp32);
        if (pattern & 'h100) UserCsrReadCheck32('h0100 + ((i-1)*4), temp32); // optional readback
      end
      // set op count
      UserCsrWrite32('h0004, (opCount-1));
      // enable ports
      UserCsrWrite32('h0008, ports);
      // address
      UserCsrWrite32('h0010, address[31:0]);
      UserCsrWrite32('h0014, address[63:32]);
      // address inc
      UserCsrWrite32('h0018, addressInc[31:0]);
      UserCsrWrite32('h001c, addressInc[63:32]);
      // address inc mask
      UserCsrWrite32('h0020, addressIncMask[31:0]);
      UserCsrWrite32('h0024, addressIncMask[63:32]);
      // port shift
      UserCsrWrite32('h004c, (portShiftMask<<16)|portShift);
      // set write, go, no prescale
      UserCsrWrite32('h0000, 32'h0000_0101);
      // poll done
      temp32 = '0;
      while ((temp32 & 'h80000000) == 0) UserCsrRead32('h0000, temp32);
      // clear go
      UserCsrWrite32('h0000, 32'h0000_0000);
    end
  endtask

  task MemoryBistRead(
                       input int          pattern = 'd0, // default is not setting pattern
                       input int          opCount = 'd1,
                       input logic [31:0] ports = ((1<<MemoryBistPortCount)-1),
                       input logic [63:0] address = 'd0,
                       input logic [63:0] addressInc = (MemoryBistDataWidth/8),
                       input logic [63:0] addressIncMask = (MemoryBistMemoryBytes-1),
                       input int          portShift = (MemoryBistAddressBits-MemoryBistPortNumberBits-1),
                       input int          portShiftMask = (MemoryBistPortCount-1),
                       input logic [31:0] signature = (((MemoryBistDataWidth==256) && (opCount==1)) ? 32'h66666664 :
                                                       ((MemoryBistDataWidth==256) && (opCount==256)) ? 32'ha22221c8 :
                                                       32'hbade1212), // need caller to specify for unknown cases
                       input bit          readDataCheck = oclib_pkg::True,
                       input bit          signatureCheck = oclib_pkg::True
                       );
    logic [31:0] temp32;
    if ((pattern & 'hff) == 1) begin
      // set op count
      UserCsrWrite32('h0004, (opCount-1));
      // enable ports
      UserCsrWrite32('h0008, ports);
      // address
      UserCsrWrite32('h0010, address[31:0]);
      UserCsrWrite32('h0014, address[63:32]);
      // address inc
      UserCsrWrite32('h0018, addressInc[31:0]);
      UserCsrWrite32('h001c, addressInc[63:32]);
      // address inc mask
      UserCsrWrite32('h0020, addressIncMask[31:0]);
      UserCsrWrite32('h0024, addressIncMask[63:32]);
      // port shift
      UserCsrWrite32('h004c, (portShiftMask<<16)|portShift);
      // set read, go, no prescale
      UserCsrWrite32('h0000, 32'h0001_0001);
      // poll done
      temp32 = '0;
      while ((temp32 & 'h80000000) == 0) UserCsrRead32('h0000, temp32);
      // clear go
      UserCsrWrite32('h0000, 32'h0000_0000);
      // check read data
      if (readDataCheck) begin
        for (int i=1; i<=8; i++) begin
          temp32 = ((pattern == 1) ? {8{i[3:0]}} : i);
          UserCsrReadCheck32('h0100 + ((i-1)*4), temp32);
        end
      end
      // check signature
      if (signatureCheck) begin
        UserCsrReadCheck32('h0028, signature);
      end
    end
  endtask

  integer                           foundPlls = 0;
  integer                           foundChipMons = 0;
  integer                           foundIics = 0;
  integer                           foundLeds = 0;
  integer                           foundGpios = 0;
  integer                           foundFans = 0;
  integer                           foundHbms = 0;
  integer                           foundCmacs = 0;
  integer                           foundProtects = 0;
  integer                           foundDummys = 0; // yes I know the spelling
  integer                           foundPcies = 0;
  integer                           foundUnknowns = 0;

  task TestEnumerate();
    logic [15:0] blockType;
    logic [15:0] blockParams;
    logic [31:0] readData;
    int          b, s, i;
    string       m;

    // if we haven't run the top info gathering, we need to probe design to figure out the number of top blocks
    if (blockTopCount == -1) blockTopCount = `OC_COS.BlockTopCount;
    if (blockUserCount == -1) blockUserCount = `OC_COS.BlockUserCount;

    m = $sformatf("%m");
    $display("%t %s: ******************************************", $realtime, m);
    $display("%t %s: Enumerating %0d top blocks", $realtime, m, blockTopCount);
    $display("%t %s: ******************************************", $realtime, m);
    for (b=0; b<blockTopCount; b++) begin

      $display("%t %s: ****************************", $realtime, m);
      $display("%t %s: Reading Block %0d...", $realtime, m, b);
      TopCsrRead(b, 0, 32'h0, {blockType, blockParams});

      if (blockType == oclib_pkg::CsrIdPll) begin : pll
        logic [7:0] PllType;
        logic [3:0] OutClockCount;
        logic       MeasureEnable, ThrottleMap, AutoThrottle;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: PLL #%0d ***", $realtime, m, blockType, foundPlls);
        PllType = blockParams[15:8];
        OutClockCount = blockParams[7:4];
        AutoThrottle = blockParams[2];
        ThrottleMap = blockParams[1];
        MeasureEnable = blockParams[0];
        $display("%t %s: Param: PllType=%0d", $realtime, m, PllType);
        $display("%t %s: Param: OutClockCount=%0d", $realtime, m, OutClockCount);
        $display("%t %s: Param: MeasureEnable=%0d", $realtime, m, MeasureEnable);
        $display("%t %s: Param: ThrottleMap=%0d", $realtime, m, ThrottleMap);
        $display("%t %s: Param: AutoThrottle=%0d", $realtime, m, AutoThrottle);
        if (PllType == 0) begin
          $display("%t %s: Type==0 means 'NONE', so skipping further checks", $realtime, m);
        end
        else begin
          $display("%t %s: *** Testing MMCME4_ADV PLL", $realtime, m);
          TopCsrWrite    (b, 0, 'h0004, 32'h00000001); // assert reset to PLL
          TopCsrReadCheck(b, 1, 'h0008, 32'h00001000, .mask(32'h00001000)); // check a DRP read
          TopCsrWrite    (b, 0, 'h0004, 32'h00000000); // deassert reset to PLL
          TopCsrRead     (b, 0, 'h0004, readData); // read csr 0
          TopCsrWrite    (b, 0, 'h0008, 32'h00000001); // trigger thermal warning
          TopCsrWrite    (b, 0, 'h0008, 32'h00001101); // throttle to 25%
          TopCsrWrite    (b, 0, 'h0008, 32'h00000000); // throttling disabled
          TopCsrRead     (b, 0, 'h0008, readData); // read clock 0
          #200us;
          TopCsrRead     (b, 0, 'h0008, readData); // read clock 0
       end
        $display("%t %s: ****************************", $realtime, m);
        foundChipMons++;
      end

      else if (blockType == oclib_pkg::CsrIdChipMon) begin : chipmon
        logic InternalReference;
        logic [7:0] ChipMonType;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: CHIPMON #%0d ***", $realtime, m, blockType, foundChipMons);
        ChipMonType = blockParams[15:8];
        InternalReference = blockParams[0];
        $display("%t %s: Param: InternalReference=%0d", $realtime, m, InternalReference);
        $display("%t %s: Param: ChipMonType=%0d", $realtime, m, ChipMonType);
        if (ChipMonType == 0) begin
          $display("%t %s: Type==0 means 'NONE', so skipping further checks", $realtime, m);
          continue;
        end
        $display("%t %s: Reading temperature (not sure what to expect, hard to predict0", $realtime, m);
        TopCsrRead (b, 1, 'h0000, readData); // DRP space
        if (RefClockHz[ClockTop] == 100_000_000) TopCsrReadCheck (b, 1, 'h0042, 'h1600); // DRP space
        if (RefClockHz[ClockTop] == 156_250_000) TopCsrReadCheck (b, 1, 'h0042, 'h2200); // DRP space
        TopCsrReadCheck (b, 1, 'h0050, 'hb834); // DRP space (this is warning temp high, 85c)
        TopCsrReadCheck (b, 1, 'h0053, 'hcb00); // DRP space (this is error temp high, 95c)
        $display("%t %s: ****************************", $realtime, m);
        foundChipMons++;
      end

      else if (blockType == oclib_pkg::CsrIdIic) begin : iic
        logic [11:0] OffloadType;
        logic        OffloadEnable;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: IIC #%0d ***", $realtime, m, blockType, foundIics);
        OffloadType = blockParams[15:4];
        OffloadEnable = blockParams[0];
        $display("%t %s: Param: OffloadEnable=%0d", $realtime, m, OffloadEnable);
        $display("%t %s: Param: OffloadType=%0d", $realtime, m, OffloadType);
        $display("%t %s: ****************************", $realtime, m);
        foundIics++;
      end

      else if (blockType == oclib_pkg::CsrIdLed) begin : led
        logic [7:0] NumLeds;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: LED #%0d ***", $realtime, m, blockType, foundLeds);
        NumLeds = blockParams[7:0];
        $display("%t %s: Param: NumLeds=%0d", $realtime, m, NumLeds);
        TopCsrRead (b, 0, 'h0004, readData); // Prescale
        $display("%t %s: Csr[4].prescale=%0d, rewriting it to 2...", $realtime, m, readData);
        TopCsrWrite(b, 0, 'h0004,    32'd2); // speed up prescale
        $display("%t %s: Reading config for each of %0d LEDs", $realtime, m, NumLeds);
        if (NumLeds>0) TopCsrWrite(b, 0, 'h0008, 32'h00003f01); // turn LED 0 on, full brightness
        if (NumLeds>1) TopCsrWrite(b, 0, 'h000c, 32'h00001f01); // turn LED 1 on, half brightness
        if (NumLeds>2) TopCsrWrite(b, 0, 'h0010, 32'h00002f03); // turn LED 2 to heartbeat, 3/4 brightness
        #50us; // give time for user to look at the pretty patterns
        $display("%t %s: ****************************", $realtime, m);
        foundLeds++;
      end

      else if (blockType == oclib_pkg::CsrIdGpio) begin : gpio
        logic [7:0] NumGpios;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: GPIO #%0d ***", $realtime, m, blockType, foundGpios);
        NumGpios = blockParams[7:0];
        $display("%t %s: Param: NumGpios=%0d", $realtime, m, NumGpios);
        for (i=0; i<NumGpios; i++) begin
          TopCsrRead(b, 0, 32'h4 + (i*4), readData);
          $display("%t %s: GPIO[%4d]: out=%0d, drive=%d, in=%d", $realtime, m, i, readData[0], readData[4], readData[8]);
        end
        $display("%t %s: ****************************", $realtime, m);
        foundGpios++;
      end

      else if (blockType == oclib_pkg::CsrIdFan) begin : fan
        logic [7:0] NumFans;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: FAN #%0d ***", $realtime, m, blockType, foundFans);
        NumFans = blockParams[7:0];
        $display("%t %s: Param: NumFans=%0d", $realtime, m, NumFans);
        $display("%t %s: ****************************", $realtime, m);
        foundFans++;
      end

      else if (blockType == oclib_pkg::CsrIdProtect) begin : protect
        logic EnableSkeletonKey;
        logic EnableTimedLicense;
        logic EnableParanoia;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: PROTECT #%0d ***", $realtime, m, blockType, foundProtects);
        EnableSkeletonKey = blockParams[0];
        EnableTimedLicense = blockParams[1];
        EnableParanoia = blockParams[2];
        $display("%t %s: Param: EnableSkeletonKey=%0d", $realtime, m, EnableSkeletonKey);
        $display("%t %s: Param: EnableTimedLicense=%0d", $realtime, m, EnableTimedLicense);
        $display("%t %s: Param: EnableParanoia=%0d", $realtime, m, EnableParanoia);
        $display("%t %s: ****************************", $realtime, m);
        foundProtects++;
      end

      else if (blockType == oclib_pkg::CsrIdDummy) begin : dummy
        logic [7:0] DatapathCount;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: DUMMY #%0d ***", $realtime, m, blockType, foundDummys);
        DatapathCount = blockParams[7:0];
        $display("%t %s: Param: DatapathCount=%0d", $realtime, m, DatapathCount);
        TopCsrRead(b, 0, 32'h08, readData);
        $display("%t %s: Param: DatapathWidth=%0d DatapathPipeStages=%0d", $realtime, m,
                 ((readData>>16)&'hffff), ((readData>>0)&'hffff));
        TopCsrRead(b, 0, 32'h0c, readData);
        $display("%t %s: Param: DatapathLogicLevels=%0d DatapathLutInputs=%0d", $realtime, m,
                 ((readData>>24)&'hff), ((readData>>20)&'hf));
        // run the engine for a bit
        TopCsrWrite(b, 0, 32'h14, 32'h00000000); // one chunk
        TopCsrWrite(b, 0, 32'h04, 32'h00000001); // go
        readData = 32'h00000000;
        while (readData[31] == 0) begin
          TopCsrRead(b, 0, 32'h4, readData);
        end
        TopCsrReadCheck(b, 0, 32'h18, 32'hd1ff271f);
        TopCsrWrite(b, 0, 32'h04, 32'h00000000); // !go
        `ifdef OC_SIM_LONG
        // run the engine for two iterations
        TopCsrWrite(b, 0, 32'h14, 32'h00000001); // two chunks
        TopCsrWrite(b, 0, 32'h04, 32'h00000001); // go
        readData = 32'h00000000;
        while (readData[31] == 0) begin
          TopCsrRead(b, 0, 32'h4, readData);
        end
        TopCsrReadCheck(b, 0, 32'h18, 32'hf7e39155);
        TopCsrWrite(b, 0, 32'h04, 32'h00000000); // !go
        `endif
        $display("%t %s: ****************************", $realtime, m);
        foundDummys++;
      end

      else if (blockType == oclib_pkg::CsrIdPcie) begin : pcie
        logic [3:0] Instance;
        logic [3:0] PcieWidthLog2;
        $display("%t %s: ****************************", $realtime, m);
        $display("%t %s: *** Found: Type %04x: PCIE #%0d ***", $realtime, m, blockType, foundPcies);
        Instance = blockParams[3:0];
        PcieWidthLog2 = blockParams[7:4];
        $display("%t %s: Param: Instance=%0d", $realtime, m, Instance);
        $display("%t %s: Param: PcieWidthLog2=%0d (x%0d)", $realtime, m, PcieWidthLog2, 1<<PcieWidthLog2);
        $display("%t %s: ****************************", $realtime, m);
        foundPcies++;
      end

      else begin
        $display("%t %s:  ***Found : Type %04x: UNKNOWN #%0d ***", $realtime, m, blockType, foundUnknowns);
        $display("%t %s: ****************************", $realtime, m);
        foundUnknowns++;
      end

    end // for (b=0; b<blockTopCount; b++)

  endtask // TestEnumerate

  initial begin
    error = 0;
    $display("%t %m: *****************************", $realtime);
    $display("%t %m: START", $realtime);
    $display("%t %m: *****************************", $realtime);

    TestConfirmParams();

    $display("%t %m: Waiting 1us for reset to complete", $realtime);
    #1us;

    TestSanity();
    //TestReset();
    //TestBlankLines();
    //TestSyntaxError();
    //TestControlC();
    //TestTimers();
    //TestInfo();
    //TestEnumerate();
    TestUserSpace();

    #100us;
    // #10ms; // for watching the LEDs

    $display("%t %m: *****************************", $realtime);
    if (error) $display("%t %m: TEST FAILED", $realtime);
    else $display("%t %m: TEST PASSED", $realtime);
    $display("%t %m: *****************************", $realtime);
    $finish;
  end


endmodule // oc_cos_test
