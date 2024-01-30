
// SPDX-License-Identifier: MPL-2.0

`include "../../lib/oclib_pkg.sv"
`include "../../lib/oclib_defines.vh"

module oc_chip_status_test;

//  localparam integer ClockHz = 100_000_000;
  localparam integer ClockHz = 156_250_000;
//  localparam integer ClockHz = 33_333_333;
  localparam realtime ClockPeriod = (1s/ClockHz);
  localparam realtime AllowedJitter = (2 * ClockPeriod);

  logic clock, reset;

  ocsim_clock #(.ClockHz(ClockHz)) uCLOCK (.clock(clock));
  ocsim_reset uRESET (.clock(clock), .reset(reset));


  oclib_pkg::chip_status_s chipStatus;

  oc_chip_status #(.ClockHz(ClockHz))
  uDUT (.clock(clock), .reset(reset), .chipStatus(chipStatus));

  realtime lastUsPulse, minUsPulse, maxUsPulse, avgUsPulse, totalUsPulse;
  realtime lastMsPulse, minMsPulse, maxMsPulse, avgMsPulse, totalMsPulse;
  realtime lastSPulse, minSPulse, maxSPulse, avgSPulse, totalSPulse;
  int      totalUsSamples, totalMsSamples, totalSSamples;

  realtime tempTime;
  int      i;
  logic    error;

  initial begin
    error = 0;
    lastUsPulse = 0s;
    lastMsPulse = 0s;
    lastSPulse = 0s;
    minUsPulse = 1000s;
    minMsPulse = 1000s;
    minSPulse = 1000s;
    maxUsPulse = 0s;
    maxMsPulse = 0s;
    maxSPulse = 0s;
    totalUsPulse = 0s;
    totalMsPulse = 0s;
    totalSPulse = 0s;
    totalUsSamples = 0;
    totalMsSamples = 0;
    totalSSamples = 0;
    $display("%t %m: *****************************", $realtime);
    $display("%t %m: START", $realtime);
    $display("%t %m: *****************************", $realtime);
    `OC_ANNOUNCE_PARAM_INTEGER(ClockHz);
    `OC_ANNOUNCE_PARAM_REALTIME(ClockPeriod);
    `OC_ANNOUNCE_PARAM_REALTIME(AllowedJitter);
    for (i=0; i<100; i++) begin
      repeat (5_000_000) @(posedge clock);
      $display("%t %m: SIM AT ITER %0d/100, TIME=%.6fs", $realtime, i+1, $realtime/1s);
      $display("%t %m: usPulse: %.3f/%.3f/%.3fns", $realtime, minUsPulse/1ns, avgUsPulse/1ns, maxUsPulse/1ns);
      $display("%t %m: msPulse: %.3f/%.3f/%.3fns", $realtime, minMsPulse/1ns, avgMsPulse/1ns, maxMsPulse/1ns);
      $display("%t %m:  sPulse: %.3f/%.3f/%.3fns", $realtime, minSPulse/1ns, avgSPulse/1ns, maxSPulse/1ns);
      CheckResults();
    end
    $display("%t %m: *****************************", $realtime);
    if (error) $display("%t %m: TEST FAILED", $realtime);
    else $display("%t %m: TEST PASSED", $realtime);
    $display("%t %m: *****************************", $realtime);
    $finish;
  end

  task CheckResults();
    if (minUsPulse < 999s) begin
      if (minUsPulse < (1us - AllowedJitter)) begin
        $display("%t %m: ERROR: minUsPulse too low (%.3fns)", $realtime, minUsPulse/1ns); error = 1;
      end
      if (maxUsPulse > (1us + AllowedJitter)) begin
        $display("%t %m: ERROR: maxUsPulse too high (%.3fns)", $realtime, maxUsPulse/1ns); error = 1;
      end
    end
    if (minMsPulse < 999s) begin
      if (minMsPulse < (1ms - AllowedJitter)) begin
        $display("%t %m: ERROR: minMsPulse too low (%.3fns)", $realtime, minMsPulse/1ns); error = 1;
      end
      if (maxMsPulse > (1ms + AllowedJitter)) begin
        $display("%t %m: ERROR: maxMsPulse too high (%.3fns)", $realtime, maxMsPulse/1ns); error = 1;
      end
    end
    if (minSPulse < 999s) begin
      if (minSPulse < (1s - AllowedJitter)) begin
        $display("%t %m: ERROR: minSPulse too low (%.3fns)", $realtime, minSPulse/1ns); error = 1;
      end
      if (maxSPulse > (1s + AllowedJitter)) begin
        $display("%t %m: ERROR: maxSPulse too high (%.3fns)", $realtime, maxSPulse/1ns); error = 1;
      end
    end
  endtask

  always @(posedge chipStatus.tick1us) begin
    if (lastUsPulse > 0s) begin
      tempTime = $realtime - lastUsPulse;
      if (tempTime < minUsPulse) begin
        minUsPulse = tempTime;
        $display("%t %m: New minUsPulse=%.3fns", $realtime, minUsPulse/1ns);
      end
      if (tempTime > maxUsPulse) begin
        maxUsPulse = tempTime;
        $display("%t %m: New maxUsPulse=%.3fns", $realtime, maxUsPulse/1ns);
      end
      totalUsPulse += tempTime;
      totalUsSamples += 1;
      avgUsPulse = (totalUsPulse / totalUsSamples);
    end
    lastUsPulse = $realtime;
  end

  always @(posedge chipStatus.tick1ms) begin
    if (lastMsPulse > 0s) begin
      tempTime = $realtime - lastMsPulse;
      if (tempTime < minMsPulse) begin
        minMsPulse = tempTime;
        $display("%t %m: New minMsPulse=%.3fns", $realtime, minMsPulse/1ns);
      end
      if (tempTime > maxMsPulse) begin
        maxMsPulse = tempTime;
        $display("%t %m: New maxMsPulse=%.3fns", $realtime, maxMsPulse/1ns);
      end
      totalMsPulse += tempTime;
      totalMsSamples += 1;
      avgMsPulse = (totalMsPulse / totalMsSamples);
    end
    lastMsPulse = $realtime;
  end

  always @(posedge chipStatus.tick1s) begin
    if (lastSPulse > 0s) begin
      tempTime = $realtime - lastSPulse;
      if (tempTime < minSPulse) begin
        minSPulse = tempTime;
        $display("%t %m: New minSPulse=%.3fns", $realtime, minSPulse/1ns);
      end
      if (tempTime > maxSPulse) begin
        maxSPulse = tempTime;
        $display("%t %m: New maxSPulse=%.3fns", $realtime, maxSPulse/1ns);
      end
      totalSPulse += tempTime;
      totalSSamples += 1;
      avgSPulse = (totalSPulse / totalSSamples);
    end
    lastSPulse = $realtime;
  end

endmodule // oc_chip_status_test
