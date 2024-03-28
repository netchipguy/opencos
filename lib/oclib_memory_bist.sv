
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

`define OCLIB_MEMORY_BIST_VERSION 32'h80000000

module oclib_memory_bist #(
                           parameter int CsrToPortFlops = 2,
                           parameter     type AxilType = oclib_pkg::axil_32_s,
                           parameter     type AxilFbType = oclib_pkg::axil_32_fb_s,
                           parameter int AxilClockFreq = 100000000, // used for the uptime counters
                           parameter     type AximType = oclib_pkg::axi4m_256_s,
                           parameter     type AximFbType = oclib_pkg::axi4m_256_fb_s,
                           parameter int AximPorts = 4,
                           parameter int AximPortRetimers = 0, // add retiming stages between port logic and HBM port
                           parameter int AximPortFifoDepth = 32, // add skid FIFO between AXIM datapath and traffic gen/check (req)
                           parameter int ConfigPipeStages = 0,
                           parameter int StatusPipeStages = 0,
                           parameter int SyncCycles = 3,
                           parameter bit ResetSync = oclib_pkg::True,
                           parameter int ResetPipeline = 2
                           )
  (
   // GLOBALS
   input  reset,

   // AXIL CSR
   input  clockAxil,
   input  AxilType axil,
   output AxilFbType axilFb,

   // AXIM MEMORY PORTS
   input  clockAxim,
   output AximType [AximPorts-1:0] axim,
   input  AximFbType [AximPorts-1:0] aximFb
   );

  localparam int AximAddressWidth = oclib_memory_bist_pkg::MaxAddressWidth;
  localparam int AximDataWidth = $bits(axim[0].w.data);

  // *** synchronize reset into two domains

  logic                            resetAxil;
  logic                            resetAxim;
  logic [AximPorts-1:0]            resetAximPort;

  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET_AXIL (.clock(clockAxil), .in(reset), .out(resetAxil));

  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET_AXIM (.clock(clockAxim), .in(reset), .out(resetAxim));

  for (genvar i=0; i<AximPorts; i++) begin : axim_port_reset
    oclib_pipeline #(.Length(2), .DontTouch(oclib_pkg::True))
    uRESET_AXIM_PORT (.clock(clockAxim), .in(resetAxim), .out(resetAximPort[i]));
  end

  // *** lightweight AXI-Lite CSR logic

  oclib_memory_bist_pkg::cfg_s     csr_cfg;
  oclib_memory_bist_pkg::sts_s     csr_sts;

  oclib_memory_bist_csrs #(
                           .AxilType(AxilType), .AxilFbType(AxilFbType),
                           .AximAddressWidth(AximAddressWidth), .AximDataWidth(AximDataWidth),
                           .AxilClockFreq(AxilClockFreq)
                           )
  uCSRS (// AXIL
         .clockAxil(clockAxil), .resetAxil(resetAxil),
         .axil(axil), .axilFb(axilFb),
         // CONFIG/STATUS (AXI DOMAIN)
         .clockAxim(clockAxim), .resetAxim(resetAxim),
         .cfg(csr_cfg), .sts(csr_sts)
         );

  // *** pipeline CFG bus over to PORT[0] area

  oclib_memory_bist_pkg::cfg_s     port_cfg [AximPorts-1:0]; // port_cfg[0] is cfg going IN to port logic #0

  oclib_pipeline #(.Width($bits(csr_cfg)), .Length(CsrToPortFlops))
  uCFG_PIPE (.clock(clockAxim), .in(csr_cfg), .out(port_cfg[0]));

  // *** pipeline CFG bus across from PORT[0] to [N]

  if (AximPorts>1) begin
    for (genvar p=1; p<AximPorts; p++) begin
      always_ff @(posedge clockAxim) begin
        port_cfg[p] <= port_cfg[p-1];
      end
    end
  end

  // *** instantiate the PORT engines

  oclib_memory_bist_pkg::sts_s     port_sts [AximPorts-1:0]; // port_sts_local[0] is sts coming OUT engine 0

  for (genvar p=0; p<AximPorts; p++) begin
    oclib_memory_bist_axim #(.PortNumber(p),
                             .AximType(AximType), .AximFbType(AximFbType),
                             .AximAddressWidth(AximAddressWidth), .AximDataWidth(AximDataWidth),
                             .AximPortRetimers(AximPortRetimers), .AximPortFifoDepth(AximPortFifoDepth),
                             .ConfigPipeStages(ConfigPipeStages), .StatusPipeStages(StatusPipeStages))
    uAXIM (.clockAxim(clockAxim), .resetAxim(resetAximPort[p]),
           .cfg(port_cfg[p]), .sts(port_sts[p]),
           .axim(axim[p]), .aximFb(aximFb[p]) );
  end

  // *** pipeline STS bus back from PORT[N] .. [0]

  oclib_memory_bist_pkg::sts_s     port_sts_pipe [AximPorts-1:0]; // [0] is sts OUT from block 0 (incl port[0] + [1] ...)

  for (genvar p=0; p<AximPorts; p++) begin

    oclib_memory_bist_pkg::sts_s   port_sts_in; // port status coming from upstream
    oclib_memory_bist_pkg::sts_s   port_sts_local; // port status from local engine
    oclib_memory_bist_pkg::sts_s   port_sts_out; // port status going to downstream

    // combinationally combine the engine status with the upstream status, which both come from flops, to go into output flop
    always_comb begin
      port_sts_local = port_sts[p];
      port_sts_in = '0;
      port_sts_out = '0;
      if (p == (AximPorts-1)) begin
        // default inputs to 0 for highest numbered port, there is no "from upstream"
        port_sts_in.done = 1'b1; // except for done bit, pretend that's asserted :)
      end
      else begin
        port_sts_in = port_sts_pipe[p+1]; // for all other ports, the input is driven from the next higher port
      end
      if (port_cfg[p].axim_enable[p]) begin
        // this port is enabled, combine our status with what's coming from upstream
        port_sts_out = (port_sts_in | port_sts_local); // we OR together our two status except for fields below
        port_sts_out.done = (port_sts_in.done & port_sts_local.done); // done when ALL are done
        port_sts_out.rdata = ((port_cfg[p].sts_port_select == p) ? port_sts_local.rdata : port_sts_in.rdata);
      end
      else begin
        port_sts_out = port_sts_in; // port is disabled, just pass on from upstream
      end
    end

    // send sts back along the pipeline
    always_ff @(posedge clockAxim) begin
      port_sts_pipe[p] <= port_sts_out;
    end

  end

  // *** pipeline STS bus over from PORT[0] back to CSR area

  oclib_memory_bist_pkg::sts_s     csr_to_port_sts [CsrToPortFlops-1:0]; // pipe stages between CSR block and port 0

  oclib_pipeline #(.Width($bits(csr_sts)), .Length(CsrToPortFlops))
  uSTS_PIPE (.clock(clockAxim), .in(port_sts_pipe[0]), .out(csr_sts));

endmodule // oclib_metest


module oclib_memory_bist_axim #(
                               parameter int PortNumber = 0,
                               parameter     type AximType = oclib_pkg::axi4m_256_s,
                               parameter     type AximFbType = oclib_pkg::axi4m_256_fb_s,
                               parameter int AximAddressWidth = 0, // must be overridden
                               parameter int AximDataWidth = 0, // must be overridden
                               parameter int AximPortRetimers = 0, // add retiming stages between port logic and AXIM port
                               parameter int AximPortFifoDepth = 32, // add skid FIFO between AXIM datapath and traffic gen/check
                               parameter int ConfigPipeStages = 0,
                               parameter int StatusPipeStages = 0,
                               parameter int SyncCycles = 3,
                               parameter bit ResetSync = oclib_pkg::False,
                               parameter int ResetPipeline = 1
                               )
  (
   // GLOBALS
   input  clockAxim,
   input  resetAxim,

   // CONFIG / STATUS
   input  oclib_memory_bist_pkg::cfg_s cfg,
   output oclib_memory_bist_pkg::sts_s sts,

   // AXIM PORT
   output AximType axim,
   input  AximFbType aximFb
   );

  logic                             resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clockAxim), .in(resetAxim), .out(resetSync));

  // **********
  // optional retiming stages (if port engine is placed farther from AXIM port, say HBM)
  // **********

  AximType aximMid;
  AximFbType aximMidFb;

  oclib_axim_pipeline #(.AximType(AximType), .AximFbType(AximFbType), .Length(AximPortRetimers), .ResetPipeline(1))
  uAXIM_PIPE (.clock(clockAxim), .reset(resetSync),
              .in(aximMid), .inFb(aximMidFb), .out(axim), .outFb(aximFb));

  // **********
  // *** mandatory FIFO stages (decouple HBM port from memory test logic, local to memtest port engine)
  // **********

  AximType aximInt;
  AximFbType aximIntFb;
  logic aw_almost_full, w_almost_full, ar_almost_full;

  oclib_axim_fifo #(.AximType(AximType), .AximFbType(AximFbType), .Depth(AximPortFifoDepth), .ResetPipeline(1))
  uAXIM_FIFO (.clock(clockAxim), .reset(resetSync),
              .awAlmostFull(aw_almost_full), .wAlmostFull(w_almost_full),
              .arAlmostFull(ar_almost_full), .rAlmostFull(), .bAlmostFull(),
              .in(aximInt), .inFb(aximIntFb), .out(aximMid), .outFb(aximMidFb));

  // **********
  // *** optionally retime cfg/status signals
  // **********

  oclib_memory_bist_pkg::cfg_s                           cfg_local;
  oclib_pipeline #(.Width($bits(cfg_local)), .Length(ConfigPipeStages))
  uCFG_PIPE (.clock(clockAxim), .in(cfg), .out(cfg_local));

  oclib_memory_bist_pkg::sts_s                           sts_local;
  oclib_pipeline #(.Width($bits(sts_local)), .Length(StatusPipeStages))
  uSTS_PIPE (.clock(clockAxim), .in(sts_local), .out(sts));

  // **********
  // Generate shifted port address (kind of a per-port base address that is somewhat configurable)
  // **********

  logic [AximAddressWidth-1:0]                           port_address;
  always_ff @(posedge clockAxim) begin
    port_address <= ((PortNumber & cfg_local.address_port_mask) << cfg_local.address_port_shift);
  end

  // **********
  // Generate WRITE transactions
  // **********

  logic                                                  awvalid;
  logic [AximAddressWidth-1:0]                           awaddr;
  logic [7:0]                                            awid;
  logic [3:0]                                            awlen;
  logic                                                  wvalid;
  logic [oclib_pkg::Axi3DataWidth-1:0]                   wdata;
  logic                                                  wlast;

  assign aximInt.awvalid = awvalid;
  assign aximInt.aw.prot = 3'd0;
  assign aximInt.aw.id = awid; // single source ID for now
  assign aximInt.aw.addr = awaddr; // don't like to mix assign and flops into struct, buggy
  assign aximInt.aw.burst = 'd1; // INCR
  assign aximInt.aw.size = 'd5; // 2**5 = 32Byte
  assign aximInt.aw.len = awlen;
  assign aximInt.aw.lock = 1'd0;
  assign aximInt.aw.cache = 4'd0;

  assign aximInt.wvalid = wvalid;
  assign aximInt.w.data = wdata;
  assign aximInt.w.strb = {(oclib_pkg::Axi3DataWidth/8){1'b1}}; // all bytes writing
  assign aximInt.w.last = wlast; // 1-word bursts for now

  enum  logic [2:0] { WrIdle, WrBusy, WrBurst, WrWait, WrDone } write_state;
  logic [31:0]                                           write_count;
  logic [15:0]                                           write_wait_count;

  // cfg_write_mode
  // 0 : writing
  // 4 : randomize length
  // 5 : rotate write data
  // 6 : random write data

  logic [AximAddressWidth-1:0]                           awaddr_next;
  logic [AximAddressWidth-1:0]                           awaddr_next_next;
  logic [AximAddressWidth-1:0]                           awaddr_random;

  logic                                                  reset_random;
  always_ff @(posedge clockAxim) begin
    reset_random <= (resetSync || !cfg_local.go);
  end

  logic                                                  consume_aw_random;
  assign consume_aw_random = ((write_state == WrBusy) && !aw_almost_full && !w_almost_full);

  oclib_lfsr #(.Seed(PortNumber+100), .OutWidth(AximAddressWidth))
  uAWADDR_LFSR (.clock(clockAxim), .reset(reset_random), .enable(consume_aw_random), .out(awaddr_random));

  always_comb begin
    awaddr_next_next = (awaddr_next      + cfg_local.address_inc) & cfg_local.address_inc_mask;
    awaddr_next_next = (awaddr_next_next ^ (awaddr_random & cfg_local.address_random_mask));
    awaddr_next_next = (awaddr_next_next ^ port_address);
  end

  // compute next arlen
  logic [3:0]                                              awlen_next;
  logic [3:0]                                              awlen_random;

  oclib_lfsr #(.Seed(PortNumber+101), .OutWidth(4), .LfsrWidth(33))
  uAWLEN_LFSR (.clock(clockAxim), .reset(reset_random), .enable(consume_aw_random), .out(awlen_random));

  always_comb begin
    if (cfg_local.write_mode[4])  awlen_next = (awlen_random & cfg_local.burst_length);
    else                          awlen_next = cfg_local.burst_length;
  end

  logic [oclib_pkg::Axi3DataWidth-1:0]                   wdata_next;
  logic [32:0]                                           wdata_random; // we generate 33 random bits per cycle
  logic                                                  consume_w_random;
  assign consume_w_random = (((write_state == WrBusy) && !aw_almost_full && !w_almost_full) ||
                             ((write_state == WrBurst) && !w_almost_full));

  oclib_lfsr #(.Seed(PortNumber+102), .OutWidth(33))
  uWDATA_LFSR (.clock(clockAxim), .reset(reset_random), .enable(consume_w_random), .out(wdata_random));

  always_comb begin
    if (cfg_local.write_mode[6])       wdata_next = {wdata[oclib_pkg::Axi3DataWidth-34:0], wdata_random};
    else if (cfg_local.write_mode[5])  wdata_next = {wdata[oclib_pkg::Axi3DataWidth-2:0], wdata[oclib_pkg::Axi3DataWidth-1]};
    else                               wdata_next = wdata;
  end

  logic                                       cfg_go_delayed;
  always_ff @(posedge clockAxim) begin
    cfg_go_delayed <= cfg_local.go; // trigger one cycle later, so any values set same time as cfg_go can be computed before start
  end

  always_ff @(posedge clockAxim) begin
    if (resetSync) begin
      awvalid <= 1'b0;
      awid <= '0;
      awlen <= '0;
      wvalid <= 1'b0;
      awaddr_next <= '0;
      wlast <= 1'b0;
      write_state <= WrIdle;
      write_count <= '0;
      write_wait_count <= '0;
      wdata <= '0;
    end
    else begin
      awvalid <= 1'b0;
      wvalid <= 1'b0;
      if (awvalid) awid <= ((awid == cfg_local.write_max_id) ? '0 : (awid + 'd1));
      case (write_state)
        WrIdle: begin
          if (cfg_go_delayed && cfg_local.axim_enable[PortNumber]) begin
            write_state <= (cfg_local.write_mode[0] ? WrBusy : WrDone);
          end
          awaddr_next <= cfg_local.address ^ port_address;
          write_count <= '0;
          awid <= '0;
          wdata <= cfg_local.data;
        end
        WrBusy: begin
          if (!cfg_local.go) begin
            write_state <= WrIdle;
          end
          else begin
            if (!w_almost_full && !aw_almost_full) begin
              // we are doing a write
              awvalid <= 1'b1;
              wvalid <= 1'b1;
              wlast <= 1'b1;
              wdata <= wdata_next;
              awaddr <= awaddr_next;
              awaddr_next <= awaddr_next_next;
              awlen <= awlen_next;
              write_count <= (write_count + 1);
              if (awlen_next) begin
                write_state <= WrBurst;
                wlast <= 1'b0;
              end
              else if (cfg_local.op_count <= write_count) begin
                write_state <= WrDone;
              end
              else if (cfg_local.wait_states) begin
                write_state <= WrWait;
              end
            end
          end
          write_wait_count <= 'd1;
        end
        WrBurst: begin
          if (!cfg_local.go) begin
            write_state <= WrIdle;
          end
          else if (!w_almost_full) begin
            wvalid <= 1'b1;
            wdata <= wdata_next;
            if (write_wait_count >= awlen) begin
              // we are done with this burst
              wlast <= 1'b1;
              if (cfg_local.op_count < write_count) begin
                write_state <= WrDone;
              end
              else if (cfg_local.wait_states) begin
                write_state <= WrWait;
              end
              else begin
                write_state <= WrBusy;
              end
              write_wait_count <= 'd1;
            end
            else begin
              write_wait_count <= (write_wait_count + 'd1);
            end
          end
        end
        WrWait: begin
          if (!cfg_local.go) begin
            write_state <= WrIdle;
          end
          else if (write_wait_count >= cfg_local.wait_states) begin
            write_state <= WrBusy;
          end
          write_wait_count <= (write_wait_count + 'd1);
        end
        WrDone: begin
          if (!cfg_local.go) begin
            write_state <= WrIdle;
          end
        end
      endcase
    end
  end

  // **********
  // Generate READ transactions
  // **********

  logic                                                    arvalid;
  logic [AximAddressWidth-1:0]                             araddr;
  logic [7:0]                                              arid;
  logic [3:0]                                              arlen;

  assign aximInt.arvalid = arvalid;
  assign aximInt.ar.prot = 3'd0;
  assign aximInt.ar.id = arid; // single source ID for now
  assign aximInt.ar.addr = araddr;
  assign aximInt.ar.burst = 'd1; // INCR
  assign aximInt.ar.size = 'd5; // 2**5 = 32Byte
  assign aximInt.ar.len = arlen;
  assign aximInt.ar.lock = 1'd0;
  assign aximInt.ar.cache = 4'd0;

  enum logic [2:0] { RdIdle, RdBusy, RdWait, RdDone } read_state;
  logic [31:0] read_count;
  logic [15:0] read_wait_count;
  logic [47:0] read_expect_words;
  logic [47:0] read_receive_words;
  logic        reset_signature;

  // cfg_read_mode
  // 0 : reading
  // 4 : randomize length
  // 5 : allow read reordering (changes signature algorithm)

  // compute next araddr
  logic [AximAddressWidth-1:0]                araddr_next;
  logic [AximAddressWidth-1:0]                araddr_next_next;
  logic [AximAddressWidth-1:0]                araddr_random;

  logic                                                  consume_ar_random;
  assign consume_ar_random = ((read_state == RdBusy) && !ar_almost_full);
  oclib_lfsr #(.Seed(PortNumber+200), .OutWidth(AximAddressWidth))
  uARADDR_LFSR (.clock(clockAxim), .reset(reset_random), .enable(consume_ar_random), .out(araddr_random));

  logic                                                  hack_mode;
  logic [1:0]                                            prev_count;
  logic [1:0]                                            next_count;
  always_ff @(posedge clockAxim) begin
    hack_mode <= (cfg_local.address_inc_mask == 'hd00d); // in hack mode, we are going to rotate bank group bits 5 & 13
  end
  assign prev_count = {araddr_next[13], araddr_next[5]};
  assign next_count = (prev_count + 2'd1);

  always_comb begin
    araddr_next_next = (araddr_next      + cfg_local.address_inc) & cfg_local.address_inc_mask;
    araddr_next_next = (hack_mode ? {'0,next_count[1],7'd0,next_count[0],5'd0} : araddr_next_next);
    araddr_next_next = (araddr_next_next ^ (araddr_random & cfg_local.address_random_mask));
    araddr_next_next = (araddr_next_next ^ port_address);
  end

  // compute next arlen
  logic [3:0]                                              arlen_next;
  logic [3:0]                                              arlen_random;

  oclib_lfsr #(.Seed(PortNumber+201), .OutWidth(4), .LfsrWidth(33))
  uARLEN_LFSR (.clock(clockAxim), .reset(reset_random), .enable(consume_ar_random), .out(arlen_random));

  always_comb begin
    if (cfg_local.read_mode[4])  arlen_next = (arlen_random & cfg_local.burst_length);
    else                         arlen_next = cfg_local.burst_length;
  end

  always_ff @(posedge clockAxim) begin
    if (resetSync) begin
      arvalid <= 1'b0;
      arid <= '0;
      arlen <= '0;
      araddr_next <= '0;
      read_state <= RdIdle;
      read_count <= '0;
      read_wait_count <= '0;
      read_expect_words <= '0;
      reset_signature <= 1'b1;
    end
    else begin
      arvalid <= 1'b0;
      reset_signature <= 1'b0;
      if (arvalid) arid <= ((arid == cfg_local.read_max_id) ? '0 : (arid + 'd1));
      case (read_state)
        RdIdle: begin
          if (cfg_go_delayed && cfg_local.axim_enable[PortNumber]) begin
            read_state <= (cfg_local.read_mode[0] ? RdBusy : RdDone);
            reset_signature <= 1'b1;
          end
          araddr_next <= cfg_local.address ^ port_address;
          read_count <= '0;
          read_expect_words <= '0;
          arid <= '0;
        end
        RdBusy: begin
          if (!cfg_local.go) begin
            read_state <= RdIdle;
          end
          else begin
            if (!ar_almost_full) begin
              // we are doing a read
              arvalid <= 1'b1;
              araddr <= araddr_next;
              arlen <= arlen_next;
              araddr_next <= araddr_next_next;
              read_count <= (read_count + 1);
              read_expect_words <= (read_expect_words + 1 + arlen_next);
              if (cfg_local.op_count <= read_count) begin
                read_state <= RdDone;
              end
              else if (cfg_local.wait_states) begin
                read_state <= RdWait;
              end
           end
          end
          read_wait_count <= 'd1;
        end
        RdWait: begin
          if (!cfg_local.go) begin
            read_state <= RdIdle;
          end
          else if (read_wait_count >= cfg_local.wait_states) begin
            read_state <= RdBusy;
          end
          read_wait_count <= (read_wait_count + 'd1);
        end
        RdDone: begin
          if (!cfg_local.go) begin
            read_state <= RdIdle;
          end
        end
      endcase
    end
  end

  // **********
  // Accept write responses
  // **********

  assign aximInt.bready = 1'b1;
  logic                                 bresp_error;
  always_ff @(posedge clockAxim) begin
    bresp_error <= aximIntFb.bvalid && (aximIntFb.b.resp != '0);
  end

  // **********
  // Accept read responses
  // **********

  localparam int DatapathWords = (AximDataWidth/32);

  logic                                 rvalid_q;
  logic                                 rlast_q;
  logic [DatapathWords-1:0] [31:0]      rdata_q;
  logic                                 rvalid_qq;
  logic                                 rlast_qq;
  logic [(DatapathWords/4)-1:0] [31:0]  rdata_qq; // we reduce 4:1
  logic                                 rvalid_qqq;
  logic [31:0]                          rdata_qqq; // we reduce the rest of the way
  logic                                 rresp_error;
  logic [31:0]                          rdata_combined;

  assign aximInt.rready = 1'b1;

  always_comb begin
    rdata_combined = '0;
    for (int w=0; w<(DatapathWords/4); w++) begin
      rdata_combined += rdata_qq[w];
    end
  end

  logic       resetStats;
  logic [9:0] contexts;
  logic [9:0] contextsMax;
  logic [9:0] contextsAveragePre;
  logic [9:0] contextsAverage;
  logic [15:0] currentCycle;
  logic [15:0] startCycle;
  logic [16:0] latencyD;
  logic [15:0] latency;
  logic [15:0] latencyMin;
  logic [15:0] latencyMax;
  logic [15:0] latencyAverage;
  logic        statReqValid;
  logic        statRespValid;
  logic        statReqValidQ;
  logic        statRespValidQ;
  logic        statRespValidQQ;

  // avg with a time constant of 1K cycles in real world, 128 in sim
  oclib_averager #(.InWidth(10), .OutWidth(10), .TimeShift(`OC_VAL_IFDEF_THEN_ELSE(SIMULATION,7,10)))
  uCONTENT_AVG (.clock(clockAxim), .reset(resetStats),
                .in(contexts), .inValid(1'b1), .out(contextsAveragePre));

  oclib_fifo #(.Width(16), .Depth(1024))
  uLATENCY_FIFO (.clock(clockAxim), .reset(resetStats),
                 .inData(currentCycle), .inValid(statReqValidQ), .inReady(),
                 .outData(startCycle), .outValid(), .outReady(statRespValidQ));

  // avg with a time constant of 1K ops in real world, 128 in sim
  oclib_averager #(.InWidth(16), .OutWidth(16), .TimeShift(`OC_VAL_IFDEF_THEN_ELSE(SIMULATION,7,10)))
  uLATENCY_AVG (.clock(clockAxim), .reset(resetStats),
                .in(latency), .inValid(statRespValidQQ), .out(latencyAverage));

  assign latencyD = ({1'b1,currentCycle} - {1'b0,startCycle});

  always_ff @(posedge clockAxim) begin
    resetStats <= (resetSync || reset_signature);
    statReqValid <= (aximInt.arvalid && aximIntFb.arready);
    statReqValidQ <= statReqValid;
    statRespValid <= (aximIntFb.rvalid && aximIntFb.r.last && aximInt.rready);
    statRespValidQ <= statRespValid;
    statRespValidQQ <= statRespValidQ;
    latency <= (statRespValidQ ? latencyD[15:0] : '0); // valid with statRespValidQQ
    if (resetStats) begin
      contexts <= '0;
      contextsMax <= '0;
      contextsAverage <= '0;
      currentCycle <= '0;
      latencyMin <= 16'hffff;
      latencyMax <= '0;
    end
    else begin
      contexts <= (contexts + {'0, statReqValidQ} - {'0, statRespValidQ});
      contextsMax <= ((contexts > contextsMax) ? contexts : contextsMax);
      contextsAverage <= contextsAveragePre;
      currentCycle <= (currentCycle + 1);
      if (statRespValidQQ) begin
        latencyMax <= ((latency > latencyMax) ? latency : latencyMax);
        latencyMin <= ((latency < latencyMin) ? latency : latencyMin);
      end
    end
  end

  always_ff @(posedge clockAxim) begin
    rvalid_q <= aximIntFb.rvalid;
    rlast_q <= aximIntFb.r.last;
    rdata_q <= aximIntFb.r.data;
    rresp_error <= aximIntFb.rvalid && (aximIntFb.r.resp != '0);
    sts_local.data <= (rvalid_q ? rdata_q : sts_local.data); // latch the last word of read data for CPU
    rvalid_qq <= rvalid_q;
    rlast_qq <= rlast_q;
    for (int w=0; w<(DatapathWords/4); w++) begin
      rdata_qq[w] <= (rdata_q[w*4] + rdata_q[w*4+1] + rdata_q[w*4+2] + rdata_q[w*4+3]);
    end
    rvalid_qqq <= rvalid_qq;
    rdata_qqq <= rdata_combined;
  end

  always_ff @(posedge clockAxim) begin
    if (resetStats) begin
      sts_local.signature <= '0;
      read_receive_words <= '0;
    end
    else begin
      if (rvalid_qqq) begin
        sts_local.signature <= (rdata_qqq + (cfg_local.read_mode[5] ?
                                             sts_local.signature : // we just add read data without rotations, so order won't matter
                                             {sts_local.signature[30:0], sts_local.signature[31]}));
        read_receive_words <= (read_receive_words + 1);
      end
    end
  end

  // Generate DONE / ERROR status
  always_ff @(posedge clockAxim) begin
    sts_local.done <= ((write_state == WrDone) && (read_state == RdDone) && (read_receive_words >= read_expect_words));
    sts_local.error <= (resetSync ? '0 :
                        (sts_local.error | { bresp_error, rresp_error }));
    sts_local.rdata <= ((cfg_local.sts_csr_select == 'h00) ? {6'd0,contextsMax,6'd0,contextsAverage} :
                        (cfg_local.sts_csr_select == 'h01) ? {latencyMax,latencyMin} :
                        (cfg_local.sts_csr_select == 'h02) ? {16'd0,latencyAverage} :
                        'h0bad0bad);
  end

endmodule // oclib_memory_bist_axi





module oclib_memory_bist_csrs #(
                                parameter     type AxilType = oclib_pkg::axil_32_s,
                                parameter     type AxilFbType = oclib_pkg::axil_32_fb_s,
                                parameter int AximAddressWidth = 0, // must be overridden
                                parameter int AximDataWidth = 0, // must be overridden
                                parameter int AxilClockFreq = 100000000, // used for the uptime counters
                                parameter int SyncCycles = 3,
                                parameter bit ResetSync = oclib_pkg::False,
                                parameter int ResetPipeline = 0
                                )
  (
   // AXIL
   input                                            clockAxil,
   input                                            resetAxil,
   input                                            AxilType axil,
   output                                           AxilFbType axilFb,

   // CONFIG/STATUS SIGNALS
   input                                            clockAxim,
   input                                            resetAxim,
   output                                           oclib_memory_bist_pkg::cfg_s cfg,
   input                                            oclib_memory_bist_pkg::sts_s sts
   );

  localparam int AxiLiteDataWidth = $bits(axil.wdata);

  // Some timers to debug whether the bitfile is being reset or reloaded

  logic [7:0]                                       reload_stable = 8'h0;
  logic                                             reload_detect;
  logic                                             reload_uptime_pulse;
  logic [31:0]                                      reload_uptime_prescale;
  logic [31:0]                                      reload_uptime_seconds;
  logic                                             reset_uptime_pulse;
  logic [31:0]                                      reset_uptime_prescale;
  logic [31:0]                                      reset_uptime_seconds;
  logic [31:0]                                      cycles_under_reset;
  logic [31:0]                                      cycles_since_reset;

  // first we detect the reload event, essentially generating a "power on reset"
  always_ff @(posedge clockAxil) begin
    reload_stable <= { reload_stable[6:0], 1'b1 };
    reload_detect <= !reload_stable[7];
  end

  always_ff @(posedge clockAxil) begin
    if (reload_detect) begin
      reload_uptime_prescale <= '0;
      reload_uptime_seconds <= '0;
      cycles_under_reset <= '0;
    end
    else begin
      reload_uptime_prescale <= (reload_uptime_pulse ? '0 : (reload_uptime_prescale + 'd1));
      reload_uptime_seconds <= (reload_uptime_seconds + {'0, reload_uptime_pulse});
      cycles_under_reset <= (cycles_under_reset + {'0, resetAxil});
    end
    if (resetAxil) begin
      reset_uptime_prescale <= '0;
      reset_uptime_seconds <= '0;
      cycles_since_reset <= '0;
    end
    else begin
      reset_uptime_prescale <= (reset_uptime_pulse ? '0 : (reset_uptime_prescale + 'd1));
      reset_uptime_seconds <= (reset_uptime_seconds + {'0, reset_uptime_pulse});
      cycles_since_reset <= (cycles_since_reset + 'd1);
    end
    reload_uptime_pulse <= (reload_uptime_prescale == (AxilClockFreq-2));
    reset_uptime_pulse <= (reset_uptime_prescale == (AxilClockFreq-2));
  end

  // AXIL interface in AXIL domain

  logic [9:0]                                     axil_address;
  logic [AxiLiteDataWidth-1:0]                    axil_write_data;
  logic                                           axil_write;
  logic                                           axil_write_req_toggle;
  logic                                           axil_write_resp_toggle;
  logic                                           axil_write_resp_toggle_q;
  logic                                           axil_read;
  logic                                           axil_read_req_toggle;
  logic                                           axil_read_resp_toggle;
  logic                                           axil_read_resp_toggle_q;
  logic [AxiLiteDataWidth-1:0]                    axil_read_data;
  logic                                           axil_rvalid;
  logic                                           axil_bvalid;

  logic [31:0]                                    axil_write_count;
  logic [31:0]                                    axil_read_count;

  logic [AxiLiteDataWidth-1:0]                    axil_local_read_data;
  logic [AxiLiteDataWidth-1:0]                    axim_read_data_sync;

  assign axilFb.awready = axil_write;
  assign axilFb.arready = axil_read;
  assign axilFb.wready = axil_write;
  assign axilFb.rresp = '0; // we always signal successful
  assign axilFb.rdata = axil_read_data;
  assign axilFb.rvalid = axil_rvalid;
  assign axilFb.bresp = '0; // we always signal successful
  assign axilFb.bvalid = axil_bvalid;

  always_ff @(posedge clockAxil) begin
    if (resetAxil) begin
      axil_write <= 1'b0;
      axil_read <= 1'b0;
      axil_write_req_toggle <= 1'b0;
      axil_read_req_toggle <= 1'b0;
      axil_rvalid <= 1'b0;
      axil_bvalid <= 1'b0;
      axil_write_count <= '0;
      axil_read_count <= '0;
    end
    else begin
      axil_write <= (axil.awvalid && axil.wvalid && !axil_write);
      axil_read <= (axil.arvalid && !axil_read);
      axil_write_req_toggle <= (axil_write_req_toggle ^ axil_write);
      axil_read_req_toggle <= (axil_read_req_toggle ^ axil_read);
      axil_rvalid <= (axil_rvalid ? ~axil.rready : (axil_read_resp_toggle ^ axil_read_resp_toggle_q));
      axil_bvalid <= (axil_bvalid ? ~axil.bready : (axil_write_resp_toggle ^ axil_write_resp_toggle_q));
      axil_write_count <= (axil_write_count + {31'd0, axil_write});
      axil_read_count <= (axil_read_count + {31'd0, axil_read});
    end
    axil_write_resp_toggle_q <= axil_write_resp_toggle;
    axil_read_resp_toggle_q <= axil_read_resp_toggle;
    // this is just paranoia, probably don't need to latch these, but spec says they are only valid during valid...
    axil_address <= (axil_write ? axil.awaddr :
                     axil_read ? axil.araddr :
                     axil_address);
    axil_write_data <= (axil_write ? axil.wdata :
                        axil_write_data);
    // mux in the read data, mostly from AXI domain but some local
    axil_read_data <= ((axil_address[9:8] == 2'd3) ? axil_local_read_data : axim_read_data_sync);
  end

  always_comb begin
    case (axil_address[4:2])
      3'b000 : axil_local_read_data = reload_uptime_seconds;
      3'b001 : axil_local_read_data = reset_uptime_seconds;
      3'b010 : axil_local_read_data = axil_write_count;
      3'b011 : axil_local_read_data = axil_read_count;
      3'b100 : axil_local_read_data = cycles_under_reset;
      3'b101 : axil_local_read_data = cycles_since_reset;
      3'b110 : axil_local_read_data = `OCLIB_MEMORY_BIST_VERSION;
      default : axil_local_read_data = 32'hbadc0ffe;
    endcase // case (axil_address[4:2])
  end

  // SYNC BETWEEN CLOCK DOMAINS

  logic [9:0]                                     axim_address;
  logic [AxiLiteDataWidth-1:0]                    axim_write_data;
  logic                                           axim_write_req_toggle;
  logic                                           axim_read_req_toggle;
  logic                                           axim_write_req_toggle_q;
  logic                                           axim_read_req_toggle_q;
  logic                                           axim_write_resp_toggle;
  logic                                           axim_read_resp_toggle;
  logic                                           axim_write;
  logic                                           axim_read;
  logic [AxiLiteDataWidth-1:0]                    axim_read_data;

  oclib_synchronizer #(.Width(10), .SyncCycles(SyncCycles))
  uAXIM_ADDRESS (clockAxim, axil_address, axim_address);

  oclib_synchronizer #(.Width(AxiLiteDataWidth), .SyncCycles(SyncCycles))
  uAXIM_WRITE_DATA (clockAxim, axil_write_data, axim_write_data);

  oclib_synchronizer #(.Width(2), .SyncCycles(SyncCycles+2))
  uAXIM_CONTROL (clockAxim, {axil_write_req_toggle, axil_read_req_toggle}, {axim_write_req_toggle, axim_read_req_toggle});

  always_ff @(posedge clockAxim) begin
    if (resetAxim) begin
      axim_write <= 1'b0;
      axim_read <= 1'b0;
      axim_write_resp_toggle <= 1'b0;
      axim_read_resp_toggle <= 1'b0;
    end
    else begin
      axim_write <= (axim_write_req_toggle ^ axim_write_req_toggle_q);
      axim_read <= (axim_read_req_toggle ^ axim_read_req_toggle_q);
      axim_write_resp_toggle <= (axim_write_resp_toggle ^ axim_write);
      axim_read_resp_toggle <= (axim_read_resp_toggle ^ axim_read);
    end
    axim_write_req_toggle_q <= axim_write_req_toggle;
    axim_read_req_toggle_q <= axim_read_req_toggle;
  end

  oclib_synchronizer #(.Width(AxiLiteDataWidth), .SyncCycles(SyncCycles))
  uAXIL_READ_DATA (clockAxil, axim_read_data, axim_read_data_sync);

  oclib_synchronizer #(.Width(2), .SyncCycles(SyncCycles+2))
  uAXIL_CONTROL (clockAxil, {axim_write_resp_toggle, axim_read_resp_toggle}, {axil_write_resp_toggle, axil_read_resp_toggle});

  // IMPLEMENT THE MAIN CSR ARRAY IN AXI DOMAIN

  // first some debug stuff
  logic [7:0]                                       axim_reload_stable = '0;
  logic                                             axim_reload_detect;
  always_ff @(posedge clockAxim) begin
    axim_reload_stable <= { axim_reload_stable[6:0], 1'b1 };
    axim_reload_detect <= !axim_reload_stable[7];
  end
                                                                                   // to check the AXI clock speed
  logic [31:0]                                      axim_cycles_under_reset = '0;
  logic [31:0]                                      axim_cycles_since_reset;
  always_ff @(posedge clockAxim) begin
    axim_cycles_under_reset <= (axim_reload_detect ? '0 : (axim_cycles_under_reset + {'0, resetAxim}));
    axim_cycles_since_reset <= (resetAxim ? '0 : (axim_cycles_since_reset + 'd1));
  end

  logic [31:0] axim_select; // we reserve space for N * 4Byte "individual" CSRs
  logic        axim_select_write_data; // these two indicate that address matches a range for larger CSRs
  logic        axim_select_read_data;

  // data buffer related, we reserve space for up to 256Byte of buffer
  localparam int DataBufferWords = (AximDataWidth / AxiLiteDataWidth); // assume data width is multiple of oclib_pkg::AxiLite...
  logic [DataBufferWords-1:0]                        axim_word_select; // reserve space for N * 4Byte "individual" CSRs
  logic [AxiLiteDataWidth-1:0]                       muxed_write_data;
  logic [AxiLiteDataWidth-1:0]                       muxed_write_data_q;
  logic [AxiLiteDataWidth-1:0]                       muxed_read_data;
  logic [AxiLiteDataWidth-1:0]                       muxed_read_data_q;
  logic [DataBufferWords-1:0] [AxiLiteDataWidth-1:0] cfg_data_as_words;
  logic [DataBufferWords-1:0] [AxiLiteDataWidth-1:0] sts_data_as_words;

  logic                                              timer_run;
  logic [7:0]                                        prescale_counter;
  logic                                              prescale_pulse;
  logic [31:0]                                       sts_op_cycles;
  logic                                              cfg_prescale;

  assign cfg.data = cfg_data_as_words; // convert between byte-oriented and word-oriented formats
  assign sts_data_as_words = sts.data; // convert between byte-oriented and word-oriented formats

  always_ff @(posedge clockAxim) begin
    if (resetAxim) begin
      cfg_prescale <= 1'b0;
      cfg.go <= 1'b0;
      cfg.write_mode <= '0;
      cfg.read_mode <= '0;
      cfg.op_count <= '0;
      cfg.axim_enable <= '0;
      cfg.address <= '0;
      cfg.address_inc <= '0;
      cfg.address_inc_mask <= {AximAddressWidth{1'b1}};
      cfg.address_random_mask <= {AximAddressWidth{1'b0}};
      cfg.sts_port_select <= '0;
      cfg.sts_csr_select <= '0;
      cfg.address_port_shift <= '0;
      cfg.address_port_mask <= {oclib_memory_bist_pkg::AximCountWidth{1'b1}};
      cfg.wait_states <= '0;
      cfg.burst_length <= '0;
      cfg.read_max_id <= '0;
      cfg.write_max_id <= '0;
      cfg_data_as_words <= '0;
    end
    else begin
      if (axim_write && axim_select[0]) begin
        cfg_prescale <= axim_write_data[1];
        cfg.go <= axim_write_data[0];
        cfg.write_mode <= axim_write_data[15:8];
        cfg.read_mode <= axim_write_data[23:16];
      end
      if (axim_write && axim_select[1]) begin
        cfg.op_count <= axim_write_data;
      end
      if (axim_write && axim_select[2]) begin
        cfg.axim_enable <= axim_write_data;
      end
      if (axim_write && axim_select[4]) begin
        cfg.address[31:0] <= axim_write_data;
      end
      if (axim_write && axim_select[5]) begin
        cfg.address[AximAddressWidth-1:32] <= axim_write_data;
      end
      if (axim_write && axim_select[6]) begin
        cfg.address_inc[31:0] <= axim_write_data;
      end
      if (axim_write && axim_select[7]) begin
        cfg.address_inc[AximAddressWidth-1:32] <= axim_write_data;
      end
      if (axim_write && axim_select[8]) begin
        cfg.address_inc_mask[31:0] <= axim_write_data;
      end
      if (axim_write && axim_select[9]) begin
        cfg.address_inc_mask[AximAddressWidth-1:32] <= axim_write_data;
      end
      if (axim_write && axim_select[16]) begin
        cfg.wait_states <= axim_write_data;
      end
      if (axim_write && axim_select[17]) begin
        cfg.burst_length <= axim_write_data;
      end
      if (axim_write && axim_select[18]) begin
        cfg.write_max_id <= axim_write_data[7:0];
        cfg.read_max_id <= axim_write_data[15:8];
      end
      if (axim_write && axim_select[19]) begin
        cfg.address_port_shift <= axim_write_data[oclib_memory_bist_pkg::AximCountWidth-1:0];
        cfg.address_port_mask <= axim_write_data[oclib_memory_bist_pkg::AximCountWidth+15:16];
      end
      if (axim_write && axim_select[20]) begin
        cfg.address_random_mask[31:0] <= axim_write_data;
      end
      if (axim_write && axim_select[21]) begin
        cfg.address_random_mask[AximAddressWidth-1:32] <= axim_write_data;
      end
      if (axim_write && axim_select[22]) begin
        cfg.sts_csr_select <= axim_write_data[7:0];
        cfg.sts_port_select <= axim_write_data[23:16];
      end
      if (axim_write && axim_select_write_data) begin
        cfg_data_as_words[axim_address[7:2]] <= axim_write_data;
      end
    end
    axim_select <= '0;
    if (axim_address[9:8] == 2'd0) begin
      axim_select[axim_address[7:2]] <= 1'b1; // set just the bit corresponding to address of a 32-bit (4 byte) CSR
    end
    axim_word_select <= '0;
    axim_word_select[axim_address[7:2]] <= 1'b1;
    axim_select_write_data <= (axim_address[9:8] == 2'd1); // addresses 256-511
    axim_select_read_data <= (axim_address[9:8] == 2'd2); // addresses 512-767

    axim_read_data <=
             (({AxiLiteDataWidth{axim_select[0]}} & { sts.done, 7'd0,
                                                     cfg.read_mode, cfg.write_mode,
                                                     6'd0, cfg_prescale, cfg.go}) |
              ({AxiLiteDataWidth{axim_select[1]}} & { '0, cfg.op_count }) |
              ({AxiLiteDataWidth{axim_select[2]}} & { '0, cfg.axim_enable }) |
              ({AxiLiteDataWidth{axim_select[4]}} & { cfg.address[31:0] }) |
              ({AxiLiteDataWidth{axim_select[5]}} & { '0, cfg.address[AximAddressWidth-1:32] }) |
              ({AxiLiteDataWidth{axim_select[6]}} & { cfg.address_inc[31:0] }) |
              ({AxiLiteDataWidth{axim_select[7]}} & { '0, cfg.address_inc[AximAddressWidth-1:32] }) |
              ({AxiLiteDataWidth{axim_select[8]}} & { cfg.address_inc_mask[31:0] }) | // 0x20
              ({AxiLiteDataWidth{axim_select[9]}} & { '0, cfg.address_inc_mask[AximAddressWidth-1:32] }) |
              ({AxiLiteDataWidth{axim_select[10]}} & { sts.signature }) |
              ({AxiLiteDataWidth{axim_select[11]}} & { sts.error }) |
              ({AxiLiteDataWidth{axim_select[12]}} & { sts_op_cycles }) | // 0x30
              ({AxiLiteDataWidth{axim_select[13]}} & { 32'h4d454d54 }) | // MEMT
              ({AxiLiteDataWidth{axim_select[14]}} & { axim_cycles_under_reset }) |
              ({AxiLiteDataWidth{axim_select[15]}} & { axim_cycles_since_reset }) |
              ({AxiLiteDataWidth{axim_select[16]}} & { '0, cfg.wait_states }) | // 0x40
              ({AxiLiteDataWidth{axim_select[17]}} & { '0, cfg.burst_length }) |
              ({AxiLiteDataWidth{axim_select[18]}} & { '0, cfg.read_max_id, cfg.write_max_id }) |
              ({AxiLiteDataWidth{axim_select[19]}} & ( {cfg.address_port_mask,16'd0} | cfg.address_port_shift)) | // 0x4c
              ({AxiLiteDataWidth{axim_select[20]}} & { cfg.address_random_mask[31:0] }) | // 0x50
              ({AxiLiteDataWidth{axim_select[21]}} & { '0, cfg.address_random_mask[AximAddressWidth-1:32] }) |
              ({AxiLiteDataWidth{axim_select[22]}} & { 8'd0, cfg.sts_port_select, 8'd0, cfg.sts_csr_select }) |
              ({AxiLiteDataWidth{axim_select[23]}} & { sts.rdata }) | // 0x5c
              ({AxiLiteDataWidth{axim_select_write_data}} & { muxed_write_data_q }) | // 0x100
              ({AxiLiteDataWidth{axim_select_read_data}} & { muxed_read_data_q }) | // 0x200
              {AxiLiteDataWidth{1'b0}}
              );

    muxed_write_data_q <= muxed_write_data;
    muxed_read_data_q <= muxed_read_data;
    timer_run <= (cfg.go && !sts.done);
    prescale_counter <= (timer_run ? (prescale_counter + 'd1) : '0);
    prescale_pulse <= timer_run && ((!cfg_prescale) || (&prescale_counter)); // "pulse" always if !cfg_prescale, else every 256
    sts_op_cycles <= (cfg.go ? (prescale_pulse ? (sts_op_cycles + 'd1) : sts_op_cycles) : '0);
  end // always_ff @

  always_comb begin
    muxed_write_data = '0;
    for (int word=0; word<DataBufferWords; word++) begin
      if (axim_word_select[word]) muxed_write_data = muxed_write_data | cfg_data_as_words[word];
    end
  end

  always_comb begin
    muxed_read_data = '0;
    for (int word=0; word<DataBufferWords; word++) begin
      if (axim_word_select[word]) muxed_read_data = muxed_read_data | sts_data_as_words[word];
    end
  end

`ifdef USER_MEMORY_TEST_ILA

  `OC_DEBUG_ILA(uILA_AXIL, clockAxil, 1024, 512, 32,
                {axil,
                 axilFb,
                 axil_address,
                 axil_read_data,
                 axil_write_data},
                {axil_read_req_toggle,
                 axil_read_resp_toggle,
                 axil_read,
                 axil_write_req_toggle,
                 axil_write_resp_toggle,
                 axil_write});

  `OC_DEBUG_ILA(uILA_AXIM, clockAxim, 1024, 512, 32,
                {cfg_data_as_words,
                 axim_write_select,
                 axim_write_address},
                {axim_write_select_cfg_data,
                 axim_write,
                 resetAxim,
                 muxed_cfg_data,
                 axim_read_select_cfg_data,
                 axim_read_select_sts_data});
  );
`endif

endmodule // oclib_memory_bist_csrs
