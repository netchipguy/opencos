
// SPDX-License-Identifier: MPL-2.0

// ocsim_reset.sv -- generate a clock for simulation

module ocsim_reset #(
                     parameter integer StartupResetCycles = 20,
                     parameter integer CyclesAfterReset = 10
                     )
  (
   input clock,
   output logic reset
   );

  initial Reset(StartupResetCycles);

  task Reset (input integer resetCycles = StartupResetCycles, input integer postResetCycles = CyclesAfterReset);
    if (resetCycles) begin
      $display("%t %m: Triggering reset for %0d cycles", $realtime, resetCycles);
      reset = 1'b1;
      repeat (resetCycles) @(posedge clock);
      reset <= 1'b0;
      repeat (postResetCycles) @(posedge clock);
    end
  endtask // Reset

endmodule // ocsim_reset
