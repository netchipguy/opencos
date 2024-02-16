
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_fan #(
                parameter integer ClockHz = 100_000_000,
                parameter integer FanCount = 1,
                                  `OC_LOCALPARAM_SAFE(FanCount),
                parameter integer FanDefaultDuty = `OC_VAL_ASDEFINED_ELSE(TARGET_FAN_DEFAULT_DUTY, 50),
                parameter integer FanDebounceCycles = `OC_VAL_ASDEFINED_ELSE(TARGET_FAN_DEBOUNCE_CYCLES, 5),
                parameter         type CsrType = oclib_pkg::csr_32_s,
                parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
                parameter         type CsrProtocol = oclib_pkg::csr_32_s,
                parameter integer SyncCycles = 3,
                parameter bit     ResetSync = oclib_pkg::False,
                parameter integer ResetPipeline = 0
                )
 (
  input                       clock,
  input                       reset,
  input                       CsrType csr,
  output                      CsrFbType csrFb,
  input [FanCount-1:0]        fanSense,
  output logic [FanCount-1:0] fanPwm
  );

  `OC_STATIC_ASSERT(FanCount>=1); // we shouldn't be instantiating this block if we don't have FANs

  logic                           resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // Implement address space 0

  // 0 : CSR ID
  //   [ 7: 0] FanCount
  //   [31:16] csrId
  // 1->(FanCount+1) : Fan
  //   [ 6: 0] dutyCycle (0=0%, 100=100%)
  //   [25:16] pulsesPerSecond

  localparam integer NumCsr = 1 + FanCount;
  localparam logic [31:0] CsrId = { oclib_pkg::CsrIdFan, 8'd0, 8'(FanCount)};
  localparam logic [31:0] FanInitCsr = { 24'd0, 1'b0, 7'(FanDefaultDuty) };
  logic [0:NumCsr-1] [31:0] csrOut;
  logic [0:NumCsr-1] [31:0] csrIn;

  oclib_csr_array #(.CsrType(CsrType), .CsrFbType(CsrFbType), .CsrProtocol(CsrProtocol),
                    .NumCsr(NumCsr),
                    .CsrRwBits   ({ 32'h00000000, {FanCount{32'h0000007f}} }),
                    .CsrRoBits   ({ 32'h00000000, {FanCount{32'h03ff0000}} }),
                    .CsrInitBits ({        CsrId, {FanCount{  FanInitCsr}} }),
                    .CsrFixedBits({ 32'hffffffff, {FanCount{32'h00000000}} }))
  uCSR (.clock(clock), .reset(resetSync),
        .csr(csr), .csrFb(csrFb),
        .csrRead(), .csrWrite(),
        .csrOut(csrOut), .csrIn(csrIn));

  // prescaler
  // this is supposed to divide input clock to generate prescalePulse at 2.5MHz (25KHz PWM freq * 100)

  localparam integer        PrescaleDivider = (ClockHz / 2500000);
  localparam integer        PrescaleW = $clog2(PrescaleDivider);
  localparam integer        PrescaleM2 = (PrescaleDivider-2);

  logic [PrescaleW-1:0]     prescaleCounter;
  logic                     prescalePulse;
  always_ff @(posedge clock) begin
    prescaleCounter <= (resetSync ? '0 : (prescalePulse ? '0 : (prescaleCounter+1)));
    prescalePulse <= (prescaleCounter == PrescaleM2);
  end

  // PWM phase counter
  // pwmValue counts from 0-99 every 40us, so we have ~25KHz PWM period to the fans

  localparam integer        PwmTC = 99;
  localparam integer        PwmW = 7; // needs to count up to 99

  logic [PwmW-1:0]          pwmCounter;
  logic                     pwmMax;
  always_ff @(posedge clock) begin
    pwmCounter <= (resetSync ? '0 : (prescalePulse ? (pwmMax ? '0 : (pwmCounter+1)) : pwmCounter));
    pwmMax <= (pwmCounter == PwmTC);
  end

  // Second counter
  // secondCounter counts from (roughly) 0-24999, incrementing every ~40us, so we can count fan pulses per second
  // Note that we reuse the PWM related prescalers to save flops.  However, the nature of the prescale value (i.e.
  // only 40 with a 100Mhz ClockHz) means that there is potential for a few percent error in the ~25KHz of the PWM,
  // which is OK for driving the fan.  For SENSING the fan, we adjust for the actual period of the PWM so that we
  // count very close to one second here.

  localparam integer        SecondTC = (ClockHz/(100*PrescaleDivider))-1;
  localparam integer        SecondW = 15; // needs to count up to ~23-27K

  logic [SecondW-1:0]       secondCounter;
  logic                     secondMax;
  logic                     secondPulse;
  always_ff @(posedge clock) begin
    secondCounter <= (resetSync ? SecondTC :
                     (prescalePulse && pwmMax) ? (secondMax ? '0 : (secondCounter+1)) :
                     secondCounter);
    secondMax <= (secondCounter == SecondTC);
    secondPulse <= (prescalePulse && pwmMax && secondMax);
  end

  // per-FAN logic
  logic [FanCount-1:0] fanSenseClean;
  logic [FanCount-1:0] fanSenseCleanQ;
  logic [FanCount-1:0] fanSensePulse;
  logic [FanCount-1:0] [9:0] pulsesThisPeriod;
  logic [FanCount-1:0] [9:0] pulsesLastPeriod;

  generate
    for (genvar i=0; i<FanCount; i++) begin

      // Output a PWM waveform per fan, forcing fans on during reset
      always_ff @(posedge clock) begin
        fanPwm[i] <= (resetSync ? 1'b1 : (csrOut[1+i][6:0] > pwmCounter));
      end

      // Debounce the fan sense input
      oclib_debounce #(.SyncCycles(SyncCycles), .DebounceCycles(FanDebounceCycles))
      uDEBOUNCE (.clock(clock), .reset(resetSync), .in(fanSense[i]), .out(fanSenseClean[i]));

      // find rising edge of debounced fan sense input
      always_ff @(posedge clock) begin
        fanSenseCleanQ[i] <= fanSenseClean[i];
        fanSensePulse[i] <= (fanSenseClean[i] && !fanSenseCleanQ[i]);
      end

      // Count the pulses in this period, and keep the count from the last second
      always_ff @(posedge clock) begin
        pulsesThisPeriod[i] <= (secondPulse ? '0 : (pulsesThisPeriod[i] + fanSensePulse[i]));
        pulsesLastPeriod[i] <= (secondPulse ? pulsesThisPeriod[i] : pulsesLastPeriod[i]);
      end

      // send back status to CSRs
      assign csrIn[1+i][25:16] = pulsesLastPeriod[i];
    end
  endgenerate

endmodule // oc_fan
