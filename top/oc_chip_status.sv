
// SPDX-License-Identifier: MPL-2.0

`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"

module oc_chip_status #(
                        parameter integer ClockHz = 100_000_000
                        )
  (
   input  clock,
   input  reset,
   output oclib_pkg::chip_status_s chipStatus
   );

  logic   resetQ;
  oclib_synchronizer uRESET_SYNC (.clock(clock), .in(reset), .out(resetQ));

  // *** Real Time timers
  // This can be a little tricky hence why it's provided as a service by OC.  The goal is to
  // get wall clock timing signals to userspace.  Eventual intention is to allow syncing to
  // host or IEEE 1588, input pin, etc, kinds of sources, with a tracking loop.  For now we
  // just create accurate microsecond pulses (which may require fractional counting) and then
  // use that to create millisecond and second based pulses for various uses.

  // note: timerCountUS is NOT counting microseconds, it is the counter that is used to generate
  // a pulse each microsecond, so it's counting clocks.  Likewise timerCountMS is actually counting
  // microseconds to generate a pulse each millisecond...  a bit confusing I know, may get refactored

  // 10-N, how many cycles we always count (it will be 156 for 156.25Mhz)
  localparam integer UsCountNominal = (ClockHz/1_000_000);

  // how many US should have an extra cycle per ms.  if 0, none, the UsCountNominal is exact.
  // otherwise, for example ClockHz = 156_250_000, and UsCountNominal = 156, each second we
  // need 250_000 extra clocks, so each millisecond we need 250 extra clocks, so the first 250
  // microseconds in each millisecond, we will count an extra clock.
  localparam integer UsCountChangeMs = (((UsCountNominal*1_000_000) == ClockHz) ? 0 : // exact case
                                        ((ClockHz - (UsCountNominal*1_000_000)) / 1000));

  localparam integer UsCountWidth = (UsCountChangeMs ? $clog2(UsCountNominal+1) : $clog2(UsCountNominal));

  // how many MS should have an extra cycle per s.  this is another term that causes the above kind
  // of cycle extension.  This term takes care of the least significant digits of frequency.  For
  // example ClockHz = 33_333_333, and UsCountNominal = 33, and UsCountChaneMs = 333.  This takes
  // care of counting 33_333_000 and so we need MsCountChangeS = 333 to get to 33_333_333.

  localparam integer MsCountChangeS = ((((UsCountNominal*1_000_000)+(UsCountChangeMs*1000)) == ClockHz) ? 0 :
                                       (ClockHz - (UsCountNominal*1_000_000) - (UsCountChangeMs*1000)));

  // counters
  logic [UsCountWidth-1:0] timerCountUS;
  logic [9:0]              timerCountMS;
  logic [9:0]              timerCountS;
  // internal registered pulses to ease timing
  logic                    timerClearUS;
  logic                    timerClearMS;
  logic                    timerClearS;
  // output pulses aligned to each other and changes in counters (assert at zero counts)
  logic                    timerPulseUS;
  logic                    timerPulseMS;
  logic                    timerPulseS;

  // we set the nominal terminal count to be -2 (optionally "changed" to be -1) because of registering.
  // If we are counting to 100, then during 98 we have combo timerCountUS == timerTerminalCountUS, then
  // during 99 we are asserting timerClearUS, and hence timerPulseUS happens next as timerCountUS goes 0
  logic [UsCountWidth-1:0] timerTerminalCountUS;
  logic                    timerLongerUS;

  assign timerTerminalCountUS = (timerLongerUS ? (UsCountNominal-1) : (UsCountNominal-2));

  always @(posedge clock) begin
    if (resetQ) begin
      timerLongerUS <= 1'b0;
      timerClearUS <= 1'b0;
      timerClearMS <= 1'b0;
      timerClearS <= 1'b0;
      timerPulseUS <= 1'b0;
      timerPulseMS <= 1'b0;
      timerPulseS <= 1'b0;
      timerCountUS <= '0;
      timerCountMS <= '0;
      timerCountS <= '0;
    end
    else begin
      timerLongerUS <= ((timerCountMS < UsCountChangeMs) ||
                        (timerCountMS == UsCountChangeMs) && (timerCountS < MsCountChangeS));
      timerClearUS <= (timerCountUS == timerTerminalCountUS);
      timerClearMS <= (timerCountMS == 'd999);
      timerClearS <= (timerCountS == 'd999);
      timerPulseUS <= ((timerPulseUS && (timerCountUS < 'd4)) || (timerClearUS));
      timerPulseMS <= ((timerPulseMS && (timerCountUS < 'd4)) || (timerClearUS && timerClearMS));
      timerPulseS <= ((timerPulseS && (timerCountUS < 'd4)) || (timerClearUS && timerClearMS && timerClearS));
      timerCountUS <= (timerClearUS ? 'd0 : (timerCountUS + 'd1));
      timerCountMS <= (timerClearUS ? (timerClearMS ? 'd0 : (timerCountMS + 'd1)) : timerCountMS);
      timerCountS <= ((timerClearUS && timerClearMS) ? (timerClearS ? 'd0 : (timerCountS + 'd1)) : timerCountS);
    end
  end

  assign chipStatus.tick1us = timerPulseUS;
  assign chipStatus.tick1ms = timerPulseMS;
  assign chipStatus.tick1s = timerPulseS;
  assign chipStatus.halt = 1'b0;
  assign chipStatus.error = 1'b0;
  assign chipStatus.clear = 1'b0;

endmodule // oc_chip_status
