
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"
`include "lib/oclib_uart_pkg.sv"

 `define OC_UART_CONTROL_CPU_TREE_TEST

module oc_uart_control_test;

  localparam integer ClockHz = 156_250_000;
  localparam integer Baud = 10_000_000;
  localparam realtime ClockPeriod = (1s/ClockHz);
  localparam realtime AllowedJitter = (2 * ClockPeriod);
  parameter integer   Verbose = `OC_VAL_ASDEFINED_ELSE(OC_SIM_VERBOSE, 1);

  logic clock, reset;

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
  uSIM_UART (.rx(uartTx), .tx(uartRx));

  oclib_pkg::bc_8b_bidi_s dutBcIn, dutBcOut;

 `ifdef OC_UART_CONTROL_CPU_TREE_TEST

  localparam                      type CsrTopType = oclib_pkg::csr_32_noc_s;
  localparam                      type CsrTopFbType = oclib_pkg::csr_32_noc_fb_s;

  CsrTopType csrTop;
  CsrTopFbType csrTopFb;

  oclib_csr_adapter #(.CsrInType(oclib_pkg::bc_8b_bidi_s), .CsrInFbType(oclib_pkg::bc_8b_bidi_s),
                      .CsrOutType(CsrTopType), .CsrOutFbType(CsrTopFbType),
                      .CsrIntType(CsrTopType), .CsrIntFbType(CsrTopFbType),
                      .UseClockOut(0)  )
  uCSR_ADAPTER (.clock(clock), .reset(reset),
                .clockOut(), .resetOut(),
                .csrSelect(1'b1),
                .in(dutBcOut), .inFb(dutBcIn),
                .out(csrTop), .outFb(csrTopFb)  );

  oclib_pkg::csr_32_s csr [1];
  oclib_pkg::csr_32_fb_s csrFb [1];

  oclib_csr_tree_splitter #(.Outputs(1),
                            .CsrInType(CsrTopType), .CsrInFbType(CsrTopFbType),
                            .CsrOutType(oclib_pkg::csr_32_s), .CsrOutFbType(oclib_pkg::csr_32_fb_s) )
  uCSR_SPLITTER (.clock(clock), .reset(reset),
                 .clockOut(), .resetOut(),
                 .csrSelect(1'b1),
                 .resetRequest(),
                 .in(csrTop), .inFb(csrTopFb),
                 .out(csr), .outFb(csrFb)  );

  localparam integer              NumCsr = 4;
  localparam integer              DataW = 32;
  logic [0:NumCsr-1] [DataW-1:0]  csrConfig;
  logic [0:NumCsr-1] [DataW-1:0]  csrStatus;
  logic [0:NumCsr-1]              csrRead;
  logic [0:NumCsr-1]              csrWrite;
  oclib_csr_array #(.NumCsr(NumCsr), //    0              1              2              3   <-- CSR #s
                    .CsrFixedBits( { 32'h0000_0000, 32'h0000_0000, 32'h00ff_0000, 32'hffff_ffff } ),
                    .CsrInitBits ( { 32'h0000_0000, 32'h0000_0000, 32'h0012_abcd, 32'h0000_0000 } ),
                    .CsrRwBits   ( { 32'h0000_0000, 32'hffff_ffff, 32'hf000_ffff, 32'h0000_0000 } ),
                    .CsrRoBits   ( { 32'hffff_ffff, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000 } ),
                    .CsrWoBits   ( { 32'h0000_0000, 32'h0000_0000, 32'h0f00_0000, 32'h0000_0000 } )  )
  uCSR_ARRAY (.clock(clock), .reset(reset), .clockCsrConfig(),
              .csr(csr[0]), .csrFb(csrFb[0]), .csrSelect(1'b1),
              .csrConfig(csrConfig), .csrStatus(csrStatus),
              .csrRead(csrRead), .csrWrite(csrWrite)  );

  initial csrStatus = '0;

 `else // !  OC_UART_CONTROL_CPU_TREE_TEST

  ocsim_data_source #(.Type(logic [7:0]), .Verbose(Verbose))
  uBC_SOURCE (.clock(clock),
              .outData(dutBcIn.data), .outValid(dutBcIn.valid), .outReady(dutBcOut.ready));

  ocsim_data_sink #(.Type(logic [7:0]), .Verbose(Verbose))
  uBC_SINK (.clock(clock),
            .inData(dutBcOut.data), .inValid(dutBcOut.valid), .inReady(dutBcIn.ready));

 `endif // !  OC_UART_CONTROL_CPU_TREE_TEST

  oc_uart_control #(.ClockHz(ClockHz), .Baud(Baud))
  uUART_CONTROL (.clock(clock), .reset(reset),
                 .resetOut(resetOut), .uartError(uartError),
                 .uartTx(uartTx), .uartRx(uartRx),
                 .bcIn(dutBcIn), .bcOut(dutBcOut)  );

  always @(posedge resetOut) begin
    uRESET.Reset();
  end

  task TestExpectBanner();
    uSIM_UART.Expect(8'h0d);
    uSIM_UART.Expect(8'h0a);
    uSIM_UART.ExpectString("* OPENCOS *");
    TestExpectPrompt();
  endtask // TestExpectBanner

  task TestExpectError();
    uSIM_UART.Expect(8'h0d);
    uSIM_UART.Expect(8'h0a);
    uSIM_UART.ExpectString("ERROR");
    TestExpectPrompt();
  endtask // TestExpectError

  task TestExpectPrompt();
    uSIM_UART.Expect(8'h0d);
    uSIM_UART.Expect(8'h0a);
    uSIM_UART.ExpectString("OC>");
    uSIM_UART.WaitForIdle();
  endtask // TestExpectPrompt

  task TestExpectIdle();
    repeat (50) uSIM_UART.WaitBit();
    `OC_ASSERT(uSIM_UART.rxQ.size() == 0);
  endtask // TestExpectIdle

  task TestReset();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 64x'~' to reset the DUT", $realtime);
    $display("%t %m: ******************************************", $realtime);
    for (int i=0; i<64; i++) begin
      uSIM_UART.Send("~");
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
      uSIM_UART.SendEnter();
      TestExpectPrompt();
      TestExpectIdle();
   end
  endtask

  task TestSyntaxError();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 'ABC' syntax error to the DUT", $realtime);
    $display("%t %m: ******************************************", $realtime);
    uSIM_UART.Send("A");
    uSIM_UART.Send("B");
    uSIM_UART.Send("C");
    $display("%t %m: Checking there's no response yet", $realtime);
    TestExpectIdle();
    $display("%t %m: Sending '<Enter>'", $realtime);
    uSIM_UART.SendEnter();
    TestExpectError();
    TestExpectIdle();
  endtask // TestSyntaxError

  task TestControlC();
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Sending 'ABC' then <Ctrl-C> to avoid error", $realtime);
    $display("%t %m: ******************************************", $realtime);
    uSIM_UART.Send("A");
    uSIM_UART.Send("B");
    uSIM_UART.Send("C");
    $display("%t %m: Checking there's no response yet", $realtime);
    TestExpectIdle();
    $display("%t %m: Sending '<Ctrl-C>'", $realtime);
    uSIM_UART.Send(8'h03);
    uSIM_UART.Expect("^");
    uSIM_UART.Expect("C");
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestControlC

  task TestTimers();
    logic [31:0] temp32;
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: Requesting Timers", $realtime);
    $display("%t %m: ******************************************", $realtime);
    $display("%t %m: ** ASCII Mode **", $realtime);
    uSIM_UART.Send("t");
    uSIM_UART.SendEnter();
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: Uptime since reload: %08x", $realtime, temp32);
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: Uptime since reset : %08x", $realtime, temp32);
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: Cycles since reset : %08x", $realtime, temp32);
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: Cycles under reset : %08x", $realtime, temp32);
    TestExpectPrompt();
    TestExpectIdle();
    $display("%t %m: ** BINARY Mode **", $realtime);
    uSIM_UART.Send("T");
    uSIM_UART.SendEnter();
    uSIM_UART.ReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Uptime since reload: %08x", $realtime, temp32);
    uSIM_UART.ReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Uptime since reset : %08x", $realtime, temp32);
    uSIM_UART.ReceiveInt32(temp32, .binaryMode(1));
    $display("%t %m: Cycles since reset : %08x", $realtime, temp32);
    uSIM_UART.ReceiveInt32(temp32, .binaryMode(1));
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
    uSIM_UART.Send("i");
    uSIM_UART.SendEnter();
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: InfoVersion        :       %02x", $realtime, temp32[31:24]);
    $display("%t %m: BcCount            :       %02x", $realtime, temp32[23:16]);
    $display("%t %m: BuilderID          :     %04x", $realtime, temp32[15:0]);
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: BitstreamID        : %08x", $realtime, temp32);
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: BuildDate          : %08x", $realtime, temp32);
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: BuildTime          :   %02x:%02x", $realtime, temp32[31:24], temp32[23:16]);
    $display("%t %m: TargetVendor       :       %02x", $realtime, temp32[15:0]);
    uSIM_UART.ReceiveEnter();
    uSIM_UART.ReceiveInt32(temp32);
    $display("%t %m: TargetLibrary      :       %02x", $realtime, temp32[31:16]);
    $display("%t %m: TargetBoard        :       %02x", $realtime, temp32[15:0]);
    for (i=0; i<3; i++) begin
      uSIM_UART.ReceiveEnter();
      uSIM_UART.ReceiveInt32(temp32);
    end
    for (i=0; i<4; i++) begin
      uSIM_UART.ReceiveEnter();
      uSIM_UART.ReceiveInt32(temp32);
      $display("%t %m: UserSpace%1x         : %08x", $realtime, i, temp32);
    end
    for (i=0; i<4; i++) begin
      uSIM_UART.ReceiveEnter();
      uSIM_UART.ReceiveInt32(temp32);
      $display("%t %m: BuildUUID%1x         : %08x", $realtime, i, temp32);
    end
    TestExpectPrompt();
    TestExpectIdle();
  endtask // TestInfo

 `ifdef OC_UART_CONTROL_CPU_TREE_TEST

  task CsrReadCheck(input [31:0] address, input [31:0] data);

    CsrTopType csr;
    CsrTopFbType csrFb;
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
    uSIM_UART.Send("B");
    uSIM_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uSIM_UART.Send(payloadRequest[i]);
    uSIM_UART.ReceiveCheck(ResponseBytes+1);
    csrFb = '0;
    csrFb.ready = 1;
    csrFb.error = 0;
    csrFb.rdata = data;
    payloadResponse = csrFb;
    for (int i=0; i<ResponseBytes; i++) uSIM_UART.ReceiveCheck(payloadResponse[i]);
    uSIM_UART.WaitForIdle();
    uSIM_UART.SendEnter();
    TestExpectPrompt();
  endtask

  task CsrWrite(input [31:0] address, input [31:0] data);

    CsrTopType csr;
    CsrTopFbType csrFb;
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
    uSIM_UART.Send("B");
    uSIM_UART.Send(RequestBytes+1); // Length (1 extra for length byte itself)
    for (int i=0; i<RequestBytes; i++) uSIM_UART.Send(payloadRequest[i]);
    uSIM_UART.ReceiveCheck(ResponseBytes+1);
    csrFb = '0;
    csrFb.ready = 1;
    csrFb.error = 0;
    csrFb.rdata = '0;
    payloadResponse = csrFb;
    for (int i=0; i<ResponseBytes; i++) uSIM_UART.ReceiveCheck(payloadResponse[i]);
    uSIM_UART.WaitForIdle();
    uSIM_UART.SendEnter();
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
    csrStatus[0] = 'h55aa_1234;
    CsrReadCheck(.address('h0000), .data('h55aa1234));

    // play with CSR 1
    CsrReadCheck(.address('h0004), .data('h0000_0000));
    csrStatus[1] = 'h55aa_1234;
    CsrWrite    (.address('h0004), .data('h8765_4321));
    CsrReadCheck(.address('h0004), .data('h8765_4321));

    // play with CSR 2
    CsrReadCheck(.address('h0008), .data('h0012_abcd));
    CsrWrite    (.address('h0008), .data('h1234_5678));
    CsrReadCheck(.address('h0008), .data('h1012_5678));
    `OC_ASSERT(csrConfig[2][27:24] == 4'h2); // write-only bits in second nibble from left

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
    uSIM_UART.Send("B");
    uSIM_UART.Send(8'h09); // Length: 9
    for (int i=0; i<8; i++) uSIM_UART.Send(i + 1);
    #1us;
    uSIM_UART.Expect(8'h06); // Length: 6
    for (int i=0; i<6; i++) uSIM_UART.Expect(i + 10);
    uBC_SOURCE.Send(8'h06); // Length: 6
    for (int i=0; i<6; i++) uBC_SOURCE.Send(i + 10);
    #1us;
    uSIM_UART.SendEnter();
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
