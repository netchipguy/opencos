
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

// ocsim_reset.sv -- generate a clock for simulation

module ocsim_reset #(
                     parameter integer StartupResetCycles = 20,
                     parameter integer CyclesAfterReset = 10,
                     parameter bit ActiveLow = oclib_pkg::False
                     )
  (
   input clock,
   output logic reset
   );

  initial Reset(StartupResetCycles);

  task Reset (input integer resetCycles = StartupResetCycles, input integer postResetCycles = CyclesAfterReset);
    if (resetCycles) begin
      $display("%t %m: Triggering reset for %0d cycles", $realtime, resetCycles);
      reset = !ActiveLow;
      repeat (resetCycles) @(posedge clock);
      reset <= ActiveLow;
      repeat (postResetCycles) @(posedge clock);
    end
  endtask // Reset

endmodule // ocsim_reset
