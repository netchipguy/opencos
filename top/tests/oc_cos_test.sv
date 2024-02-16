
// SPDX-License-Identifier: MPL-2.0

`include "top/oc_top_pkg.sv"
`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oc_cos_test
  #(
    // *******************************************************************************
    // ***                         EXTERNAL CONFIGURATION                          ***
    // Interfaces to the chip top
    // *******************************************************************************

    // *** MISC ***
    parameter integer Seed = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_SEED,0),
    parameter bit     EnableUartControl = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_ENABLE_UART_CONTROL,1),

    // *** REFCLOCK ***
    parameter integer RefClockCount = 1,
                      `OC_LOCALPARAM_SAFE(RefClockCount),
    parameter integer RefClockHz [0:RefClockCount-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_REFCLOCK_HZ,'{RefClockCount{156_250_000}}),
    parameter integer DiffRefClockCount = 2,
                      `OC_LOCALPARAM_SAFE(DiffRefClockCount),
    parameter integer DiffRefClockHz [0:DiffRefClockCountSafe-1] = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_DIFFREFCLOCK_HZ,
                      '{DiffRefClockCountSafe{161_132_812}}),

    // *** TOP CLOCK ***
    parameter integer ClockTop = oc_top_pkg::ClockIdSingleEndedRef(0),

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
    parameter integer UartCount = 2,
                      `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = {10_000_000,115_200},
    parameter integer UartControl = 0,

    // *******************************************************************************
    // ***                         INTERNAL CONFIGURATION                          ***
    // Configuring OC_COS internals which board can override in target-specific ways
    // *******************************************************************************

    // *** Format of Top-Level CSR bus ***
    parameter         type CsrTopType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrTopFbType = oclib_pkg::bc_8b_bidi_s,
    parameter         type CsrTopProtocol = oclib_pkg::csr_32_tree_s,
    parameter         type CsrTopFbProtocol = oclib_pkg::csr_32_tree_fb_s,

    // *******************************************************************************
    // ***                        TESTBENCH CONFIGURATION                          ***
    // *******************************************************************************
    parameter integer Verbose = `OC_VAL_ASDEFINED_ELSE(OC_SIM_VERBOSE, 0)
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
  // *** LED ***
  logic [LedCountSafe-1:0]      ledOut;
  // *** UART ***
  logic [UartCountSafe-1:0]     uartRx;
  logic [UartCountSafe-1:0]     uartTx;
  // *** MISC ***
  logic                         thermalWarning;
  logic                         thermalError;


  integer                       blockTopCount = 0;
  integer                       blockUserCount = 0;


  for (genvar i=0; i<RefClockCount; i++) begin
    ocsim_clock #(.ClockHz(RefClockHz[i])) uCLOCK (.clock(clockRef[i]));
  end
  for (genvar i=0; i<DiffRefClockCount; i++) begin
    ocsim_clock #(.ClockHz(DiffRefClockHz[i])) uDIFFCLOCK (.clock(clockDiffRefP[i]));
    assign clockDiffRefN[i] = ~clockDiffRefP[i];
  end
  ocsim_reset uHARD_RESET (.clock(clockRef[0]), .reset(hardReset));

  ocsim_uart #(.Baud(UartBaud[UartControl]), .Verbose(Verbose))
  uCONTROL_UART (.rx(uartTx[0]), .tx(uartRx[0]));

  // in OC_COS testing mode (default), we pass params from above and the DUT conforms to what
  // we setup.  In BOARD testing mode, we don't override the board params, just config the TB
  // to match the board.  It's up to us to config the TB as needed to match the board.  It
  // shouldn't require different defines for the TB vs BOARD params, but we may have to revisit.

