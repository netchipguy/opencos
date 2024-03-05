
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_axim_to_axil #(
                            parameter type InType = oclib_pkg::axi4m_32_s,
                            parameter type InFbType = oclib_pkg::axi4m_32_fb_s,
                            parameter type OutType = oclib_pkg::axil_32_s,
                            parameter type OutFbType = oclib_pkg::axil_32_fb_s
                            )
  (
   input  clock,
   input  reset,
   input  InType in,
   output InFbType inFb,
   output OutType out,
   input  OutFbType outFb
   );

//  localparam ADDR_WIDTH = $bits(out.awaddr); // we set addr width based on AXIL needs
  localparam ADDR_WIDTH = 32;
  localparam AXI_DATA_WIDTH = $bits(in.w.data);
  localparam AXI_ID_WIDTH = $bits(in.aw.id);
//  localparam AXIL_DATA_WIDTH = $bits(out.wdata);
  localparam AXIL_DATA_WIDTH = 32;

  ocext_axi_axil_adapter #(.ADDR_WIDTH(ADDR_WIDTH),
                           .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
                           .AXI_ID_WIDTH(AXI_ID_WIDTH),
                           .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH))
  uAXI_AXIL (.clk(clock),
             .rst(reset),
             // AXI slave interface
             .s_axi_awid(in.aw.id),
             .s_axi_awaddr(in.aw.addr[ADDR_WIDTH-1:0]),
             .s_axi_awlen(in.aw.len),
             .s_axi_awsize(in.aw.size),
             .s_axi_awburst(in.aw.burst),
             .s_axi_awlock(in.aw.lock),
             .s_axi_awcache(in.aw.cache),
             .s_axi_awprot(in.aw.prot),
             .s_axi_awvalid(in.awvalid),
             .s_axi_awready(inFb.awready),
             .s_axi_wdata(in.w.data),
             .s_axi_wstrb(in.w.strb),
             .s_axi_wlast(in.w.last),
             .s_axi_wvalid(in.wvalid),
             .s_axi_wready(inFb.wready),
             .s_axi_bid(inFb.b.id),
             .s_axi_bresp(inFb.b.resp),
             .s_axi_bvalid(inFb.bvalid),
             .s_axi_bready(in.bready),
             .s_axi_arid(in.ar.id),
             .s_axi_araddr(in.ar.addr[ADDR_WIDTH-1:0]),
             .s_axi_arlen(in.ar.len),
             .s_axi_arsize(in.ar.size),
             .s_axi_arburst(in.ar.burst),
             .s_axi_arlock(in.ar.lock),
             .s_axi_arcache(in.ar.cache),
             .s_axi_arprot(in.ar.prot),
             .s_axi_arvalid(in.arvalid),
             .s_axi_arready(inFb.arready),
             .s_axi_rid(inFb.r.id),
             .s_axi_rdata(inFb.r.data),
             .s_axi_rresp(inFb.r.resp),
             .s_axi_rlast(inFb.r.last),
             .s_axi_rvalid(inFb.rvalid),
             .s_axi_rready(in.rready),
             // AXI lite master interface
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
             .m_axil_rready(out.rready)
             );

endmodule // oclib_axim_to_axil
