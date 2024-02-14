
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oclib_csr_space_splitter
  #(
    parameter         type CsrInType = oclib_pkg::csr_32_s,
    parameter         type CsrInFbType = oclib_pkg::csr_32_fb_s,
    parameter         type CsrOutType = oclib_pkg::csr_32_s,
    parameter         type CsrOutFbType = oclib_pkg::csr_32_fb_s,
    parameter integer Spaces = 2,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0,
    parameter         type CsrIntType = oclib_pkg::csr_32_s,
    parameter         type CsrIntFbType = oclib_pkg::csr_32_fb_s
    )
  (
   input                            clock,
   input                            reset,
   input                            csrSelect = 1'b1,
   input                            CsrInType in,
   output                           CsrInFbType inFb,
   output logic [Spaces-1:0] outSelect,
   output                           CsrOutType out,
   input                            CsrOutFbType outFb [0:Spaces-1]
   );

  // synchronize/pipeline reset as needed
  logic                           resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // convert incoming CSR array if necessary
  CsrIntType csrInt;
  CsrIntFbType csrIntFb;

  if (type(CsrInType) != type(CsrIntType)) begin

    oclib_csr_adapter #(.CsrInType(CsrInType), .CsrInFbType(CsrInFbType),
                        .CsrOutType(CsrIntType), .CsrOutFbType(CsrIntFbType))
    uCSR_ADAPTER (.clock(clock), .reset(resetSync),
                  .in(in), .inFb(inFb),
                  .out(csrInt), .outFb(csrIntFb));
  end
  else begin
    assign csrInt = in;
    assign inFb = csrIntFb;
  end

  CsrOutFbType outSelectedFb;
  always_comb begin
    outSelect = '0;
    outSelect[out.space] = 1'b1;
    outSelectedFb = outFb[out.space];
  end

  // convert outgoing CSR array if necessary
  if (type(CsrOutType) != type(CsrIntType)) begin

    oclib_csr_adapter #(.CsrInType(CsrIntType), .CsrInFbType(CsrIntFbType),
                        .CsrOutType(CsrOutType), .CsrOutFbType(CsrOutFbType))
    uCSR_ADAPTER (.clock(clock), .reset(resetSync),
                  .in(csrInt), .inFb(csrIntFb),
                  .out(out), .outFb(outSelectedFb));
  end
  else begin
    assign out = csrInt;
    assign csrIntFb = outSelectedFb;
  end


endmodule // oclib_csr_space_splitter