`ifdef OC_CHIP_HARNESS_TEST

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
            .thermalWarning(thermalWarning),
            .thermalError(thermalError)
            );

`else

  oc_cos #(.Seed(Seed),
           .EnableUartControl(EnableUartControl),
           .RefClockCount(RefClockCount),
           .RefClockHz(RefClockHz),
           .ClockTop(ClockTop),
           .ChipMonCount(ChipMonCount),
           .LedCount(LedCount),
           .UartCount(UartCount),
           .UartBaud(UartBaud),
           .UartControl(UartControl),
           .CsrTopType(CsrTopType),
           .CsrTopFbType(CsrTopFbType))
  uDUT (
        .clockRef(clockRef),
        .hardReset(hardReset),
        .chipMonScl(chipMonScl),
        .chipMonSclTristate(chipMonSclTristate),
        .chipMonSda(chipMonSda),
        .chipMonSdaTristate(chipMonSdaTristate),
        .ledOut(ledOut),
        .uartRx(uartRx),
        .uartTx(uartTx),
        .thermalWarning(thermalWarning),
        .thermalError(thermalError)
        );

  `endif

  task TestExpectBanner();
    uCONTROL_UART.Expect(8'h0d);
    uCONTROL_UART.Expect(8'h0a);
    uCONTROL_UART.ExpectString("* OPENCOS *");
    TestExpectPrompt();
  endtask // TestExpectBanner

  task TestExpectError();
    uCONTROL_UART.Expect(8'h0d);
    uCONTROL_UART.Expect(8'h0a);
    uCONTROL_UART.ExpectString("ERROR");
    TestExpectPrompt();
  endtask // TestExpectError

  task TestExpectPrompt();
    uCONTROL_UART.Expect(8'h0d);
    uCONTROL_UART.Expect(8'h0a);
    uCONTROL_UART.ExpectString("OC>");
    uCONTROL_UART.WaitForIdle();
  endtask // TestExpectPrompt

  task TestExpectIdle();
    repeat (50) uCONTROL_UART.WaitBit();
    `OC_ASSERT(uCONTROL_UART.rxQ.size() == 0);
  endtask // TestExpectIdle

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
      uCONTROL_UART.Send("~");
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
      uCONTROL_UART.SendEnter();
      TestExpectPrompt();
      TestExpectIdle();
   end
  endtask

  task TestSyntaxError();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 'ABC' syntax error to the DUT", $realtime);
    $display("%t %m: ******************************************", $realtime);
    uCONTROL_UART.Send("A");
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send("C");
    $display("%t %m: Checking there's no response yet", $realtime);
    TestExpectIdle();
    $display("%t %m: Sending '<Enter>'", $realtime);
    uCONTROL_UART.SendEnter();
    TestExpectError();
    TestExpectIdle();
  endtask // TestSyntaxError

  task TestControlC();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 'ABC' then <Ctrl-C> to avoid error", $realtime);
    $display("%t %m: ******************************************", $realtime);
    uCONTROL_UART.Send("A");
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send("C");
    $display("%t %m: Checking there's no response yet", $realtime);
    TestExpectIdle();
    $display("%t %m: Sending '<Ctrl-C>'", $realtime);
    uCONTROL_UART.Send(8'h03);
    uCONTROL_UART.Expect("^");
    uCONTROL_UART.Expect("C");
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestControlC

  task TestTimers();
    logic [31:0] temp32;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Requesting Timers", $realtime);
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: ** ASCII Mode **", $realtime);
    uCONTROL_UART.Send("t");
    uCONTROL_UART.SendEnter();
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: Uptime since reload: %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: Uptime since reset : %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: Cycles since reset : %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: Cycles under reset : %08x", $realtime, temp32);
    TestExpectPrompt();
    TestExpectIdle();
    $display("%t %m: ** BINARY Mode **", $realtime);
    uCONTROL_UART.Send("T");
    uCONTROL_UART.SendEnter();
    uCONTROL_UART.ReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Uptime since reload: %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Uptime since reset : %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Cycles since reset : %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveInt32(temp32, .binaryMode(1));
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
    uCONTROL_UART.Send("i");
    uCONTROL_UART.SendEnter();
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: InfoVersion        :       %02x", $realtime, temp32[31:24]);
    $display("%t %m: BuilderID          :   %06x", $realtime, temp32[23:0]);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: BitstreamID        : %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: BuildDate          : %08x", $realtime, temp32);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: BuildTime          :    %02x:%02x", $realtime, temp32[31:24], temp32[23:16]);
    $display("%t %m: TargetVendor       :     %04x", $realtime, temp32[15:0]);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: TargetLibrary      :     %04x", $realtime, temp32[31:16]);
    $display("%t %m: TargetBoard        :     %04x", $realtime, temp32[15:0]);
    uCONTROL_UART.ReceiveEnter();
    uCONTROL_UART.ReceiveInt32(temp32);
    $display("%t %m: BlockTopCount      :     %04x", $realtime, temp32[31:16]);
    $display("%t %m: BlockUserCount     :     %04x", $realtime, temp32[15:0]);
    blockTopCount = temp32[31:16];
    blockUserCount = temp32[15:0];
    for (i=0; i<2; i++) begin
      uCONTROL_UART.ReceiveEnter();
      uCONTROL_UART.ReceiveInt32(temp32);
    end
    for (i=0; i<4; i++) begin
      uCONTROL_UART.ReceiveEnter();
      uCONTROL_UART.ReceiveInt32(temp32);
      $display("%t %m: UserSpace%1x         : %08x", $realtime, i, temp32);
    end
    for (i=0; i<4; i++) begin
      uCONTROL_UART.ReceiveEnter();
      uCONTROL_UART.ReceiveInt32(temp32);
      $display("%t %m: BuildUUID%1x         : %08x", $realtime, i, temp32);
    end
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestInfo

  string csrModuleName;
  initial csrModuleName = $sformatf("%m.CSR");

  task CsrRead(input [oclib_pkg::BlockIdBits-1:0] block,
               input [oclib_pkg::SpaceIdBits-1:0] space,
               input [31:0]                       address,
               output logic [31:0]                data);
    CsrTopProtocol csr;
    CsrTopFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %s: Read     ....   <= [%02x][%1x][%08x]", $realtime, csrModuleName, block, space, address);
    csr = '0;
    csr.toblock = block;
    csr.space = space;
    csr.read = 1;
    csr.address = address;
    csr.wdata = '0;
    payloadRequest = csr;
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uCONTROL_UART.Send(payloadRequest[i]);
    uCONTROL_UART.ReceiveCheck(ResponseBytes+1);
    for (int i=0; i<ResponseBytes; i++) uCONTROL_UART.Receive(payloadResponse[i]);
    csrFb = payloadResponse;
    `OC_ASSERT_EXPECTED(csrFb.ready,1);
    `OC_ASSERT_EXPECTED(csrFb.error,0);
    data = csrFb.rdata;
    $display("%t %s:        %08x <= [%02x][%1x][%08x] (OK)", $realtime, csrModuleName, data, block, space, address);
    uCONTROL_UART.WaitForIdle();
    uCONTROL_UART.SendEnter();
    TestExpectPrompt();
  endtask

  task CsrReadCheck(input [oclib_pkg::BlockIdBits-1:0] block,
                    input [oclib_pkg::SpaceIdBits-1:0] space,
                    input [31:0]                       address,
                    input [31:0]                       data,
                    input                              ready = 1,
                    input                              error = 0);
    CsrTopProtocol csr;
    CsrTopFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %s: Expect %08x <= [%02x][%1x][%08x]", $realtime, csrModuleName, data, block, space, address);
    csr = '0;
    csr.read = 1;
    csr.toblock = block;
    csr.space = space;
    csr.address = address;
    csr.wdata = '0;
    payloadRequest = csr;
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uCONTROL_UART.Send(payloadRequest[i]);
    uCONTROL_UART.ReceiveCheck(ResponseBytes+1);
    for (int i=0; i<ResponseBytes; i++) uCONTROL_UART.Receive(payloadResponse[i]);
    csrFb = payloadResponse;
    `OC_ASSERT_EQUAL(csrFb.ready, ready);
    `OC_ASSERT_EQUAL(csrFb.error, error);
    `OC_ASSERT_EQUAL(csrFb.rdata, data);
    $display("%t %s:        %08x <= [%02x][%1x][%08x] (OK, Match)", $realtime, csrModuleName, data, block, space, address);
    uCONTROL_UART.WaitForIdle();
    uCONTROL_UART.SendEnter();
    TestExpectPrompt();
  endtask

  task CsrWrite(input [oclib_pkg::BlockIdBits-1:0] block,
                input [oclib_pkg::SpaceIdBits-1:0] space,
                input [31:0]                       address,
                input [31:0]                       data,
                input [31:0]                       rdata = '0,
                input                              ready = 1,
                input                              error = 0);
    CsrTopProtocol csr;
    CsrTopFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %s: Write  %08x => [%02x][%1x][%08x]", $realtime, csrModuleName, data, block, space, address);
    csr = '0;
    csr.write = 1;
    csr.toblock = block;
    csr.space = space;
    csr.address = address;
    csr.wdata = data;
    payloadRequest = csr;
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uCONTROL_UART.Send(payloadRequest[i]);
    uCONTROL_UART.ReceiveCheck(ResponseBytes+1);
    for (int i=0; i<ResponseBytes; i++) uCONTROL_UART.Receive(payloadResponse[i]);
    csrFb = payloadResponse;
    `OC_ASSERT_EQUAL(csrFb.ready, ready);
    `OC_ASSERT_EQUAL(csrFb.error, error);
    `OC_ASSERT_EQUAL(csrFb.rdata, rdata);
    $display("%t %s:        %08x => [%02x][%1x][%08x] (OK)", $realtime, csrModuleName, data, block, space, address);
    uCONTROL_UART.WaitForIdle();
    uCONTROL_UART.SendEnter();
    TestExpectPrompt();
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
  integer                           foundUnknowns = 0;

  task TestEnumerate();
    logic [15:0] blockType;
    logic [15:0] blockParams;
    logic [31:0] readData;
    int          b, s, i;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Enumerating %0d top blocks", $realtime, blockTopCount);
    $display("%t %m: ******************************************", $realtime);
    for (b=0; b<blockTopCount; b++) begin

      $display("%t %m: ****************************", $realtime);
      $display("%t %m: Reading Block %0d...", $realtime, b);
      CsrRead(b, 0, 32'h0, {blockType, blockParams});

      if (blockType == oclib_pkg::CsrIdChipMon) begin : chipmon
        logic InternalReference;
        logic [11:0] ChipMonType;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: *** Found: Type %04x: CHIPMON #%0d ***", $realtime, blockType, foundChipMons);
        ChipMonType = blockParams[15:4];
        InternalReference = blockParams[0];
        $display("%t %m: Param: InternalReference=%0d", $realtime, InternalReference);
        $display("%t %m: Param: ChipMonType=%0d", $realtime, ChipMonType);
        if (ChipMonType == 0) begin
          $display("%t %m: Type==0 means 'NONE', so skipping further checks", $realtime);
          continue;
        end
        $display("%t %m: Reading temperature (not sure what to expect, hard to predict0", $realtime);
        CsrRead (b, 1, 'h0000, readData); // DRP space
        if (RefClockHz[ClockTop] == 100_000_000) CsrReadCheck (b, 1, 'h0042, 'h1600); // DRP space
        if (RefClockHz[ClockTop] == 156_250_000) CsrReadCheck (b, 1, 'h0042, 'h2200); // DRP space
        CsrReadCheck (b, 1, 'h0050, 'hb834); // DRP space (this is warning temp high, 85c)
        CsrReadCheck (b, 1, 'h0053, 'hcb00); // DRP space (this is error temp high, 95c)
        $display("%t %m: ****************************", $realtime);
        foundChipMons++;
      end

      else if (blockType == oclib_pkg::CsrIdIic) begin : iic
        logic [11:0] OffloadType;
        logic        OffloadEnable;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: *** Found: Type %04x: IIC #%0d ***", $realtime, blockType, foundIics);
        OffloadType = blockParams[15:4];
        OffloadEnable = blockParams[0];
        $display("%t %m: Param: OffloadEnable=%0d", $realtime, OffloadEnable);
        $display("%t %m: Param: OffloadType=%0d", $realtime, OffloadType);
        $display("%t %m: ****************************", $realtime);
        foundIics++;
      end

      else if (blockType == oclib_pkg::CsrIdLed) begin : led
        logic [7:0] NumLeds;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: *** Found: Type %04x: LED #%0d ***", $realtime, blockType, foundLeds);
        NumLeds = blockParams[7:0];
        $display("%t %m: Param: NumLeds=%0d", $realtime, NumLeds);
        CsrRead (b, 0, 'h0004, readData); // Prescale
        $display("%t %m: Csr[4].prescale=%0d, rewriting it to 2...", $realtime, readData);
        CsrWrite(b, 0, 'h0004,    32'd2); // speed up prescale
        $display("%t %m: Reading config for each of %0d LEDs", $realtime, NumLeds);
        if (NumLeds>0) CsrWrite(b, 0, 'h0008, 32'h00003f01); // turn LED 0 on, full brightness
        if (NumLeds>1) CsrWrite(b, 0, 'h000c, 32'h00001f01); // turn LED 1 on, half brightness
        if (NumLeds>2) CsrWrite(b, 0, 'h0010, 32'h00002f03); // turn LED 2 to heartbeat, 3/4 brightness
        #50us; // give time for user to look at the pretty patterns
        $display("%t %m: ****************************", $realtime);
        foundLeds++;
      end

      else if (blockType == oclib_pkg::CsrIdGpio) begin : gpio
        logic [7:0] NumGpios;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: *** Found: Type %04x: GPIO #%0d ***", $realtime, blockType, foundGpios);
        NumGpios = blockParams[7:0];
        $display("%t %m: Param: NumGpios=%0d", $realtime, NumGpios);
        for (i=0; i<NumGpios; i++) begin
          CsrRead(b, 0, 32'h4 + (i*4), readData);
          $display("%t %m: GPIO[%4d]: out=%0d, drive=%d, in=%d", $realtime, i, readData[0], readData[4], readData[8]);
        end
        $display("%t %m: ****************************", $realtime);
        foundGpios++;
      end

      else if (blockType == oclib_pkg::CsrIdFan) begin : fan
        logic [7:0] NumFans;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: *** Found: Type %04x: FAN #%0d ***", $realtime, blockType, foundFans);
        NumFans = blockParams[7:0];
        $display("%t %m: Param: NumFans=%0d", $realtime, NumFans);
        $display("%t %m: ****************************", $realtime);
        foundFans++;
      end

      else if (blockType == oclib_pkg::CsrIdProtect) begin : protect
        logic EnableSkeletonKey;
        logic EnableTimedLicense;
        logic EnableParanoia;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: *** Found: Type %04x: PROTECT #%0d ***", $realtime, blockType, foundProtects);
        EnableSkeletonKey = blockParams[0];
        EnableTimedLicense = blockParams[1];
        EnableParanoia = blockParams[2];
        $display("%t %m: Param: EnableSkeletonKey=%0d", $realtime, EnableSkeletonKey);
        $display("%t %m: Param: EnableTimedLicense=%0d", $realtime, EnableTimedLicense);
        $display("%t %m: Param: EnableParanoia=%0d", $realtime, EnableParanoia);
        $display("%t %m: ****************************", $realtime);
        foundProtects++;
      end

      else if (blockType == oclib_pkg::CsrIdDummy) begin : dummy
        logic [7:0] DatapathCount;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: *** Found: Type %04x: DUMMY #%0d ***", $realtime, blockType, foundDummys);
        DatapathCount = blockParams[7:0];
        $display("%t %m: Param: DatapathCOunt=%0d", $realtime, DatapathCount);
        // OK run the engine for a bit
        CsrWrite(b, 0, 32'h14, 32'h00000000); // once chunk
        CsrWrite(b, 0, 32'h04, 32'h00000001); // go
        readData = 32'h00000000;
        while (readData[31] == 0) begin
          CsrRead(b, 0, 32'h4, readData);
        end
        CsrReadCheck(b, 0, 32'h18, 32'hd1ff271f);
        $display("%t %m: ****************************", $realtime);
        foundDummys++;
      end

      else begin
        $display("%t %m:  ***Found : Type %04x: UNKNOWN #%0d ***", $realtime, blockType, foundUnknowns);
        $display("%t %m: ****************************", $realtime);
        foundUnknowns++;
      end

    end // for (b=0; b<blockTopCount; b++)

  endtask // TestEnumerate

  initial begin
    error = 0;
    $display("%t %m: *****************************", $realtime);
    $display("%t %m: START", $realtime);
    $display("%t %m: *****************************", $realtime);
    `OC_ANNOUNCE_PARAM_INTEGER(Seed);
    `OC_ANNOUNCE_PARAM_INTEGER(EnableUartControl);
    `OC_ANNOUNCE_PARAM_INTEGER(RefClockCount);
    `OC_ANNOUNCE_PARAM_MISC   (RefClockHz);
    `OC_ANNOUNCE_PARAM_INTEGER(ClockTop);
    `OC_ANNOUNCE_PARAM_INTEGER(LedCount);
    `OC_ANNOUNCE_PARAM_INTEGER(UartCount);
    `OC_ANNOUNCE_PARAM_MISC   (UartBaud);
    `OC_ANNOUNCE_PARAM_INTEGER(UartControl);

    TestSanity();
    TestReset();
    TestBlankLines();
    TestSyntaxError();
    TestControlC();
    TestTimers();
    TestInfo();
    TestEnumerate();

    #1ms;
    // #10ms; // for watching the LEDs

    $display("%t %m: *****************************", $realtime);
    if (error) $display("%t %m: TEST FAILED", $realtime);
    else $display("%t %m: TEST PASSED", $realtime);
    $display("%t %m: *****************************", $realtime);
    $finish;
  end


endmodule // oc_cos_test
