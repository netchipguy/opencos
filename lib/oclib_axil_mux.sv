
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_axil_mux #(
                        parameter     type AxilType = oclib_pkg::axil_32_s,
                        parameter     type AxilFbType = oclib_pkg::axil_32_fb_s,
                        localparam int InCount = 2
                        )
  (
   input clock,
   input reset,
   input AxilType in [InCount-1:0],
   output AxilFbType inFb [InCount-1:0],
   output AxilType out,
   input AxilFbType outFb
   );

  localparam int AddressWidth = $bits(in[0].awaddr);
  localparam int DataWidth = $bits(in[0].wdata);

  ocext_axil_interconnect #(.S_COUNT(2),
                            .M_COUNT(1),
                            .DATA_WIDTH(DataWidth),
                            .ADDR_WIDTH(AddressWidth))
  uAXIL_INTERCONNECT (.clk(clock),
                      .rst(reset),
                      .s_axil_awaddr({in[1].awaddr,in[0].awaddr}),
                      .s_axil_awprot({in[1].awprot,in[0].awprot}),
                      .s_axil_awvalid({in[1].awvalid,in[0].awvalid}),
                      .s_axil_awready({inFb[1].awready,inFb[0].awready}),
                      .s_axil_wdata({in[1].wdata,in[0].wdata}),
                      .s_axil_wstrb({in[1].wstrb,in[0].wstrb}),
                      .s_axil_wvalid({in[1].wvalid,in[0].wvalid}),
                      .s_axil_wready({inFb[1].wready,inFb[0].wready}),
                      .s_axil_bresp({inFb[1].bresp,inFb[0].bresp}),
                      .s_axil_bvalid({inFb[1].bvalid,inFb[0].bvalid}),
                      .s_axil_bready({in[1].bready,in[0].bready}),
                      .s_axil_araddr({in[1].araddr,in[0].araddr}),
                      .s_axil_arprot({in[1].arprot,in[0].arprot}),
                      .s_axil_arvalid({in[1].arvalid,in[0].arvalid}),
                      .s_axil_arready({inFb[1].arready,inFb[0].arready}),
                      .s_axil_rdata({inFb[1].rdata,inFb[0].rdata}),
                      .s_axil_rresp({inFb[1].rresp,inFb[0].rresp}),
                      .s_axil_rvalid({inFb[1].rvalid,inFb[0].rvalid}),
                      .s_axil_rready({in[1].rready,in[0].rready}),
                      .m_axil_awaddr(out.awaddr),
                      .m_axil_awprot(out.awprot),
                      .m_axil_awvalid(out.awvalid),
                      .m_axil_awready(outFb.awready),
                      .m_axil_wdata(out.wdata),
                      .m_axil_wstrb(out.wstrb),
                      .m_axil_wvalid(out.wvalid),
                      .m_axil_wready(outFb.wready),
                      .m_axil_bresp(outFb.bresp),
                      .m_axil_bvalid(outFb.bvalid),
                      .m_axil_bready(out.bready),
                      .m_axil_araddr(out.araddr),
                      .m_axil_arprot(out.arprot),
                      .m_axil_arvalid(out.arvalid),
                      .m_axil_arready(outFb.arready),
                      .m_axil_rdata(outFb.rdata),
                      .m_axil_rresp(outFb.rresp),
                      .m_axil_rvalid(outFb.rvalid),
                      .m_axil_rready(out.rready));

endmodule // oclib_axil_mux
