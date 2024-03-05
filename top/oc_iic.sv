
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_iic #(
                parameter integer ClockHz = 100_000_000,
                parameter bit     OffloadEnable = oclib_pkg::False,
                parameter         type CsrType = oclib_pkg::csr_32_s,
                parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
                parameter         type CsrProtocol = oclib_pkg::csr_32_s,
                parameter integer SyncCycles = 3,
                parameter bit     ResetSync = oclib_pkg::False,
                parameter integer ResetPipeline = 0
                )
 (
  input        clock,
  input        reset,
  input        CsrType csr,
  output       CsrFbType csrFb,
  input        iicScl,
  output logic iicSclTristate,
  input        iicSda,
  output logic iicSdaTristate
  );

  logic                           resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // need to check OffloadEnable against the OC_LIBRARY_* defines
  localparam integer              Spaces = (OffloadEnable ? 2 : 1);
  localparam                      type CsrIntType = oclib_pkg::csr_32_s;
  localparam                      type CsrIntFbType = oclib_pkg::csr_32_fb_s;
  CsrIntType    [Spaces-1:0] csrInt;
  CsrIntFbType  [Spaces-1:0] csrIntFb;

  oclib_csr_adapter #(.CsrInType(CsrType), .CsrInFbType(CsrFbType), .CsrInProtocol(CsrProtocol),
                      .CsrOutType(CsrIntType), .CsrOutFbType(CsrIntFbType),
                      .UseClockOut(oclib_pkg::False),
                      .SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline),
                      .Spaces(Spaces))
  uCSR_ADAPTER (.clock(clock), .reset(resetSync),
                .in(csr), .inFb(csrFb),
                .out(csrInt), .outFb(csrIntFb) );

  // Implement address space 0

  // 0 : CSR ID
  //   [    0] OffloadEnable
  //   [15: 4] OffloadType
  //   [31:16] csrId
  // 1 : Control
  //   [    0] sclManual
  //   [    1] sclTristate
  //   [    3] sclIn
  //   [    4] sdaManual
  //   [    5] sdaTristate
  //   [    7] sdaIn
  //   [   30] offloadDebug
  //   [   31] offloadInterrupt

  localparam [7:0] OffloadType = ((!OffloadEnable) ? 8'd0 : // None
                                  `OC_VAL_IFDEF(OC_LIBRARY_ULTRASCALE_PLUS) ? 8'd1 : // Xilinx AXI-IIC
                                  8'hff); // unknown

  localparam integer NumCsr = 2; // 1 id
  localparam logic [31:0] CsrId = { oclib_pkg::CsrIdIic, OffloadType, 7'd0, OffloadEnable};
  logic [0:NumCsr-1] [31:0] csrOut;
  logic [0:NumCsr-1] [31:0] csrIn;

  oclib_csr_array #(.CsrType(CsrIntType), .CsrFbType(CsrIntFbType),
                    .NumCsr(NumCsr),
                    .CsrRwBits   ({ 32'h00000000, 32'h00000022 | (OffloadEnable?'h11:'0) }),
                    .CsrRoBits   ({ 32'h00000000, 32'hc0000088 }),
                    .CsrFixedBits({ 32'hffffffff, 32'h00000000 }),
                    .CsrInitBits ({ CsrId       , 32'h00000000 }))
  uCSR (.clock(clock), .reset(resetSync),
        .csr(csrInt[0]), .csrFb(csrIntFb[0]),
        .csrRead(), .csrWrite(),
        .csrOut(csrOut), .csrIn(csrIn));

  logic                     csrSclManual;
  logic                     csrSclTristate;
  logic                     csrSclIn;
  logic                     csrSdaManual;
  logic                     csrSdaTristate;
  logic                     csrSdaIn;
  logic                     offloadDebug;
  logic                     offloadInterrupt;

  assign csrSclManual = csrOut[1][0];
  assign csrSclTristate = csrOut[1][1];

  assign csrSdaManual = csrOut[1][4];
  assign csrSdaTristate = csrOut[1][5];

  oclib_synchronizer #(.Width(2))
  uSYNC (.clock(clock), .in({iicSda, iicScl}), .out({csrSdaIn, csrSclIn}));

  assign csrIn[1][3] = csrSclIn;
  assign csrIn[1][7] = csrSdaIn;
  assign csrIn[1][30] = offloadDebug;
  assign csrIn[1][31] = offloadInterrupt;

  if (OffloadEnable) begin

`ifdef OC_LIBRARY_ULTRASCALE_PLUS

    oclib_pkg::axil_32_s      axil;
    oclib_pkg::axil_32_fb_s   axilFb;

    logic                      offloadSclTristate;
    logic                      offloadSdaTristate;

    // Implement address space 1

    oclib_csr_to_axil #(.CsrType(CsrIntType), .CsrFbType(CsrIntFbType))
    uCSR_TO_AXIL (.clock(clock), .reset(resetSync),
                  .csr(csrInt[1]), .csrFb(csrIntFb[1]),
                  .axil(axil), .axilFb(axilFb));

    xip_iic uIP (
                 .s_axi_aclk(clock), .s_axi_aresetn(!resetSync),
                 .sda_i(iicSda), .sda_o(), .sda_t(offloadSdaTristate),
                 .scl_i(iicScl), .scl_o(), .scl_t(offloadSclTristate),
                 .s_axi_awaddr(axil.awaddr[8:0]),
                 .s_axi_awvalid(axil.awvalid), .s_axi_awready(axilFb.awready),
                 .s_axi_wdata(axil.wdata), .s_axi_wstrb(axil.wstrb),
                 .s_axi_wvalid(axil.wvalid), .s_axi_wready(axilFb.wready),
                 .s_axi_araddr(axil.araddr[8:0]),
                 .s_axi_arvalid(axil.arvalid), .s_axi_arready(axilFb.arready),
                 .s_axi_bresp(axilFb.bresp),
                 .s_axi_bvalid(axilFb.bvalid), .s_axi_bready(axil.bready),
                 .s_axi_rdata(axilFb.rdata), .s_axi_rresp(axilFb.rresp),
                 .s_axi_rvalid(axilFb.rvalid), .s_axi_rready(axil.rready),
                 .iic2intc_irpt(offloadInterrupt), .gpo(offloadDebug)
                 );

    assign iicSclTristate = (csrSclManual ? csrSclTristate : offloadSclTristate);
    assign iicSdaTristate = (csrSdaManual ? csrSdaTristate : offloadSdaTristate);

  `ifdef OC_IIC_INCLUDE_ILA_DEBUG
    `OC_DEBUG_ILA(uILA, clock, 8192, 128, 32,
                  { resetSync,
                    axil, axilFb,
                    offloadSdaTristate, offloadSclTristate,
                    csrSdaManual, csrSclManual,
                    iicSdaTristate, iicSclTristate,
                    csrSdaIn, csrSclIn },
                  { resetSync,
                    iicSdaTristate, iicSclTristate,
                    csrSdaIn, csrSclIn });
  `endif

`else
    `OC_STATIC_ERROR("Only support OffloadEnable in IIC for OC_LIBRARY_ULTRASCALE_PLUS");
`endif
  end
  else begin
    assign iicSclTristate = csrSclTristate;
    assign iicSdaTristate = csrSdaTristate;
    assign offloadDebug = 1'b0;
    assign offloadInterrupt = 1'b0;
`ifdef OC_IIC_INCLUDE_ILA_DEBUG
    `OC_DEBUG_ILA(uILA, clock, 8192, 128, 32,
                  { resetSync,
                    iicSdaTristate, iicSclTristate,
                    csrSdaIn, csrSclIn },
                  { resetSync,
                    iicSdaTristate, iicSclTristate,
                    csrSdaIn, csrSclIn });
`endif

  end

endmodule // oc_iic
