
// SPDX-License-Identifier: MPL-2.0

`include "sim/ocsim_pkg.sv"
`include "lib/oclib_pkg.sv"

module ocsim_uart
  #(
    parameter integer Baud = 115200,
    parameter integer Verbose = 1
    )
  (
   input        rx,
   output logic tx
   );

  logic [7:0]   rxQ [$];
  logic [7:0]   expectQ [$];
  logic         txEnterCR;
  logic         txEnterLF;
  logic         rxEnterCR;
  logic         rxEnterLF;

  initial begin
    tx = 1'b1;
    txEnterCR = 1'b1;
    txEnterLF = 1'b0;
    rxEnterCR = 1'b1;
    rxEnterLF = 1'b1;
  end

  task WaitBit ( input half = 0 );
    if (half) #(1s / (Baud*2));
    else      #(1s / Baud);
  endtask // WaitBit

  task Send ( input [7:0] b );
    if (Verbose) $display("%t %m: Sending Byte: %02x (%s)", $realtime, b, ocsim_pkg::CharToString(b));
    tx = 1'b0;
    WaitBit();
    for (int i=0; i<8; i++) begin
      tx = b[i];
      WaitBit();
    end
    tx = 1'b1;
    WaitBit();
  endtask // Send

  task SendEnter();
    if (txEnterCR) Send(8'h0d);
    if (txEnterLF) Send(8'h0a);
  endtask

  task SendString ( input string s );
    for (int i=0; i<s.len(); i++) Send(s[i]);
  endtask // SendString

  task Sendmultiple ( input [7:0] b [$] );
    if (Verbose) $display("%t %m: Sending %0d Bytes...", $realtime, b.size());
    for (int i=0; i<b.size(); i++) Send(b[i]);
  endtask // SendMultiple

  task Expect ( input [7:0] b );
    expectQ.push_back(b);
    if (Verbose) $display("%t %m: Expecting Byte: %02x (%s)", $realtime, b, ocsim_pkg::CharToString(b));
  endtask // Expect

  task ExpectEnter();
    if (rxEnterCR) Expect(8'h0d);
    if (rxEnterLF) Expect(8'h0a);
  endtask

  task ExpectString ( input string s );
    for (int i=0; i<s.len(); i++) Expect(s[i]);
  endtask // ExpectRxByte

  task ExpectMultiple ( input [7:0] b [$] );
    if (Verbose) $display("%t %m: Expecting %0d Bytes...", $realtime, b.size());
    for (int i=0; i<b.size(); i++) Expect(b[i]);
  endtask // ExpectMultiple

  task Receive ( output logic [7:0] b, input integer maxNS = 1000000 );
    int i;
    bit done;
    i = '0;
    done = 0;
    while (!done) begin
      if (rxQ.size()) begin
        b = rxQ.pop_front();
        done = 1;
      end
      else #1ns;
      if (i++ >= maxNS) `OC_ERROR($sformatf("Didn't get byte after waiting %0dns!", maxNS));
    end
  endtask // Receive

  task ReceiveCheck ( input [7:0] v, input integer maxNS = 1000000 );
    logic [7:0] b;
    Receive(b, maxNS);
    if (b !== v) `OC_ERROR($sformatf("Received 0x%02x when expecting 0x%02x!", b, v));
  endtask // ReceiveCheck

  task ReceiveEnter();
    if (rxEnterCR) ReceiveCheck(8'h0d);
    if (rxEnterLF) ReceiveCheck(8'h0a);
  endtask // ReceiveEnter

  // ReceiveInt tasks leverage the Byte oriented tasks above to send/receive values in binary
  // or ascii (hex) format.

  task SendInt8 ( input [7:0] v, input binaryMode = 0 );
    SendInt({'0,v}, binaryMode, 1);
  endtask

  task SendInt16 ( input [15:0] v, input binaryMode = 0 );
    SendInt({'0,v}, binaryMode, 2);
  endtask

  task SendInt32 ( input [31:0] v, input binaryMode = 0 );
    SendInt({'0,v}, binaryMode, 4);
  endtask

  task SendInt64 ( input [63:0] v, input binaryMode = 0 );
    SendInt(v, binaryMode, 8);
  endtask

  task SendInt ( input [63:0] v, input binaryMode = 0, input integer len );
    int c;
    bit done;
    c = '0;
    done = 0;
    while (!done) begin
        if (binaryMode) begin
          Send((v >> (8*(len-1-c))) & 8'hff);
          if (c++ >= (len-1)) done = 1;
        end
        else begin
          Send(oclib_pkg::HexToAsciiNibble(v >> (4*((len*2)-1-c))) & 8'hf);
          if (c++ >= ((2*len)-1)) done = 1;
        end
    end
  endtask // SendInt

  task ReceiveInt8 ( output [7:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    logic [63:0] o;
    ReceiveInt( o, maxNS, binaryMode, 1);
    v = o[7:0];
  endtask

  task ReceiveInt16 ( output [15:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    logic [63:0] o;
    ReceiveInt( o, maxNS, binaryMode, 2);
    v = o[15:0];
  endtask

  task ReceiveInt32 ( output [31:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    logic [63:0] o;
    ReceiveInt( o, maxNS, binaryMode, 4);
    v = o[31:0];
  endtask

  task ReceiveInt64 ( output [63:0] v, input integer maxNS = 1000000, input binaryMode = 0 );
    ReceiveInt( v, maxNS, binaryMode, 8);
  endtask

  task ReceiveInt ( output [63:0] v, input integer maxNS = 1000000, input binaryMode = 0, input integer len );
    int i;
    int c;
    bit done;
    logic [63:0] temp64;
    i = '0;
    c = '0;
    done = 0;
    temp64 = 'X;
    while (!done) begin
      if (rxQ.size()) begin
        if (binaryMode) begin
          temp64 = { temp64[55:0], rxQ.pop_front() };
          if (c++ >= (len-1)) done = 1;
        end
        else begin
          temp64 = { temp64[59:0], oclib_pkg::AsciiToHexNibble(rxQ.pop_front()) };
          if (c++ >= ((2*len)-1)) done = 1;
        end
        if (done) v = temp64;
      end
      else #1ns;
      if (i++ >= maxNS) `OC_ERROR($sformatf("Didn't get byte after waiting %0dns!", maxNS));
    end
  endtask // ReceiveInt

  task WaitForIdle( integer maxNS = 1000000 );
    int i;
    $display("%t %m: Waiting for expectQ to empty (%0dns max)", $realtime, maxNS);
    while (expectQ.size() && (i < maxNS)) begin
      #1ns;
      i=i+1;
    end
    if (expectQ.size()) begin
      `OC_ERROR($sformatf("expectQ still has %0d entries after waiting %0dns!", expectQ.size(), maxNS));
    end
    else begin
      $display("%t %m: expectQ is empty (waited %0dns)", $realtime, i);
    end
  endtask // WaitForIdle

  logic [7:0] b;
  initial begin
    #10ns;
    while (1) begin
      @(negedge rx);
      WaitBit(.half(1));
      `OC_ASSERT(rx == 1'b0); // samples start bit
      for (int i=0; i<8; i++) begin
        WaitBit();
        b[i] = rx;
      end
      WaitBit();
      `OC_ASSERT(rx == 1'b1); // samples stop bit
      rxQ.push_back(b);
      if (Verbose) $display("%t %m: Received Byte:    %02x (%s)", $realtime, b, ocsim_pkg::CharToString(b));
    end
  end

  always begin
    if (rxQ.size() && expectQ.size()) begin
      if (rxQ[0] === expectQ[0]) begin
        if (Verbose) $display("%t %m: Matched expected: %02x (%s)", $realtime, rxQ[0], ocsim_pkg::CharToString(rxQ[0]));
        rxQ.pop_front();
        expectQ.pop_front();
      end
      else begin
        $display("%t %m: ERROR: Received byte: %02x (%s) when expecting: %02x (%s)", $realtime,
                 rxQ[0], ocsim_pkg::CharToString(rxQ[0]), expectQ[0], ocsim_pkg::CharToString(expectQ[0]));
        $finish;
      end
    end
    #10ns;
  end

  endmodule
