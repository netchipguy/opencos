
// SPDX-License-Identifier: MPL-2.0

`include "sim/ocsim_pkg.sv"

module ocsim_data_source
  #(
    parameter type Type = logic [31:0],
    parameter integer Verbose = `OC_VAL_ASDEFINED_ELSE(OC_SIM_VERBOSE, 0)
    )
  (
   input        clock,
   output       Type outData,
   output logic outValid,
   input        outReady
   );

  integer       dataContents = ocsim_pkg::DataTypeRandom;
  integer       dutyCycle = 100;
  logic         running = 0;
  integer       count = 0;

  task SetDataContents ( integer i );
    dataContents = i;
  endtask // SetDataContents

  task SetDutyCycle ( integer i );
    dutyCycle = i;
  endtask // SetDutyCycle

  task Start();
    running = 1;
  endtask // Start

  task Stop();
    running = 0;
  endtask // Stop

  function Type CreateData();
    Type o;
    if (dataContents == ocsim_pkg::DataTypeRandom) begin
      for (int i=0; i<(($bits(outData)+31)/32); i++) begin
        o = (o << 32) | {$random};
      end
    end
    else if (dataContents == ocsim_pkg::DataTypeZero) begin
      o = '0;
    end
    else if (dataContents == ocsim_pkg::DataTypeOne) begin
      o = '1;
    end
    else begin
      `OC_ERROR($sformatf("Don't understand dataContents = %0d", dataContents));
    end
    if (Verbose) $display("%t %m: Sourcing data #%0d: %p", $realtime, count, o);
    count = count + 1;
    return o;
  endfunction // CreateData

  initial outValid = 1'b0;

  always @(posedge clock) begin
    outValid <= (outValid && !outReady); // clear any outValid if we get outReady
    if (running && `OC_RAND_PERCENT(dutyCycle) && (!outValid || outReady)) begin
      outData <= CreateData();
      outValid <= 1'b1;
    end
  end

endmodule // ocsim_data_source
