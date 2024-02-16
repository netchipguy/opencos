
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_led #(
                parameter integer ClockHz = 100_000_000,
                parameter integer LedCount = 1,
                                  `OC_LOCALPARAM_SAFE(LedCount),
                parameter         type CsrType = oclib_pkg::csr_32_s,
                parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
                parameter         type CsrProtocol = oclib_pkg::csr_32_s,
                parameter integer SyncCycles = 3,
                parameter bit     ResetSync = oclib_pkg::False,
                parameter integer ResetPipeline = 0
                )
 (
  input                           clock,
  input                           reset,
  input                           CsrType csr,
  output                          CsrFbType csrFb,
  output logic [LedCountSafe-1:0] ledOut
  );

  logic                           resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // Implement address space 0

  // 0 : CSR ID
  //   [ 7: 0] LedCount
  //   [31:16] csrId
  // 1 : Prescale
  //   [ 9: 0] count (period will be count*2097152, so for ~1Hz we have 47 at 100MHz)
  // 2->(LedCount+1) : Control
  //   [ 1: 0]  mode (0 = off, 1 = on, 2 = blink, 3 = heartbeat)
  //   [13: 8] brightness (0-63)
  //   [18:16] blinks (0-7, valid in mode 2)

  localparam integer NumCsr = 2 + LedCount;
  localparam logic [31:0] CsrId = { oclib_pkg::CsrIdLed, 8'd0, 8'(LedCount)};
  localparam logic [31:0] InitPrescale = (ClockHz / 2097152);
  logic [0:NumCsr-1] [31:0] csrOut;
  logic [0:NumCsr-1] [31:0] csrIn;

  oclib_csr_array #(.CsrType(CsrType), .CsrFbType(CsrFbType), .CsrProtocol(CsrProtocol),
                    .NumCsr(NumCsr),
                    .CsrRwBits   ({ 32'h00000000, 32'h000003ff, {LedCount{32'h00073f03}} }),
                    .CsrRoBits   ({ 32'h00000000, 32'h00000000, {LedCount{32'h00000000}} }),
                    .CsrInitBits ({        CsrId, InitPrescale, {LedCount{32'h00000000}} }),
                    .CsrFixedBits({ 32'hffffffff, 32'h00000000, {LedCount{32'h00000000}} }))
  uCSR (.clock(clock), .reset(resetSync),
        .csr(csr), .csrFb(csrFb),
        .csrRead(), .csrWrite(),
        .csrOut(csrOut), .csrIn(csrIn));

  logic [9:0]               prescaleTC;
  assign prescaleTC = csrOut[1][9:0];

  // prescaler
  // this is supposed to divide input clock to generate prescalePulse every ~0.5us

  logic [9:0]               prescaleCounter;
  logic                     prescalePulse;
  always_ff @(posedge clock) begin
    prescaleCounter <= (resetSync ? '0 : (prescalePulse ? '0 : (prescaleCounter+1)));
    prescalePulse <= ((prescaleCounter+2) == prescaleTC);
  end

  // TDM phase counter
  // tdmValue counts from 0-63 every ~0.5ms, so we have ~2KHz blinks on the LEDs

  logic [9:0]               tdmCounter;
  logic                     tdmPulse;
  logic [5:0]               tdmValue;
  always_ff @(posedge clock) begin
    tdmCounter <= (resetSync ? '0 : (tdmCounter + prescalePulse));
    tdmPulse <= ((&tdmCounter) && prescalePulse);
  end
  assign tdmValue = tdmCounter[9:4];

  // Intra-step counter
  // this counts from 0-255 every ~128ms, so each step will be 1/8th of a second

  logic [7:0]               intraCounter;
  logic                     intraPulse;
  always_ff @(posedge clock) begin
    intraCounter <= (resetSync ? '0 : (intraCounter + tdmPulse));
    intraPulse <= ((&intraCounter) && tdmPulse);
  end

  // Step counter
  // this counts from 0-7 every ~1s, which is our overall period

  logic [4:0]               stepCounter;
  always_ff @(posedge clock) begin
    stepCounter <= (resetSync ? '0 : (stepCounter + intraPulse));
  end

  // heartbeat pattern
  // 100MHz (10ns) clock freq, ~1Hz beat period, so 128M (27 bit)
  // 8 phases (up-down-up-down-off-off-off-off), so 16M (24 bit) per sequence phase
  // 64 brightness levels, so 64 steps per phase, so 256K (18 bit) per step
  // 32 reps per step, so 8K (13 bit) per rep
  // 64 brightness levels, so 128 (7 bit) per TDM phase, and this is the prescaler value

  logic                     heartbeat;
  always_ff @(posedge clock) begin
    heartbeat <= (stepCounter[2] ? 1'b0 :                            // off during steps 4-7
                  stepCounter[0] ? (~intraCounter[7:2] > tdmValue) : // falling brightness during steps 1, 3
                  (intraCounter[7:2] > tdmValue));                   // rising brightness during steps 0, 2
  end

  for (genvar i=0; i<LedCount; i++) begin

    logic [1:0] ledMode;
    logic [5:0] ledBright;
    logic [2:0] ledBlinks;

    assign ledMode = csrOut[2+i][1:0];
    assign ledBright = csrOut[2+i][13:8];
    assign ledBlinks = csrOut[2+i][18:16];

    always_ff @(posedge clock) begin
      ledOut[i] <= ((ledMode == 2'b01) ? (ledBright >= tdmValue) :                              // on
                    (ledMode == 2'b10) ? ((ledBlinks > stepCounter[4:2]) &&                     // blink
                                          (ledBright >= tdmValue) && stepCounter[1]) :
                    (ledMode == 2'b11) ? ((ledBright[5:2] >= intraCounter[3:0]) && heartbeat) : // heartbeat
                    1'b0);                                                                      // off
    end

  end

endmodule // oc_led
