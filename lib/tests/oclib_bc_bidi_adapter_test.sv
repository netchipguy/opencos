
// SPDX-License-Identifier: MPL-2.0

`include "sim/ocsim_defines.vh"
`include "sim/ocsim_pkg.sv"
`include "lib/oclib_pkg.sv"

module oclib_bc_bidi_adapter_test;

  localparam integer ClockHz = 100_000_000;

  logic clock, reset;

  ocsim_clock #(.ClockHz(ClockHz)) uCLOCK (.clock(clock));
  ocsim_reset uRESET (.clock(clock), .reset(reset));

  logic error;

  initial begin
    error = 0;
    $display("%t %m: *****************************", $realtime);
    $display("%t %m: START", $realtime);
    $display("%t %m: *****************************", $realtime);
    `OC_ANNOUNCE_PARAM_INTEGER(ClockHz);
    while (reset) @(posedge clock);
    repeat (10) @(posedge clock);
    uSINK_S0.SetDutyCycle(40);
    uSINK_S0.Start();
    uSINK_S9.SetDutyCycle(60);
    uSINK_S9.Start();
    uSOURCE_S0.SetDataContents(ocsim_pkg::DataTypeRandom);
    uSOURCE_S0.SetDutyCycle(40);
    uSOURCE_S0.Start();
    uSOURCE_S9.SetDataContents(ocsim_pkg::DataTypeRandom);
    uSOURCE_S9.SetDutyCycle(60);
    uSOURCE_S9.Start();
    repeat (1000) @(posedge clock);
    uSOURCE_S0.Stop();
    uSOURCE_S9.Stop();
    uSINK_S0.WaitForIdle();
    uSINK_S9.WaitForIdle();
    $display("%t %m: *****************************", $realtime);
    if (error) $display("%t %m: TEST FAILED", $realtime);
    else $display("%t %m: TEST PASSED", $realtime);
    $display("%t %m: *****************************", $realtime);
    $finish;
  end

  oclib_pkg::bc_8b_bidi_s fromS0, toS0;
  oclib_pkg::bc_8b_bidi_s fromS1, toS1;
  oclib_pkg::bc_async_8b_bidi_s fromS2, toS2;
  oclib_pkg::bc_8b_bidi_s fromS3, toS3;
  oclib_pkg::bc_async_1b_bidi_s fromS4, toS4;
  oclib_pkg::bc_8b_bidi_s fromS9, toS9;

  ocsim_data_source #(.Type(logic[7:0]))
  uSOURCE_S0 (.clock(clock), .outData(fromS0.data), .outValid(fromS0.valid), .outReady(toS0.ready));

  ocsim_data_sink #(.Type(logic[7:0]))
  uSINK_S0 (.clock(clock), .inData(toS0.data), .inValid(toS0.valid), .inReady(fromS0.ready));

  oclib_bc_bidi_adapter #(.BcTypeA(oclib_pkg::bc_8b_bidi_s),
                          .BcTypeB(oclib_pkg::bc_8b_bidi_s),
                          .BufferStages(3),
                          .ResetSync(1),
                          .ResetPipeline(3))
  uADAPTER_S1 (.clock(clock), .reset(reset),
               .aIn(fromS0), .aOut(toS0),
               .bIn(toS1), .bOut(fromS1));

  oclib_bc_bidi_adapter #(.BcTypeA(oclib_pkg::bc_8b_bidi_s),
                          .BcTypeB(oclib_pkg::bc_async_8b_bidi_s),
                          .BufferStages(3),
                          .ResetSync(0),
                          .ResetPipeline(3))
  uADAPTER_S2 (.clock(clock), .reset(reset),
               .aIn(fromS1), .aOut(toS1),
               .bIn(toS2), .bOut(fromS2));

  oclib_bc_bidi_adapter #(.BcTypeA(oclib_pkg::bc_async_8b_bidi_s),
                          .BcTypeB(oclib_pkg::bc_8b_bidi_s),
                          .BufferStages(0),
                          .ResetSync(0),
                          .ResetPipeline(0))
  uADAPTER_S3 (.clock(clock), .reset(reset),
               .aIn(fromS2), .aOut(toS2),
               .bIn(toS3), .bOut(fromS3));

  oclib_bc_bidi_adapter #(.BcTypeA(oclib_pkg::bc_8b_bidi_s),
                          .BcTypeB(oclib_pkg::bc_async_1b_bidi_s),
                          .BufferStages(3),
                          .ResetSync(0),
                          .ResetPipeline(3))
  uADAPTER_S4 (.clock(clock), .reset(reset),
               .aIn(fromS3), .aOut(toS3),
               .bIn(toS4), .bOut(fromS4));

  oclib_bc_bidi_adapter #(.BcTypeA(oclib_pkg::bc_async_1b_bidi_s),
                          .BcTypeB(oclib_pkg::bc_8b_bidi_s),
                          .BufferStages(0),
                          .ResetSync(0),
                          .ResetPipeline(0))
  uADAPTER_S5 (.clock(clock), .reset(reset),
               .aIn(fromS4), .aOut(toS4),
               .bIn(fromS9), .bOut(toS9));

  ocsim_data_sink #(.Type(logic[7:0]))
  uSINK_S9 (.clock(clock), .inData(toS9.data), .inValid(toS9.valid), .inReady(fromS9.ready));

  ocsim_data_source #(.Type(logic[7:0]))
  uSOURCE_S9 (.clock(clock), .outData(fromS9.data), .outValid(fromS9.valid), .outReady(toS9.ready));

  always @(posedge clock) begin
    if (fromS0.valid && toS0.ready) uSINK_S9.Expect(fromS0.data);
    if (fromS9.valid && toS9.ready) uSINK_S0.Expect(fromS9.data);
  end

endmodule // oclib_bc_bidi_adapter_test
