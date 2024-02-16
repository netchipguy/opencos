
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oclib_csr_null
  #(
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter         type CsrProtocol = oclib_pkg::csr_32_s,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input  clock,
   input  reset,
   input  CsrType csr,
   output CsrFbType csrFb
   );

  logic   resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // first we normalize incoming bus to CsrIntType

  localparam type CsrIntType = oclib_pkg::csr_32_s;
  localparam type CsrIntFbType = oclib_pkg::csr_32_fb_s;

  CsrIntType csrInt;
  CsrIntFbType csrIntFb;

  oclib_csr_adapter #(.CsrInType(CsrType), .CsrInFbType(CsrFbType), .CsrInProtocol(CsrProtocol),
                      .CsrOutType(CsrIntType), .CsrOutFbType(CsrIntFbType),
                      .SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uCSR_ADAPTER (.clock(clock), .reset(resetSync),
                .in(csr), .inFb(csrFb),
                .out(csrInt), .outFb(csrIntFb) );

  logic      strobe;
  logic      strobeQ;
  logic      ready;

  assign strobe = (csrInt.read || csrInt.write);

  always_comb begin
    csrIntFb = '0;
    csrIntFb.rdata = 32'habadcafe;
    csrIntFb.ready = ready;
    csrIntFb.error = 1'b1;
  end

  always_ff @(posedge clock) begin
    if (resetSync) begin
      strobeQ <= 1'b0;
      ready <= 1'b0;
    end
    else begin
      strobeQ <= (csrInt.read || csrInt.write);
      ready <= (strobe && ~strobeQ);
    end
  end

endmodule // oclib_csr_null
