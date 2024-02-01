
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "sim/ocsim_defines.vh"
`include "sim/ocsim_pkg.sv"

module ocsim_data_sink
  #(
    parameter type Type = logic [31:0],
    parameter integer Verbose = `OC_VAL_ASDEFINED_ELSE(OC_SIM_VERBOSE, 0)
    )
  (
   input        clock,
   input        Type inData,
   input        inValid,
   output logic inReady
   );

  integer       dutyCycle = 100;
  logic         running = 0;
  integer       count = 0;

  task SetDutyCycle ( integer i );
    dutyCycle = i;
    $display("%t %m: Setting sink duty cycle to %0d%%", $realtime, dutyCycle);
  endtask // SetDutyCycle

  task Start();
    running = 1;
    $display("%t %m: Starting automatic traffic sink at %0d%% duty cycle", $realtime, dutyCycle);
  endtask // Start

  task Stop();
    running = 0;
    $display("%t %m: Stopping automatic traffic sink", $realtime);
  endtask // Stop

  Type expectQ [$];

  task Expect(Type d);
    if (Verbose) $display("%t %m: Expecting data: %p", $realtime, d);
    expectQ.push_back(d);
  endtask // Expect

  task ExpectMultiple(Type d [$]);
    if (Verbose) $display("%t %m: Expecting %0d data items:", $realtime, d.size());
    for (int i=0; i<d.size(); i++) Expect(d[i]);
  endtask // ExpectMultiple

  task WaitForIdle( input integer maxCycles = 10000 );
    int i;
    i = 0;
    $display("%t %m: Waiting for expectQ to empty (%0d cycles max)", $realtime, maxCycles);
    while (expectQ.size()) begin
      @(posedge clock);
      i = i + 1;
      if (i > maxCycles) begin
        `OC_ERROR($sformatf("expectQ still has %0d entries after waiting %0d cycles!", expectQ.size(), maxCycles));
      end
    end
    $display("%t %m: expectQ is empty (waited %0d cycles)", $realtime, i);
  endtask // WaitForIdle

  Type d;

  initial inReady = 1'b0;
  always @(posedge clock) begin
    inReady <= (running && `OC_RAND_PERCENT(dutyCycle));
    if (inValid && inReady) begin
      if (expectQ.size() == 0) begin
        `OC_ERROR($sformatf("Received data %p when expectQ was empty!", inData));
      end
      else begin
        d = expectQ.pop_front();
        if (d === inData) begin
          if (Verbose) $display("%t %m: Received data #%0d: %p", $realtime, count, d);
          count <= count+1;
        end
        else begin
          `OC_ERROR($sformatf("Received data #%0d %p when expectQ has %p!", count, inData, d));
        end
      end
    end
  end

endmodule // ocsim_data_sink
