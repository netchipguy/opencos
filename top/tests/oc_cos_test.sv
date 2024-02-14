
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
    parameter integer Seed = 0,
    parameter bit     EnableUartControl = 1,

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
    parameter integer UartBaud [0:UartCountSafe-1] = {10_000_000, 115200},
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
   // *** RESET ***
  logic                         hardReset;
   // *** LED ***
  logic [LedCountSafe-1:0]      ledOut;
   // *** UART ***
  logic [UartCountSafe-1:0]     uartRx;
  logic [UartCountSafe-1:0]     uartTx;


  integer                           blockTopCount = 0;
  integer                           blockUserCount = 0;


  for (genvar i=0; i<RefClockCount; i++) begin
    ocsim_clock #(.ClockHz(RefClockHz[i])) uCLOCK (.clock(clockRef[i]));
  end
  ocsim_reset uHARD_RESET (.clock(clockRef[0]), .reset(hardReset));

  ocsim_uart #(.Baud(UartBaud[UartControl]), .Verbose(Verbose))
  uCONTROL_UART (.rx(uartTx[0]), .tx(uartRx[0]));

  oc_cos #(.Seed(Seed),
           .EnableUartControl(EnableUartControl),
           .RefClockCount(RefClockCount),
           .RefClockHz(RefClockHz),
           .ClockTop(ClockTop),
           .LedCount(LedCount),
           .UartCount(UartCount),
           .UartBaud(UartBaud),
           .UartControl(UartControl),
           .CsrTopType(CsrTopType),
           .CsrTopFbType(CsrTopFbType))
  uDUT (
        .clockRef(clockRef),
        .hardReset(hardReset),
        .ledOut(ledOut),
        .uartRx(uartRx),
        .uartTx(uartTx) );

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
    $display("%t %m: BuildTime          :   %02x:%02x", $realtime, temp32[31:24], temp32[23:16]);
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

  task CsrRead(input [oclib_pkg::BlockIdBits-1:0] block, input [31:0] address, output logic [31:0] data);
    CsrTopProtocol csr;
    CsrTopFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %m: *** Reading [%08x] => ...", $realtime, address);
    csr = '0;
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
    `OC_ASSERT(csrFb.ready == 1);
    `OC_ASSERT(csrFb.error == 0);
    data = csrFb.rdata;
    $display("%t %m: *** Read    [%08x] => %08x", $realtime, address, data);
    uCONTROL_UART.WaitForIdle();
    uCONTROL_UART.SendEnter();
    TestExpectPrompt();
  endtask

  task CsrReadCheck(input [oclib_pkg::BlockIdBits-1:0] block, input [31:0] address, input [31:0] data,
                    input ready = 1, input error = 0);
    CsrTopProtocol csr;
    CsrTopFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %m: *** Expecting [%08x] => %08x", $realtime, address, data);
    csr = '0;
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
    `OC_ASSERT(csrFb.ready == ready);
    `OC_ASSERT(csrFb.error == error);
    `OC_ASSERT(csrFb.rdata == data);
    uCONTROL_UART.WaitForIdle();
    uCONTROL_UART.SendEnter();
    TestExpectPrompt();
  endtask

  task CsrWrite(input [oclib_pkg::BlockIdBits-1:0] block, input [31:0] address, input [31:0] data);
    CsrTopProtocol csr;
    CsrTopFbProtocol csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %m: *** Writing   [%08x] <= %08x", $realtime, address, data);
    csr = '0;
    csr.write = 1;
    csr.address = address;
    csr.wdata = data;
    payloadRequest = csr;
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uCONTROL_UART.Send(payloadRequest[i]);
    uCONTROL_UART.ReceiveCheck(ResponseBytes+1);
    for (int i=0; i<ResponseBytes; i++) uCONTROL_UART.Receive(payloadResponse[i]);
    csrFb = payloadResponse;
    `OC_ASSERT(csrFb.ready == 1);
    `OC_ASSERT(csrFb.error == 0);
    `OC_ASSERT(csrFb.rdata == 0);
    uCONTROL_UART.WaitForIdle();
    uCONTROL_UART.SendEnter();
    TestExpectPrompt();
  endtask

  integer                           foundPlls = 0;
  integer                           foundChipmons = 0;
  integer                           foundProtects = 0;
  integer                           foundIics = 0;
  integer                           foundLeds = 0;
  integer                           foundGpios = 0;
  integer                           foundHbms = 0;
  integer                           foundCmacs = 0;
  integer                           foundUnknowns = 0;

  task TestEnumerate();
    logic [15:0] blockType;
    logic [15:0] blockParams;
    logic [31:0] readData;
    int          b, i;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Enumerating %0d top blocks", $realtime, blockTopCount);
    $display("%t %m: ******************************************", $realtime);
    for (b=0; b<blockTopCount; b++) begin
      CsrRead(b, 32'h0, {blockType, blockParams});
      if (0) begin
      end
      else if (blockType == oclib_pkg::CsrIdLed) begin : led
        logic [7:0] NumLeds;
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: Block %0d: Type %04x: LED #%0d", $realtime, b, blockType, foundLeds);
        $display("%t %m: ****************************", $realtime);
        CsrRead (b, 'h0004, readData); // Prescale
        CsrWrite(b, 'h0004,    32'd2); // speed up prescale
        NumLeds = blockParams[7:0];
        $display("%t %m: Param: NumLeds=%0d", $realtime, NumLeds);
        if (NumLeds>0) CsrWrite(b, 'h0008, 32'h00003f01); // turn LED 0 on, full brightness
        if (NumLeds>1) CsrWrite(b, 'h000c, 32'h00001f01); // turn LED 1 on, half brightness
        if (NumLeds>2) CsrWrite(b, 'h0010, 32'h00002f03); // turn LED 2 to heartbeat, 3/4 brightness
        #50us; // give time for user to look at the pretty patterns
        foundLeds++;
      end
      else begin
        $display("%t %m: ****************************", $realtime);
        $display("%t %m: Block %0d : Type %04x: UNKNOWN #%0d", $realtime, b, blockType, foundUnknowns);
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

    #10ms;

    $display("%t %m: *****************************", $realtime);
    if (error) $display("%t %m: TEST FAILED", $realtime);
    else $display("%t %m: TEST PASSED", $realtime);
    $display("%t %m: *****************************", $realtime);
    $finish;
  end


endmodule // oc_cos_test
