// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_pcie
  #(
    parameter integer Instance = 0,
    parameter integer PcieWidth = 1,
    parameter bit     AxilEnable = oclib_pkg::True,
    parameter         type AxilType = oclib_pkg::axil_32_s,
    parameter         type AxilFbType = oclib_pkg::axil_32_fb_s,
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter         type CsrProtocol = oclib_pkg::csr_32_s,
    parameter int     SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter int     ResetPipeline = 0

    )
  (
   input                  clock,
   input                  reset,
   output [PcieWidth-1:0] txP,
   output [PcieWidth-1:0] txN,
   input [PcieWidth-1:0]  rxP,
   input [PcieWidth-1:0]  rxN,
   input                  clockRefP,
   input                  clockRefN,
   input                  pcieReset,
    // AXI-Lite interface for CSR access to TOP/USER
   output logic           clockAxil,
   output logic           resetAxil,
   output                 AxilType axil,
   input                  AxilFbType axilFb,
   // CSR bus input for PCIe macro control/status
   input                  CsrType csr,
   output                 CsrFbType csrFb
   );

  logic                             resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

`ifdef OC_LIBRARY_ULTRASCALE_PLUS

  // clock/reset
  logic                             sys_clk;
  logic                             sys_clk_gt;

  // ODIV2 is not actually divided by two, it's just driven out of the SERDES for external use
  IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00))
  refclk_ibuf (.O(sys_clk_gt), .ODIV2(sys_clk), .I(clockRefP), .CEB(1'b0), .IB(clockRefN));


  logic                             clockAxi;
  logic                             resetAxiN, resetAxi;
  logic                             resetAxiSync, resetAxiSeen, resetAxiAck;

  logic                             resetAxiControlN, resetAxiControl;
  logic                             resetAxiControlSync, resetAxiControlSeen, resetAxiControlAck;

  // control signals
  logic                             soft_sys_reset;

  // status signals
  logic [5:0]                       cfg_ltssm_state;
  logic                             user_lnk_up;

  localparam                        Spaces = 2;

  // *** Convert incoming CSR type into two spaces: local csr and a DRP for the PLL IP

  localparam                        type CsrIntType = oclib_pkg::csr_32_s;
  localparam                        type CsrIntFbType = oclib_pkg::csr_32_fb_s;
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

  // Not sure how this Type thing is going to work here.  Should it name the hard block (which has all the DRP stuff etc)
  // or the IP wrapper.  At first we don't have much IP but eventually QDMA etc.   So I think it needs to ID the IP?
  // but there's a lot of variables, we should support any kind of IP that has the right ports (i.e. we should not care
  // if board and/or user decides to build more features internal to the block (outstanding requests etc).
  // One thought would be to have just enough info here (in 8-bit) to move forward.  I.e. this is a Xilinx XDMA of some
  // kind.  Then we put a CSR/ROM block that gives all the info IT TURNS OUT WE NEED (i.e. let's not just start throwing
  // stuff in, to have the cool printouts in CLI, let's think about driver needs to actually operate the IP ... XDMA
  // itself may have enough status regs (are feature x, y, z, enabled) to get what is needed.  In general these IPs
  // have drivers, and hopefully those drivers are designed to interrogate the device and adapt (for sanity sake) vs
  // having features compiled in or enabled via run-time switches.

  localparam logic [7:0]            PcieType = 8'd1; // PCIE40E4
  localparam integer                NumCsr = 3;
  localparam logic [31:0]           CsrId = { oclib_pkg::CsrIdPcie,
                                              PcieType, 4'($clog2(PcieWidth)), 4'(Instance) };

  logic [0:NumCsr-1] [31:0]         csrOut;
  logic [0:NumCsr-1] [31:0]         csrIn;
  logic [0:NumCsr-1]                csrWrite;
  logic [0:NumCsr-1]                csrRead;

    // 0 : CSR ID
    //   [ 3: 0] Instance
    //   [ 7: 4] PcieWidth
    //   [15: 8] PcieType
    //   [31:16] csrId
    // 1 : Reset
    //   [    0] softReset
    // 2 : Status
    //   [ 5: 0] ltssmState
    //   [   31] linkUp

  oclib_csr_array #(.CsrType(CsrIntType), .CsrFbType(CsrIntFbType),
                    .NumCsr(NumCsr),
                    .CsrRwBits   ({ 32'h00000000, 32'h00000001, 32'h00000000 }),
                    .CsrRoBits   ({ 32'h00000000, 32'h00000000, 32'h8000001f }),
                    .CsrFixedBits({ 32'hffffffff, 32'h00000000, 32'h00000000 }),
                    .CsrInitBits ({        CsrId, 32'h00000000, 32'h00000000 }) )
  uCSR (.clock(clock), .reset(resetSync),
        .csr(csrInt[0]), .csrFb(csrIntFb[0]),
        .csrRead(csrRead), .csrWrite(csrWrite),
        .csrOut(csrOut), .csrIn(csrIn));

  // ADDR 1 - Reset
  assign soft_sys_reset = csrOut[1][0];
  assign resetAxiAck = csrOut[1][9] && csrWrite[1]; // clear when written 1, maybe we'll put this function into csr_array...
  assign resetAxiControlAck = csrOut[1][11] && csrWrite[1];
  // ADDR 2 - Status (these are synchronized by csr_array)
  // ADDR 3 - Interrupt

  always_comb begin
    csrIn = '0;
    // ADDR 1 - Reset
    csrIn[1][8] = resetAxiSync;
    csrIn[1][9] = resetAxiSeen;
    csrIn[1][10] = resetAxiControlSync;
    csrIn[1][11] = resetAxiControlSeen;
    // ADDR 2 - Status (these are synchronized by csr_array)
    csrIn[2][21:16] = cfg_ltssm_state;
    csrIn[2][24] = user_lnk_up;
  end

  // these are coming from the AXI domain, and we sync over.  For now we assume we won't miss
  // a reset pulse (it's wide enough to be seen in "clock") but it really should be a pulse
  // synchronizer of some kind
  assign resetAxi = !resetAxiN; // not sure what/how we are going to use this
  assign resetAxiControl = !resetAxiControlN; // not sure what/how we are going to use this

  oclib_synchronizer #(.Width(2), .SyncCycles(SyncCycles))
  uRESET_AXI_SYNC(.clock(clock), .in({resetAxiControl, resetAxi}), .out({resetAxiControlSync, resetAxiSync}));

  always @(posedge clock) begin
    resetAxiSeen <= (resetSync ? 1'b0 : (resetAxiSync || (resetAxiSeen && !resetAxiAck)));
    resetAxiControlSeen <= (resetSync ? 1'b0 : (resetAxiSync || (resetAxiControlSeen && !resetAxiControlAck)));
  end

  // Implement address space 1

  AxilType csrAxil;
  AxilFbType csrAxilFb;

  oclib_csr_adapter #(.CsrInType(CsrIntType), .CsrInFbType(CsrIntFbType),
                      .CsrOutType(AxilType), .CsrOutFbType(AxilFbType),
                      .UseClockOut(oclib_pkg::True))
  uCSR_TO_CSRAXIL (.clock(clock), .reset(resetSync),
                   .clockOut(clockAxil), .resetOut(resetAxil),
                   .in(csrInt[1]), .inFb(csrIntFb[1]),
                   .out(csrAxil), .outFb(csrAxilFb));


  /* Interrupt Handling Logic (TBD) */


  /* IP Instantiation */

  // these will be setup by importing IP TCL (which in OpenChip can setup defines for the project)
  `OC_IFNDEFDEFINE_TO(OC_IP_PCIE_0_MODULE,xip_pcie_bridge_x1_0)
  `OC_IFNDEFDEFINE_TO(OC_IP_PCIE_1_MODULE,xip_pcie_bridge_x1_1)

  localparam type AxiBridgeMasterType   = `OC_VAL_ASDEFINED_ELSE(OC_IP_PCIE_M_AXIB_TYPE,oclib_pkg::axi4m_64_s);
  localparam type AxiBridgeMasterFbType = `OC_VAL_ASDEFINED_ELSE(OC_IP_PCIE_M_AXIB_FB_TYPE,oclib_pkg::axi4m_64_fb_s);
  AxiBridgeMasterType ipAxiBridgeMaster;
  AxiBridgeMasterFbType ipAxiBridgeMasterFb;

  `define OC_LOCAL_MODULE_CONNECTIONS \
  .sys_clk(sys_clk), \
  .sys_clk_gt(sys_clk_gt), \
  .sys_rst_n(!(pcieReset || soft_sys_reset)), \
  .cfg_ltssm_state(cfg_ltssm_state), \
  .user_lnk_up(user_lnk_up), \
  .pci_exp_txp(txP[PcieWidth-1:0]), \
  .pci_exp_txn(txN[PcieWidth-1:0]), \
  .pci_exp_rxp(rxP[PcieWidth-1:0]), \
  .pci_exp_rxn(rxN[PcieWidth-1:0]), \
  .axi_aclk(clockAxi), \
  .axi_aresetn(resetAxiN), \
  .axi_ctl_aresetn(resetAxiControlN), \
  .usr_irq_req('0), \
  .usr_irq_ack(), \
  .msi_enable(), \
  .msi_vector_width(), \
  .m_axib_awid(ipAxiBridgeMaster.aw.id), \
  .m_axib_awaddr(ipAxiBridgeMaster.aw.addr), \
  .m_axib_awlen(ipAxiBridgeMaster.aw.len), \
  .m_axib_awsize(ipAxiBridgeMaster.aw.size), \
  .m_axib_awburst(ipAxiBridgeMaster.aw.burst), \
  .m_axib_awprot(ipAxiBridgeMaster.aw.prot), \
  .m_axib_awvalid(ipAxiBridgeMaster.awvalid), \
  .m_axib_awready(ipAxiBridgeMasterFb.awready), \
  .m_axib_awlock(ipAxiBridgeMaster.aw.lock), \
  .m_axib_awcache(ipAxiBridgeMaster.aw.cache), \
  .m_axib_wdata(ipAxiBridgeMaster.w.data), \
  .m_axib_wstrb(ipAxiBridgeMaster.w.strb), \
  .m_axib_wlast(ipAxiBridgeMaster.w.last), \
  .m_axib_wvalid(ipAxiBridgeMaster.wvalid), \
  .m_axib_wready(ipAxiBridgeMasterFb.wready), \
  .m_axib_bid(ipAxiBridgeMasterFb.b.id), \
  .m_axib_bresp(ipAxiBridgeMasterFb.b.resp), \
  .m_axib_bvalid(ipAxiBridgeMasterFb.bvalid), \
  .m_axib_bready(ipAxiBridgeMaster.bready), \
  .m_axib_arid(ipAxiBridgeMaster.ar.id), \
  .m_axib_araddr(ipAxiBridgeMaster.ar.addr), \
  .m_axib_arlen(ipAxiBridgeMaster.ar.len), \
  .m_axib_arsize(ipAxiBridgeMaster.ar.size), \
  .m_axib_arburst(ipAxiBridgeMaster.ar.burst), \
  .m_axib_arprot(ipAxiBridgeMaster.ar.prot), \
  .m_axib_arvalid(ipAxiBridgeMaster.arvalid), \
  .m_axib_arready(ipAxiBridgeMasterFb.arready), \
  .m_axib_arlock(ipAxiBridgeMaster.ar.lock), \
  .m_axib_arcache(ipAxiBridgeMaster.ar.cache), \
  .m_axib_rid(ipAxiBridgeMasterFb.r.id), \
  .m_axib_rdata(ipAxiBridgeMasterFb.r.data), \
  .m_axib_rresp(ipAxiBridgeMasterFb.r.resp), \
  .m_axib_rlast(ipAxiBridgeMasterFb.r.last), \
  .m_axib_rvalid(ipAxiBridgeMasterFb.rvalid), \
  .m_axib_rready(ipAxiBridgeMaster.rready), \
  .s_axil_awaddr(csrAxil.awaddr), \
  .s_axil_awprot('0), \
  .s_axil_awvalid(csrAxil.awvalid), \
  .s_axil_awready(csrAxilFb.awready), \
  .s_axil_wdata(csrAxil.wdata), \
  .s_axil_wstrb(csrAxil.wstrb), \
  .s_axil_wvalid(csrAxil.wvalid), \
  .s_axil_wready(csrAxilFb.wready), \
  .s_axil_bvalid(csrAxilFb.bvalid), \
  .s_axil_bresp(csrAxilFb.bresp), \
  .s_axil_bready(csrAxil.bready), \
  .s_axil_araddr(csrAxil.araddr), \
  .s_axil_arprot('0), \
  .s_axil_arvalid(csrAxil.arvalid), \
  .s_axil_arready(csrAxilFb.arready), \
  .s_axil_rdata(csrAxilFb.rdata), \
  .s_axil_rresp(csrAxilFb.rresp), \
  .s_axil_rvalid(csrAxilFb.rvalid), \
  .s_axil_rready(csrAxil.rready), \
  .interrupt_out(), \
  .s_axib_awid('0), \
  .s_axib_awaddr('0), \
  .s_axib_awregion('0), \
  .s_axib_awlen('0), \
  .s_axib_awsize('0), \
  .s_axib_awburst('0), \
  .s_axib_awvalid('0), \
  .s_axib_wdata('0), \
  .s_axib_wstrb('0), \
  .s_axib_wlast('0), \
  .s_axib_wvalid('0), \
  .s_axib_bready('0), \
  .s_axib_arid('0), \
  .s_axib_araddr('0), \
  .s_axib_arregion('0), \
  .s_axib_arlen('0), \
  .s_axib_arsize('0), \
  .s_axib_arburst('0), \
  .s_axib_arvalid('0), \
  .s_axib_rready('0), \
  .s_axib_awready(), \
  .s_axib_wready(), \
  .s_axib_bid(), \
  .s_axib_bresp(), \
  .s_axib_bvalid(), \
  .s_axib_arready(), \
  .s_axib_rid(), \
  .s_axib_rdata(), \
  .s_axib_rresp(), \
  .s_axib_rlast(), \
  .s_axib_rvalid()

  if (`OC_VAL_IFDEF(SIMULATION)) begin : sim_model

    // in sim, we fake out the IP with transactors
    ocsim_clock #(.ClockHz(125_000_000))
    uSIM_CLOCK_AXI (.clock(clockAxi));

    ocsim_reset #(.StartupResetCycles(100), .ActiveLow(oclib_pkg::True))
    uSIM_RESET_AXI (.clock(clockAxi), .reset(resetAxiN));

    ocsim_reset #(.StartupResetCycles(120), .ActiveLow(oclib_pkg::True))
    uSIM_RESET_AXI_CONTROL (.clock(clockAxi), .reset(resetAxiControlN));

    ocsim_axim_source #(.AxiType(AxiBridgeMasterType), .AxiFbType(AxiBridgeMasterFbType))
    uSIM_AXIM_SOURCE (.clock(clockAxi), .reset(resetAxi),
                      .axi(ipAxiBridgeMaster), .axiFb(ipAxiBridgeMasterFb));

  end else if (Instance==0) begin : i0
    `OC_IP_PCIE_0_MODULE uIP ( `OC_LOCAL_MODULE_CONNECTIONS );
  end else if (Instance==1) begin : i1
    `OC_IP_PCIE_1_MODULE uIP ( `OC_LOCAL_MODULE_CONNECTIONS );
  end else begin
    `OC_STATIC_ERROR("Only support up to 2 PCIEs currently");
  end

  assign clockAxil = clockAxi;
  assign resetAxil = resetAxi;

  /* convert the bridge's output into AXIL */
  oclib_axim_to_axil #(.InType(AxiBridgeMasterType), .InFbType(AxiBridgeMasterFbType),
                       .OutType(AxilType), .OutFbType(AxilFbType))
  uIPAXI_TO_IPAXIL (.clock(clockAxil), .reset(resetAxil),
                    .in(ipAxiBridgeMaster), .inFb(ipAxiBridgeMasterFb),
                    .out(axil), .outFb(axilFb));

  /* debug ILA */

  `ifdef OC_PCIE_INCLUDE_ILA_DEBUG

  logic [7:0] clockCount;
  always_ff @(posedge clock) clockCount <= (clockCount + 1);
  logic [7:0] clockAxilCount;
  always_ff @(posedge clockAxil) clockAxilCount <= (clockAxilCount + 1);

  `OC_DEBUG_ILA(uILA0, clock, 1024, 128, 32,
                { csr, csrFb, clockCount, clockAxilCount },
                { cfg_ltssm_state, user_lnk_up,
                  resetAxil, resetAxiN, resetAxiControlN, pcieReset, soft_sys_reset, reset  });

  `OC_DEBUG_ILA(uILA1, clockAxil, 1024, 512, 32,
                { ipAxiBridgeMaster, ipAxiBridgeMasterFb, axil, axilFb, clockCount, clockAxilCount },
                { ipAxiBridgeMaster.arvalid, ipAxiBridgeMaster.awvalid,
                  ipAxiBridgeMasterFb.rvalid, ipAxiBridgeMasterFb.bvalid,
                  cfg_ltssm_state, user_lnk_up,
                  resetAxil, resetAxiN, resetAxiControlN, pcieReset, soft_sys_reset, reset });

  `endif // OC_PCIE_INCLUDE_ILA_DEBUG

`else // !`ifdef OC_LIBRARY_ULTRASCALE_PLUS
  // OC_LIBRARY_BEHAVIORAL

  // When we don't have a library defined, we cannot have PCIe, so we default to a CSR array indicating 'NONE',
  // but we shouldn't ever be hitting this case in a physical chip, just COS level simulation can be done, and
  // we should add tasks here to exercise any external interfaces.

  // This is different from the SIMULATION code above, where a library was defined, but we don't have a good
  // model of the IP (or it's link partner), so we were emulating a specific IP to exercise the logic around it.
  // So above, we emulate AXI-M interface coming out of the XIP; here we'd emulate AXIL coming out of OC_PCIE.

  localparam logic [7:0]            PcieType = 8'd0; // NONE
  localparam integer                NumCsr = 1;
  localparam logic [31:0]           CsrId = { oclib_pkg::CsrIdPcie,
                                              PcieType, 4'($clog2(PcieWidth)), 4'(Instance) };

    // 0 : CSR ID
    //   [ 3: 0] Instance
    //   [ 7: 4] PcieWidth
    //   [15: 8] PcieType
    //   [31:16] csrId

  oclib_csr_array #(.CsrType(CsrType), .CsrFbType(CsrFbType),
                    .NumCsr(NumCsr),
                    .CsrRwBits   ({ 32'h00000000 }),
                    .CsrRoBits   ({ 32'h00000000 }),
                    .CsrFixedBits({ 32'hffffffff }),
                    .CsrInitBits ({        CsrId }) )
  uCSR (.clock(clock), .reset(resetSync),
        .csr(csr), .csrFb(csrFb),
        .csrRead(), .csrWrite(),
        .csrOut(), .csrIn('0));

  // we should match the hierarchy names for behavioral and vendor library cases, so testbench stays clean
  if (`OC_VAL_IFDEF(SIMULATION)) begin : sim_model

    localparam type AxiBridgeMasterType   = `OC_VAL_ASDEFINED_ELSE(OC_IP_PCIE_M_AXIB_TYPE,oclib_pkg::axi4m_64_s);
    localparam type AxiBridgeMasterFbType = `OC_VAL_ASDEFINED_ELSE(OC_IP_PCIE_M_AXIB_FB_TYPE,oclib_pkg::axi4m_64_fb_s);
    AxiBridgeMasterType ipAxiBridgeMaster;
    AxiBridgeMasterFbType ipAxiBridgeMasterFb;

    // in sim, we fake out the IP with transactors
    ocsim_clock #(.ClockHz(125_000_000))
    uSIM_CLOCK_AXI (.clock(clockAxi));

    ocsim_reset #(.StartupResetCycles(100), .ActiveLow(oclib_pkg::True))
    uSIM_RESET_AXI (.clock(clockAxi), .reset(resetAxiN));

    ocsim_reset #(.StartupResetCycles(120), .ActiveLow(oclib_pkg::True))
    uSIM_RESET_AXI_CONTROL (.clock(clockAxi), .reset(resetAxiControlN));

    ocsim_axim_source #(.AxiType(AxiBridgeMasterType), .AxiFbType(AxiBridgeMasterFbType))
    uSIM_AXIM_SOURCE (.clock(clockAxi), .reset(resetAxi),
                      .axi(ipAxiBridgeMaster), .axiFb(ipAxiBridgeMasterFb));

    assign resetAxi = !resetAxiN; // not sure what/how we are going to use this
    assign resetAxiControl = !resetAxiControlN; // not sure what/how we are going to use this
    assign clockAxil = clockAxi;
    assign resetAxil = resetAxi;

    /* convert the bridge's output into AXIL */
    oclib_axim_to_axil #(.InType(AxiBridgeMasterType), .InFbType(AxiBridgeMasterFbType),
                         .OutType(AxilType), .OutFbType(AxilFbType))
    uIPAXI_TO_IPAXIL (.clock(clockAxil), .reset(resetAxil),
                      .in(ipAxiBridgeMaster), .inFb(ipAxiBridgeMasterFb),
                      .out(axil), .outFb(axilFb));

  end
  else begin
  `OC_STATIC_WARNING("Not in SIMULATION, and don't have a valid OC_LIBRARY that supports PCIe");
  end

  // OC_LIBRARY_BEHAVIORAL
`endif // !`ifdef OC_LIBRARY_ULTRASCALE_PLUS


endmodule // oc_pcie
