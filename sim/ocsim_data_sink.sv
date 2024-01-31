
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
  endtask // SetDutyCycle

  task Start();
    running = 1;
  endtask // Start

  task Stop();
    running = 0;
  endtask // Stop

  Type expectQ [$];

  task Expect(Type d);
    expectQ.push_back(d);
    if (Verbose) $display("%t %m: Expecting data: %p", $realtime, d);
  endtask // Expect

  task WaitForIdle( integer maxCycles = 10000 );
    int i;
    i = 0;
    $display("%t %m: Waiting for expectQ to empty (%0d cycles max)", $realtime, maxCycles);
    while (expectQ.size() && (i < maxCycles)) begin
      @(posedge clock);
      i = i + 1;
    end
    if (expectQ.size()) begin
      `OC_ERROR($sformatf("expectQ still has %0d entries after waiting %0d cycles!", expectQ.size(), maxCycles));
//      `OC_ERROR("expectQ still has entries after waiting max cycles!");
    end
    else begin
      $display("%t %m: expectQ is empty (waited %0d cycles)", $realtime, i);
    end
  endtask

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
