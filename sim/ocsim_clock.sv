
// SPDX-License-Identifier: MPL-2.0

// ocsim_clock.sv -- generate a clock for simulation

module ocsim_clock #(
                     parameter integer  ClockHz = 100000000,
                     parameter realtime ClockPeriod = (1s / ClockHz)
                     )
  (
   output logic clock
   );

  realtime      currentPeriod = ClockPeriod;

  always begin
    #(currentPeriod/2); clock = 1'b0;
    #(currentPeriod - (currentPeriod/2)); clock = 1'b1; // take care of rounding
  end

  task SetHz (input integer hz);
    currentPeriod = (1s / hz);
    $display("%t %m: Set Hz to %0d (period = %t)", $realtime, hz, currentPeriod);
  endtask // SetHz

  task SetPeriod (input realtime period);
    currentPeriod = period;
    $display("%t %m: Set Period to %t", $realtime, currentPeriod);
  endtask // SetPeriod

endmodule // ocsim_clock
