
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_gpio #(
                parameter integer ClockHz = 100_000_000,
                parameter integer GpioCount = 1,
                                  `OC_LOCALPARAM_SAFE(GpioCount),
                parameter         type CsrType = oclib_pkg::csr_32_s,
                parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
                parameter         type CsrProtocol = oclib_pkg::csr_32_s,
                parameter integer SyncCycles = 3,
                parameter bit     ResetSync = oclib_pkg::False,
                parameter integer ResetPipeline = 0
                )
 (
  input                        clock,
  input                        reset,
  input                        CsrType csr,
  output                       CsrFbType csrFb,
  output logic [GpioCount-1:0] gpioOut,
  output logic [GpioCount-1:0] gpioTristate,
  input [GpioCount-1:0]        gpioIn
  );

  `OC_STATIC_ASSERT(GpioCount>=1); // we shouldn't be instantiating this block if we don't have GPIOs

  logic                           resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // Implement address space 0

  // 0 : CSR ID
  //   [ 7: 0] GpioCount
  //   [31:16] csrId
  // 1->(GpioCount+1) : Gpio
  //   [    0]  out
  //   [    4]  drive
  //   [    8]  in

  localparam integer NumCsr = 1 + GpioCount;
  localparam logic [31:0] CsrId = { oclib_pkg::CsrIdGpio, 8'd0, 8'(GpioCount)};
  logic [0:NumCsr-1] [31:0] csrOut;
  logic [0:NumCsr-1] [31:0] csrIn;

  oclib_csr_array #(.CsrType(CsrType), .CsrFbType(CsrFbType), .CsrProtocol(CsrProtocol),
                    .NumCsr(NumCsr),
                    .CsrRwBits   ({ 32'h00000000, {GpioCount{32'h00000011}} }),
                    .CsrRoBits   ({ 32'h00000000, {GpioCount{32'h00000100}} }),
                    .CsrFixedBits({ 32'hffffffff, {GpioCount{32'h00000000}} }),
                    .CsrInitBits ({        CsrId, {GpioCount{32'h00000000}} }))
  uCSR (.clock(clock), .reset(resetSync),
        .csr(csr), .csrFb(csrFb),
        .csrRead(), .csrWrite(),
        .csrOut(csrOut), .csrIn(csrIn));

  logic [GpioCount-1:0]     gpioInSync;
  oclib_synchronizer #(.Width(GpioCount), .SyncCycles(SyncCycles))
  uSYNC (.clock(clock), .in(gpioIn), .out(gpioInSync));

  for (genvar i=0; i<GpioCount; i++) begin
    assign gpioOut[i] = csrOut[1+i][0];
    assign gpioTristate[i] = !csrOut[1+i][4];
    assign csrIn[i+1][8] = gpioInSync[i];
  end

endmodule // oc_gpio
