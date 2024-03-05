
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"
`include "sim/ocsim_pkg.sv"

module ocsim_axim_memory #(
                           parameter int AximPorts = 1,
                           parameter     type AximType = oclib_pkg::axi4m_256_s,
                           parameter     type AximFbType = oclib_pkg::axi4m_256_fb_s,
                           parameter bit SeparateMemorySpaces = 0,
                           parameter int MemoryBytes = 65536 * AximPorts, // our sim convention is to use 64K per HBM port
                           parameter int InputFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_INPUT_FIFO_DEPTH,64),
                           parameter int OutputFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_OUTPUT_FIFO_DEPTH,64),
                           parameter int ARFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_AR_FIFO_DEPTH,InputFifoDepth),
                           parameter int AWFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_AW_FIFO_DEPTH,InputFifoDepth),
                           parameter int WFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_W_FIFO_DEPTH,InputFifoDepth),
                           parameter int BFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_B_FIFO_DEPTH,OutputFifoDepth),
                           parameter int RFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_R_FIFO_DEPTH,OutputFifoDepth),
                           parameter int ReadLatencyCycles = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_READ_LATENCY,32),
                           parameter int WriteLatencyCycles = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_WRITE_LATENCY,32),
                           parameter int DutyCycle = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_READ_DUTY_CYCLE,100),
                           parameter int ReadDutyCycle = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_READ_DUTY_CYCLE,DutyCycle),
                           parameter int WriteDutyCycle = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_WRITE_DUTY_CYCLE,DutyCycle),
                           parameter int GapCycles = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_GAP_CYCLES,0),
                           parameter int ReadGapCycles = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_READ_GAP_CYCLES,GapCycles),
                           parameter int WriteGapCycles = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_WRITE_GAP_CYCLES,GapCycles),
                           parameter bit MemoryInit = (`OC_VAL_ISTRUE(OCSIM_AXIM_MEMORY_INIT) ||
                                                       `OC_VAL_ISTRUE(OCSIM_AXIM_MEMORY_INIT_ZERO) ),
                           parameter bit MemoryInitZero = `OC_VAL_ISTRUE(OCSIM_AXIM_MEMORY_INIT_ZERO)
                           )
  (
   input [AximPorts-1:0] clockAxim,
   input [AximPorts-1:0] resetAxim,
   input AximType [AximPorts-1:0] axim,
   output AximFbType [AximPorts-1:0] aximFb
   );

  localparam int MemWidth = $bits(axim[0].w.data);
  localparam int MemWidthBytes = (MemWidth/8);
  localparam int MemDepth = (MemoryBytes / MemWidthBytes);
  logic [MemWidth-1:0] mem [MemDepth-1:0];
  if (MemoryInit) begin
    initial begin
      for (int i=0; i<MemDepth; i++) begin
        if (MemoryInitZero)  mem[i] = '0;
        else                 mem[i] = MemWidth'(i);
      end
    end
  end

  localparam type AximAwType = type(axim[0].aw);
  localparam type AximArType = type(axim[0].ar);
  localparam type AximWType = type(axim[0].w);
  localparam type AximRType = type(aximFb[0].r);
  localparam type AximBType = type(aximFb[0].b);

  logic [AximPorts-1:0] blockRead = '0;
  logic [AximPorts-1:0] blockWrite = '0;

  for (genvar port=0; port<AximPorts; port++) begin : aximPort
    // really simplistic axi3 slave for now
    // * no support for byte masks
    // * no support for creating errors
    // * no support for creating reordering

    int readDutyCycle = ReadDutyCycle;
    int writeDutyCycle = WriteDutyCycle;

    // *** aw channel
    AximAwType                                             aw;
    logic                                                  awready;
    logic                                                  awvalid;
    logic                                                  aw_almost_full;
    localparam AWFifoAddressWidth = $clog2(AWFifoDepth);

    oclib_fifo #(.Width($bits(AximAwType)), .Depth(AWFifoDepth), .AlmostFull(AWFifoDepth/2))
    uAW_FIFO (.clock(clockAxim[port]), .reset(resetAxim[port]), .almostFull(aw_almost_full),
              .inData(axim[port].aw), .inValid(axim[port].awvalid), .inReady(aximFb[port].awready),
              .outData(aw), .outValid(awvalid), .outReady(awready));

    // *** ar channel
    AximArType                                             ar;
    logic                                                  arready;
    logic                                                  arvalid;
    logic                                                  ar_almost_full;
    localparam ARFifoAddressWidth = $clog2(ARFifoDepth);

    oclib_fifo #(.Width($bits(AximArType)), .Depth(ARFifoDepth), .AlmostFull(ARFifoDepth/2))
    uAR_FIFO (.clock(clockAxim[port]), .reset(resetAxim[port]), .almostFull(ar_almost_full),
              .inData(axim[port].ar), .inValid(axim[port].arvalid), .inReady(aximFb[port].arready),
              .outData(ar), .outValid(arvalid), .outReady(arready));

    // *** w channel
    AximWType                                              w;
    logic                                                  wvalid;
    logic                                                  wready;
    logic                                                  w_almost_full;
    localparam WFifoAddressWidth = $clog2(WFifoDepth);

    oclib_fifo #(.Width($bits(AximWType)), .Depth(WFifoDepth), .AlmostFull(WFifoDepth/2))
    uW_FIFO (.clock(clockAxim[port]), .reset(resetAxim[port]), .almostFull(w_almost_full),
             .inData(axim[port].w), .inValid(axim[port].wvalid), .inReady(aximFb[port].wready),
             .outData(w), .outValid(wvalid), .outReady(wready));

    // *** r channel
    AximRType                                              r;
    logic                                                  rvalid;
    logic                                                  rready;
    logic                                                  r_almost_full;
    AximRType                                              rDelay;
    logic                                                  rvalidDelay;
    localparam RFifoAddressWidth = $clog2(RFifoDepth);

    oclib_fifo #(.Width($bits(AximRType)), .Depth(RFifoDepth), .AlmostFull(RFifoDepth-2-ReadLatencyCycles))
    uR_FIFO (.clock(clockAxim[port]), .reset(resetAxim[port]), .almostFull(r_almost_full),
             .inData(rDelay), .inValid(rvalidDelay), .inReady(rready),
             .outData(aximFb[port].r), .outValid(aximFb[port].rvalid), .outReady(axim[port].rready));

    oclib_pipeline #(.Width($bits(AximRType)+1), .Length(ReadLatencyCycles))
    uR_PIPE (.clock(clockAxim[port]), .in({rvalid,r}), .out({rvalidDelay,rDelay}));

    // *** b channel
    AximBType                                              b;
    logic                                                  bvalid;
    logic                                                  bready;
    logic                                                  b_almost_full;
    AximBType                                              bDelay;
    logic                                                  bvalidDelay;
    localparam BFifoAddressWidth = $clog2(BFifoDepth);

    oclib_fifo #(.Width($bits(AximBType)), .Depth(BFifoDepth), .AlmostFull(BFifoDepth-2-WriteLatencyCycles))
    uB_FIFO (.clock(clockAxim[port]), .reset(resetAxim[port]), .almostFull(b_almost_full),
             .inData(bDelay), .inValid(bvalidDelay), .inReady(bready),
             .outData(aximFb[port].b), .outValid(aximFb[port].bvalid), .outReady(axim[port].bready));

    oclib_pipeline #(.Width($bits(AximBType)+1), .Length(WriteLatencyCycles))
    uB_PIPE (.clock(clockAxim[port]), .in({bvalid,b}), .out({bvalidDelay,bDelay}));

    localparam int PortAddressOffset = (SeparateMemorySpaces ? (port * (MemoryBytes/AximPorts)) : 0);
    localparam int PortAddressMask = (SeparateMemorySpaces ? ((MemoryBytes/AximPorts)-1) : 'hffffffff);
    int            readGapCount;
    int            writeGapCount;
    int            extraWriteWords;
    int            extraWriteCount;
    int            extraReadWords;
    int            extraReadCount;

    logic              doingWrite;
    logic              doingRead;

    assign wready = (awready || (extraWriteWords));
    assign doingWrite = (awvalid && wvalid && awready && (extraWriteWords==0));
    assign doingRead = (arvalid && arready && (extraReadWords==0));

    function int physical_address( input int address, input int burstWord );
      return (((((address + (burstWord*MemWidthBytes)) & PortAddressMask) + PortAddressOffset) /
               MemWidthBytes) % MemDepth);
    endfunction

    always @(posedge clockAxim[port]) begin
      if (resetAxim[port]) begin
        awready <= 1'b0;
        arready <= 1'b0;
        bvalid <= 1'b0;
        rvalid <= 1'b0;
        readGapCount <= 0;
        writeGapCount <= 0;
        extraWriteWords <= '0;
        extraWriteCount <= '0;
        extraReadWords <= '0;
        extraReadCount <= '0;
      end
      else begin
        arready <= 1'b0;
        bvalid <= 1'b0;
        rvalid <= 1'b0;
        writeGapCount <= ((writeGapCount>0) ? (writeGapCount-1) : writeGapCount);
        readGapCount <= ((readGapCount>0) ? (readGapCount-1) : readGapCount);
        awready <= (!b_almost_full && ocsim_pkg::RandPercent(writeDutyCycle) && (writeGapCount==0) &&
                    !(doingWrite && aw.len) && !(extraWriteWords>1) && !blockWrite[port]);
        if (extraWriteWords) begin
          writeGapCount <= WriteGapCycles;
          extraWriteCount <= (extraWriteCount+1);
          extraWriteWords <= (extraWriteWords-1);
          mem[physical_address(aw.addr, extraWriteCount)] <= w.data;
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: writing %x to %x on port %0d (model addr %x, burst word %0d)", $realtime,
                   w.data, (aw.addr + (extraWriteCount*MemWidthBytes)), port,
                   physical_address(aw.addr, extraWriteCount), extraWriteCount);
          `endif
          if (extraWriteWords == 1) begin
            bvalid <= 1'b1;
          end
        end
        else if (doingWrite) begin
          writeGapCount <= WriteGapCycles;
          extraWriteWords <= aw.len;
          extraWriteCount <= 1;
          b.id <= aw.id;
          b.resp <= 2'd0;
          bvalid <= (aw.len == 0);
          mem[physical_address(aw.addr, 0)] <= w.data;
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: writing %x to %x on port %0d (model addr %x)", $realtime,
                   w.data, aw.addr, port, physical_address(aw.addr, 0));
          `endif
        end
        arready <= (!r_almost_full && ocsim_pkg::RandPercent(readDutyCycle) && (readGapCount==0) &&
                   !(doingRead && ar.len) && !(extraReadWords>1) && !blockRead[port]);
        if (extraReadWords) begin
          readGapCount <= ReadGapCycles;
          extraReadCount <= (extraReadCount+1);
          extraReadWords <= (extraReadWords-1);
          rvalid <= 1'b1;
          r.data <= mem[physical_address(ar.addr, extraReadCount)];
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: reading %x from %x on port %0d (model addr %x, burst word %0d)", $realtime,
                   mem[physical_address(ar.addr, extraReadCount)], (ar.addr + (extraReadCount*MemWidthBytes)), port,
                   physical_address(ar.addr, extraReadCount), extraReadCount);
          `endif
          if (extraReadWords == 1) begin
            r.last <= 1'b1;
          end
        end
        else if (doingRead) begin
          readGapCount <= ReadGapCycles;
          extraReadWords <= ar.len;
          extraReadCount <= 1;
          rvalid <= 1'b1;
          r.id <= ar.id;
          r.last <= (ar.len==0);
          r.resp <= 2'd0;
          r.data <= mem[physical_address(ar.addr, 0)];
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: reading %x from %x on port %0d (model addr %x)", $realtime,
                   mem[physical_address(ar.addr, 0)], ar.addr, port, physical_address(ar.addr, 0));
          `endif
        end
      end
    end

  end // block: aximPort

endmodule // ocsim_axim_memory
