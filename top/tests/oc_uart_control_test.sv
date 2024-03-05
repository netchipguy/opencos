
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"
`include "lib/oclib_uart_pkg.sv"

 `define OC_UART_CONTROL_CPU_TREE_TEST

module oc_uart_control_test;

  localparam integer              ClockHz = 156_250_000;
  localparam integer              Baud = 10_000_000;
  localparam realtime             ClockPeriod = (1s/ClockHz);
  localparam realtime             AllowedJitter = (2 * ClockPeriod);
  localparam integer              Verbose = `OC_VAL_ASDEFINED_ELSE(OC_SIM_VERBOSE, 1);

  logic                           clock, reset;

  ocsim_clock #(.ClockHz(ClockHz)) uCLOCK (.clock(clock));
  ocsim_reset uRESET (.clock(clock), .reset(reset));

  oclib_pkg::chip_status_s chipStatus;

  oc_chip_status #(.ClockHz(ClockHz))
  uDUT (.clock(clock), .reset(reset), .chipStatus(chipStatus));

  int                             i;
  logic                           error;

  localparam                      UartErrorWidth = oclib_uart_pkg::ErrorWidth;

  logic                           resetOut;
  logic [UartErrorWidth-1:0]      uartError;
  logic                           uartRx;
  logic                           uartTx;

  ocsim_uart #(.Baud(Baud), .Verbose(Verbose))
  uCONTROL_UART (.rx(uartTx), .tx(uartRx));

  localparam                      type BcType = oclib_pkg::bc_8b_bidi_s;
  BcType                          dutBcIn, dutBcOut;

  localparam logic [0:1] [7:0]    BlockTopCount = 'h1234;
  localparam logic [0:1] [7:0]    BlockUserCount = 'h5678;

   `ifdef OC_UART_CONTROL_CSR_32_NOC
  localparam                      type TopCsrType = oclib_pkg::csr_32_noc_s;
  localparam                      type TopCsrFbType = oclib_pkg::csr_32_noc_fb_s;
   `elsif OC_UART_CONTROL_CSR_32_TREE
  localparam                      type TopCsrType = oclib_pkg::csr_32_tree_s;
  localparam                      type TopCsrFbType = oclib_pkg::csr_32_tree_fb_s;
   `else
  localparam                      type TopCsrType = oclib_pkg::csr_32_s;
  localparam                      type TopCsrFbType = oclib_pkg::csr_32_fb_s;
   `endif

  // this is internal to the block, i.e. we can force it to use async connection UART <> state machine
  localparam                      type UartBcType = oclib_pkg::bc_8b_bidi_s;

  oc_uart_control #(.ClockHz(ClockHz),
                    .Baud(Baud),
                    .BcType(BcType),
                    .BcProtocol(TopCsrType),
                    .UartBcType(UartBcType),
                    .BlockTopCount(BlockTopCount),
                    .BlockUserCount(BlockUserCount),
                    .ResetSync(oclib_pkg::False)
                    )
  uUART_CONTROL (.clock(clock), .reset(reset),
                 .resetOut(resetOut), .uartError(uartError),
                 .uartTx(uartTx), .uartRx(uartRx),
                 .bcIn(dutBcIn), .bcOut(dutBcOut)  );

  // respond to reset request
  always @(posedge resetOut)  uRESET.Reset();

 `ifdef OC_UART_CONTROL_CPU_TREE_TEST

  TopCsrType topCsr;
  TopCsrFbType topCsrFb;

  oclib_csr_adapter #(.CsrInType(oclib_pkg::bc_8b_bidi_s), .CsrInFbType(oclib_pkg::bc_8b_bidi_s),
                      .CsrOutType(TopCsrType), .CsrOutFbType(TopCsrFbType),
                      .CsrIntType(TopCsrType), .CsrIntFbType(TopCsrFbType),
                      .UseClockOut(0)  )
  uCSR_ADAPTER (.clock(clock), .reset(reset),
                .clockOut(), .resetOut(),
                .in(dutBcOut), .inFb(dutBcIn),
                .out(topCsr), .outFb(topCsrFb)  );

  oclib_pkg::csr_32_s csr [1];
  oclib_pkg::csr_32_fb_s csrFb [1];
  logic                           splitterResetRequest;

  oclib_csr_tree_splitter #(.Outputs(1),
                            .CsrInType(TopCsrType), .CsrInFbType(TopCsrFbType),
                            .CsrOutType(oclib_pkg::csr_32_s), .CsrOutFbType(oclib_pkg::csr_32_fb_s) )
  uCSR_SPLITTER (.clock(clock), .reset(reset),
                 .clockOut(), .resetOut(),
                 .resetRequest(splitterResetRequest),
                 .in(topCsr), .inFb(topCsrFb),
                 .out(csr), .outFb(csrFb)  );

  localparam integer              NumCsr = 4;
  localparam integer              DataW = 32;
  logic [0:NumCsr-1] [DataW-1:0]  csrOut;
  logic [0:NumCsr-1] [DataW-1:0]  csrIn;
  logic [0:NumCsr-1]              csrRead;
  logic [0:NumCsr-1]              csrWrite;
  oclib_csr_array #(.NumCsr(NumCsr), //    0              1              2              3   <-- CSR #s
                    .CsrFixedBits( { 32'h0000_0000, 32'h0000_0000, 32'h00ff_0000, 32'hffff_ffff } ),
                    .CsrInitBits ( { 32'h0000_0000, 32'h0000_0000, 32'h0012_abcd, 32'h0000_0000 } ),
                    .CsrRwBits   ( { 32'h0000_0000, 32'hffff_ffff, 32'hf000_ffff, 32'h0000_0000 } ),
                    .CsrRoBits   ( { 32'hffff_ffff, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000 } ),
                    .CsrWoBits   ( { 32'h0000_0000, 32'h0000_0000, 32'h0f00_0000, 32'h0000_0000 } )  )
  uCSR_ARRAY (.clock(clock), .reset(reset), .clockCsrConfig(),
              .csr(csr[0]), .csrFb(csrFb[0]),
              .csrOut(csrOut), .csrIn(csrIn),
              .csrRead(csrRead), .csrWrite(csrWrite)  );

  initial csrIn = '0;

 `else // !  OC_UART_CONTROL_CPU_TREE_TEST

  ocsim_data_source #(.Type(logic [7:0]), .Verbose(Verbose))
  uBC_SOURCE (.clock(clock),
              .outData(dutBcIn.data), .outValid(dutBcIn.valid), .outReady(dutBcOut.ready));

  ocsim_data_sink #(.Type(logic [7:0]), .Verbose(Verbose))
  uBC_SINK (.clock(clock),
            .inData(dutBcOut.data), .inValid(dutBcOut.valid), .inReady(dutBcIn.ready));

 `endif // !  OC_UART_CONTROL_CPU_TREE_TEST

  // The following APIs perform multiple operations to the above, to work on INTs, STRINGs, etc

  logic         txEnterCR = 1;
  logic         txEnterLF = 0;
  logic         rxEnterCR = 1;
  logic         rxEnterLF = 1;

  task ControlSendEnter();
    if (txEnterCR) uCONTROL_UART.Send(8'h0d);
    if (txEnterLF) uCONTROL_UART.Send(8'h0a);
  endtask // ControlSendEnter

  task ControlExpectString ( input string s );
    for (int i=0; i<s.len(); i++) uCONTROL_UART.Expect(s[i]);
  endtask // ControlExpectRxByte

  task ControlReceiveEnter();
    if (rxEnterCR) uCONTROL_UART.ReceiveCheck(8'h0d);
    if (rxEnterLF) uCONTROL_UART.ReceiveCheck(8'h0a);
  endtask // ControlReceiveEnter

  task ControlSendInt ( input [63:0] v, input binaryMode = 0, input integer len );
    int c;
    bit done;
    c = '0;
    done = 0;
    while (!done) begin
        if (binaryMode) begin
          uCONTROL_UART.Send((v >> (8*(len-1-c))) & 8'hff);
          if (c++ >= (len-1)) done = 1;
        end
        else begin
          uCONTROL_UART.Send(oclib_pkg::HexToAsciiNibble(v >> (4*((len*2)-1-c))) & 8'hf);
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
      uCONTROL_UART.Receive(temp8, maxNS/4);
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



  // TESTS

  task TestExpectBanner();
    uCONTROL_UART.Expect(8'h0d);
    uCONTROL_UART.Expect(8'h0a);
    ControlExpectString("* OPENCOS *");
    TestExpectPrompt();
  endtask // TestExpectBanner

  task TestExpectError();
    uCONTROL_UART.Expect(8'h0d);
    uCONTROL_UART.Expect(8'h0a);
    ControlExpectString("ERROR");
    TestExpectPrompt();
  endtask // TestExpectError

  task TestExpectPrompt();
    uCONTROL_UART.Expect(8'h0d);
    uCONTROL_UART.Expect(8'h0a);
    ControlExpectString("OC>");
    uCONTROL_UART.WaitForIdle();
  endtask // TestExpectPrompt

  task TestExpectIdle();
    repeat (50) uCONTROL_UART.WaitBit();
    `OC_ASSERT(uCONTROL_UART.rxQ.size() == 0);
  endtask // TestExpectIdle

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
      ControlSendEnter();
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
    ControlSendEnter();
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
    uCONTROL_UART.Send("T");
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
    uCONTROL_UART.Send("i");
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
    $display("%t %m: BuildTime          :   %02x:%02x", $realtime, temp32[31:24], temp32[23:16]);
    $display("%t %m: TargetVendor       :     %04x", $realtime, temp32[15:0]);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: TargetLibrary      :     %04x", $realtime, temp32[31:16]);
    $display("%t %m: TargetBoard        :     %04x", $realtime, temp32[15:0]);
    ControlReceiveEnter();
    ControlReceiveInt32(temp32);
    $display("%t %m: BlockTopCount      :     %04x", $realtime, temp32[31:16]);
    $display("%t %m: BlockUserCount     :     %04x", $realtime, temp32[15:0]);
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

 `ifdef OC_UART_CONTROL_CPU_TREE_TEST

  string csrModuleName;
  initial csrModuleName = $sformatf("%m.CSR");

  task CsrReadCheck(input [31:0] address, input [31:0] data);

    TopCsrType csr;
    TopCsrFbType csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %s: Expect %08x <= [%08x]", $realtime, csrModuleName, data, address);
    csr = '0;
    csr.read = 1;
    csr.address = address;
    csr.wdata = '0;
    payloadRequest = csr;
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uCONTROL_UART.Send(payloadRequest[i]);
    uCONTROL_UART.ReceiveCheck(ResponseBytes+1);
    csrFb = '0;
    csrFb.ready = 1;
    csrFb.error = 0;
    csrFb.rdata = data;
    payloadResponse = csrFb;
    for (int i=0; i<ResponseBytes; i++) uCONTROL_UART.ReceiveCheck(payloadResponse[i]);
    $display("%t %s:        %08x <= [%08x] (OK, Match)", $realtime, csrModuleName, data, address);
    uCONTROL_UART.WaitForIdle();
    ControlSendEnter();
    TestExpectPrompt();
  endtask

  task CsrWrite(input [31:0] address, input [31:0] data);

    TopCsrType csr;
    TopCsrFbType csrFb;
    localparam int RequestBytes = (($bits(csr)+7)/8);
    localparam int ResponseBytes = (($bits(csrFb)+7)/8);
    logic [0:RequestBytes-1] [7:0] payloadRequest;
    logic [0:ResponseBytes-1] [7:0] payloadResponse;

    $display("%t %s: Write  %08x => [%08x]", $realtime, csrModuleName, data, address);
    csr = '0;
    csr.write = 1;
    csr.address = address;
    csr.wdata = data;
    payloadRequest = csr;
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uCONTROL_UART.Send(payloadRequest[i]);
    uCONTROL_UART.ReceiveCheck(ResponseBytes+1);
    csrFb = '0;
    csrFb.ready = 1;
    csrFb.error = 0;
    csrFb.rdata = '0;
    payloadResponse = csrFb;
    for (int i=0; i<ResponseBytes; i++) uCONTROL_UART.ReceiveCheck(payloadResponse[i]);
    $display("%t %s:        %08x => [%08x] (OK)", $realtime, csrModuleName, data, address);
    uCONTROL_UART.WaitForIdle();
    ControlSendEnter();
    TestExpectPrompt();
  endtask

  task TestCsr();
    logic [31:0] temp32;
    int          i;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: TestCsr", $realtime);
    $display("%t %m: Creating a BC message", $realtime);
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: ** BINARY Mode **", $realtime);

    // play with CSR 0
    CsrReadCheck(.address('h0000), .data('h0000_0000));
    CsrWrite    (.address('h0000), .data('h1234_5678));
    csrIn[0] = 'h55aa_1234;
    CsrReadCheck(.address('h0000), .data('h55aa1234));

    // play with CSR 1
    CsrReadCheck(.address('h0004), .data('h0000_0000));
    csrIn[1] = 'h55aa_1234;
    CsrWrite    (.address('h0004), .data('h8765_4321));
    CsrReadCheck(.address('h0004), .data('h8765_4321));

    // play with CSR 2
    CsrReadCheck(.address('h0008), .data('h0012_abcd));
    CsrWrite    (.address('h0008), .data('h1234_5678));
    CsrReadCheck(.address('h0008), .data('h1012_5678));
    `OC_ASSERT(csrOut[2][27:24] == 4'h2); // write-only bits in second nibble from left

    TestExpectIdle();
  endtask // TestMessage
 `else
  task TestMessage();
    logic [31:0] temp32;
    int          i;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: TestMessage", $realtime);
    $display("%t %m: Creating a BC message", $realtime);
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: ** BINARY Mode **", $realtime);
    uBC_SINK.Start();
    uBC_SINK.Expect(8'h09); // Length: 9
    for (int i=0; i<8; i++) uBC_SINK.Expect(i + 1);
    uCONTROL_UART.Send("B");
    uCONTROL_UART.Send(8'h09); // Length: 9
    for (int i=0; i<8; i++) uCONTROL_UART.Send(i + 1);
    #1us;
    uCONTROL_UART.Expect(8'h06); // Length: 6
    for (int i=0; i<6; i++) uCONTROL_UART.Expect(i + 10);
    uBC_SOURCE.Send(8'h06); // Length: 6
    for (int i=0; i<6; i++) uBC_SOURCE.Send(i + 10);
    #1us;
    ControlSendEnter();
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestMessage
 `endif

  initial begin
    error = 0;
    $display("%t %m: *****************************", $realtime);
    $display("%t %m: START", $realtime);
    $display("%t %m: *****************************", $realtime);
    `OC_ANNOUNCE_PARAM_INTEGER(ClockHz);
    `OC_ANNOUNCE_PARAM_REALTIME(ClockPeriod);
    `OC_ANNOUNCE_PARAM_REALTIME(AllowedJitter);
    `OC_ANNOUNCE_PARAM_REALTIME(Baud);

    $display("%t %m: Expect to receive prompt", $realtime);
    TestExpectBanner();

    $display("%t %m: Check that it stays idle", $realtime);
    TestExpectIdle();

    TestReset();
    TestBlankLines();
    TestSyntaxError();
    TestControlC();
    TestTimers();
    TestInfo();
 `ifdef OC_UART_CONTROL_CPU_TREE_TEST
    TestCsr();
 `else
    TestMessage();
 `endif

    $display("%t %m: *****************************", $realtime);
    if (error) $display("%t %m: TEST FAILED", $realtime);
    else $display("%t %m: TEST PASSED", $realtime);
    $display("%t %m: *****************************", $realtime);
    $finish;
  end

endmodule // oc_uart_control_test
