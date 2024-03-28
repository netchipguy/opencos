
// SPDX-License-Identifier: MPL-2.0

`include "sim/ocsim_pkg.sv"
`include "lib/oclib_pkg.sv"

module ocsim_uart
  #(
    parameter integer Baud = 115200,
    parameter integer Verbose = oclib_pkg::False
    )
  (
   input        rx,
   output logic tx
   );

  logic [7:0]   rxQ [$];
  logic [7:0]   expectQ [$];

  initial begin
    tx = 1'b1;
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

  task Expect ( input [7:0] b );
    expectQ.push_back(b);
    if (Verbose) $display("%t %m: Expecting Byte: %02x (%s)", $realtime, b, ocsim_pkg::CharToString(b));
  endtask // Expect

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

  task WaitForIdle( integer maxNS = 1000000 );
    int i;
    if (Verbose) $display("%t %m: Waiting for expectQ to empty (%0dns max)", $realtime, maxNS);
    while (expectQ.size() && (i < maxNS)) begin
      #1ns;
      i=i+1;
    end
    if (expectQ.size()) begin
      `OC_ERROR($sformatf("expectQ still has %0d entries after waiting %0dns!", expectQ.size(), maxNS));
    end
    else begin
      if (Verbose) $display("%t %m: expectQ is empty (waited %0dns)", $realtime, i);
    end
  endtask // WaitForIdle

  task ExpectIdle( integer NS = 1000 );
    if (Verbose) $display("%t %m: Checking idle for %0dns", $realtime, NS);
    repeat (NS) begin
      #1ns;
      `OC_ASSERT(expectQ.size() == 0);
    end
    if (Verbose) $display("%t %m: Confirmed idle for %0dns", $realtime, NS);
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

  logic [7:0] temp8;
  always begin
    if (rxQ.size() && expectQ.size()) begin
      if (rxQ[0] === expectQ[0]) begin
        if (Verbose) $display("%t %m: Matched expected: %02x (%s)", $realtime, rxQ[0], ocsim_pkg::CharToString(rxQ[0]));
        temp8 = rxQ.pop_front(); // using temp8 avoids warnings
        temp8 = expectQ.pop_front();
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
