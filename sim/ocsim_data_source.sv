
// SPDX-License-Identifier: MPL-2.0

`include "sim/ocsim_pkg.sv"
`include "sim/ocsim_defines.vh"
`include "lib/oclib_defines.vh"

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
  logic         autoMode = 0;
  integer       queueCount = 0;
  integer       sendCount = 0;

  // We can provide data to send, either queueing up a batch (and configuring duty cycle) or sending
  // in a blocking fashion

  Type sendQ [$];

  task Send( Type d, input bit blocking = 0, input integer maxCycles = 10000);
    int i;
    sendQ.push_back(d);
    i = 0;
    while (blocking && sendQ.size()) begin
      @(posedge clock);
      if (i > maxCycles) `OC_ERROR($sformatf("Don't understand dataContents = %0d", dataContents));
    end
    if (Verbose && (blocking==0)) $display("%t %m: Queued data #%0d: %p", $realtime, queueCount, d);
    queueCount++;
  endtask // Send

  task SendMultiple ( Type d [$], input bit blocking = 0, input integer maxCycles = 10000);
    if (Verbose) $display("%t %m: Sending %0d items...", $realtime, d.size());
    for (int i=0; i<d.size(); i++) Send(d[i], blocking, maxCycles);
  endtask // SendMultiple

  // This transactor can also create it's own dummy output data with variable duty cycle and patterns

  task SetDataContents ( integer i );
    dataContents = i;
  endtask // SetDataContents

  task SetDutyCycle ( integer i );
    dutyCycle = i;
    $display("%t %m: Setting source duty cycle to %0d%%", $realtime, dutyCycle);
  endtask // SetDutyCycle

  task Start();
    $display("%t %m: Starting automatic traffic generation at %0d%% duty cycle", $realtime, dutyCycle);
    autoMode = 1;
  endtask // Start

  task Stop();
    $display("%t %m: Stopping automatic traffic generation", $realtime);
    autoMode = 0;
  endtask // Stop

  function Type CreateData();
    Type o;
    if (dataContents == ocsim_pkg::DataTypeRandom) begin
      for (int i=0; i<(($bits(outData)+31)/32); i++)  o = (o << 32) | {$random};
    end
    else if (dataContents == ocsim_pkg::DataTypeZero) o = '0;
    else if (dataContents == ocsim_pkg::DataTypeOne)  o = '1;
    else `OC_ERROR($sformatf("Don't understand dataContents = %0d", dataContents));
    return o;
  endfunction // CreateData

  initial outValid = 1'b0;

  Type outDataD;
  always @(posedge clock) begin
    outValid <= (outValid && !outReady); // clear any outValid if we get outReady
    if ((sendQ.size() || autoMode) && `OC_RAND_PERCENT(dutyCycle) && (!outValid || outReady)) begin
      outDataD = (sendQ.size() ? sendQ.pop_front() : CreateData());
      if (Verbose) $display("%t %m: Sending data #%0d: %p", $realtime, sendCount, outDataD);
      sendCount++;
      outData <= outDataD;
      outValid <= 1'b1;
    end
  end

endmodule // ocsim_data_source
