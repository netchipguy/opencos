
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
                           parameter int ArFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_AR_FIFO_DEPTH,InputFifoDepth),
                           parameter int AwFifoDepth = `OC_VAL_ASDEFINED_ELSE(OCSIM_AXIM_MEMORY_AW_FIFO_DEPTH,InputFifoDepth),
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
      for (int i=0; i<MemDepth; i++) mem[i] = (MemoryInitZero ? '0 : MemWidth'(i));
    end
  end

  logic [AximPorts-1:0] blockRead = '0;
  logic [AximPorts-1:0] blockWrite = '0;

  for (genvar port=0; port<AximPorts; port++) begin : aximPort
    // really simplistic axi3 slave for now
    // * no support for byte masks
    // * no support for creating errors
    // * no support for creating reordering

    AximType aximInt;
    AximFbType aximFifoFb;

    logic arAlmostFull;
    logic awAlmostFull;
    logic wAlmostFull;
    logic rAlmostFull;
    logic bAlmostFull;

    int readDutyCycle = ReadDutyCycle;
    int writeDutyCycle = WriteDutyCycle;

    oclib_axim_fifo #(
                      .AximType(AximType), .AximFbType(AximFbType),
                      .ArDepth(ArFifoDepth), .ArAlmostFull(ArFifoDepth/2),
                      .AwDepth(AwFifoDepth), .AwAlmostFull(AwFifoDepth/2),
                      .WDepth(WFifoDepth), .WAlmostFull(WFifoDepth/2),
                      .RDepth(RFifoDepth), .RAlmostFull(RFifoDepth/2),
                      .BDepth(BFifoDepth), .BAlmostFull(BFifoDepth/2)
                      )
    uAXIM_FIFO (
                .clock(clockAxim[port]), .reset(resetAxim[port]),
                .arAlmostFull(arAlmostFull), .awAlmostFull(awAlmostFull), .wAlmostFull(wAlmostFull),
                .rAlmostFull(rAlmostFull), .bAlmostFull(bAlmostFull),
                .in(axim[port]), .inFb(aximFb[port]),
                .out(aximInt), .outFb(aximFifoFb) // aximFifoFb, explained ... vvv ...
                );

    // Reverse channel has extra pipeline delay.  This only works because the "ready" on R/B FB FIFO
    // never goes away, because we stop servicing the AR/AW FIFOs when R/B get half full.
    // We can't add latency on the awready, wready, arready however
    AximFbType aximIntFb;

    oclib_pipeline #(.Width($bits({aximIntFb.rvalid, aximIntFb.r, aximIntFb.bvalid, aximIntFb.b})), .Length(ReadLatencyCycles))
    uR_PIPE (.clock(clockAxim[port]),
             .in({aximIntFb.rvalid, aximIntFb.r, aximIntFb.bvalid, aximIntFb.b}),
             .out({aximFifoFb.rvalid, aximFifoFb.r, aximFifoFb.bvalid, aximFifoFb.b}));

    assign aximFifoFb.awready = aximIntFb.awready;
    assign aximFifoFb.wready = aximIntFb.wready;
    assign aximFifoFb.arready = aximIntFb.arready;


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

    assign wready = (aximIntFb.awready || (extraWriteWords));
    assign doingWrite = (aximInt.awvalid && aximInt.wvalid &&
                         aximIntFb.awready && aximIntFb.wready &&
                         (extraWriteWords==0));
    assign doingRead = (aximInt.arvalid && aximIntFb.arready && (extraReadWords==0));

    logic              nextWriteReady;
    assign nextWriteReady = (!bAlmostFull && ocsim_pkg::RandPercent(writeDutyCycle) && (writeGapCount==0) &&
                             !(doingWrite && aximInt.aw.len) && !(extraWriteWords>1) && !blockWrite[port]);

    function int physical_address( input int address, input int burstWord );
      return (((((address + (burstWord*MemWidthBytes)) & PortAddressMask) + PortAddressOffset) /
               MemWidthBytes) % MemDepth);
    endfunction

    always @(posedge clockAxim[port]) begin
      if (resetAxim[port]) begin
        aximIntFb <= '0;
        readGapCount <= 0;
        writeGapCount <= 0;
        extraWriteWords <= '0;
        extraWriteCount <= '0;
        extraReadWords <= '0;
        extraReadCount <= '0;
      end
      else begin
        aximIntFb.arready <= 1'b0;
        aximIntFb.bvalid <= 1'b0;
        aximIntFb.rvalid <= 1'b0;
        writeGapCount <= ((writeGapCount>0) ? (writeGapCount-1) : writeGapCount);
        readGapCount <= ((readGapCount>0) ? (readGapCount-1) : readGapCount);
        aximIntFb.awready <= nextWriteReady;
        aximIntFb.wready <= nextWriteReady;
        if (extraWriteWords) begin
          writeGapCount <= WriteGapCycles;
          extraWriteCount <= (extraWriteCount+1);
          extraWriteWords <= (extraWriteWords-1);
          mem[physical_address(aximInt.aw.addr, extraWriteCount)] <= aximInt.w.data;
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: writing %x to %x on port %0d (model addr %x, burst word %0d)", $realtime,
                   aximInt.w.data, (aximInt.aw.addr + (extraWriteCount*MemWidthBytes)), port,
                   physical_address(aximInt.aw.addr, extraWriteCount), extraWriteCount);
          `endif
          if (extraWriteWords == 1) begin
            aximIntFb.bvalid <= 1'b1;
          end
        end
        else if (doingWrite) begin
          writeGapCount <= WriteGapCycles;
          extraWriteWords <= aximInt.aw.len;
          extraWriteCount <= 1;
          aximIntFb.b.id <= aximInt.aw.id;
          aximIntFb.b.resp <= 2'd0;
          aximIntFb.bvalid <= (aximInt.aw.len == 0);
          mem[physical_address(aximInt.aw.addr, 0)] <= aximInt.w.data;
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: writing %x to %x on port %0d (model addr %x)", $realtime,
                   aximInt.w.data, aximInt.aw.addr, port, physical_address(aximInt.aw.addr, 0));
          `endif
        end
        aximIntFb.arready <= (!rAlmostFull && ocsim_pkg::RandPercent(readDutyCycle) && (readGapCount==0) &&
                              !(doingRead && aximInt.ar.len) && !(extraReadWords>1) && !blockRead[port]);
        if (extraReadWords) begin
          readGapCount <= ReadGapCycles;
          extraReadCount <= (extraReadCount+1);
          extraReadWords <= (extraReadWords-1);
          aximIntFb.rvalid <= 1'b1;
          aximIntFb.r.data <= mem[physical_address(aximInt.ar.addr, extraReadCount)];
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: reading %x from %x on port %0d (model addr %x, burst word %0d)", $realtime,
                   mem[physical_address(aximInt.ar.addr, extraReadCount)],
                   (aximInt.ar.addr + (extraReadCount*MemWidthBytes)), port,
                   physical_address(aximInt.ar.addr, extraReadCount), extraReadCount);
          `endif
          if (extraReadWords == 1) begin
            aximIntFb.r.last <= 1'b1;
          end
        end
        else if (doingRead) begin
          readGapCount <= ReadGapCycles;
          extraReadWords <= aximInt.ar.len;
          extraReadCount <= 1;
          aximIntFb.rvalid <= 1'b1;
          aximIntFb.r.id <= aximInt.ar.id;
          aximIntFb.r.last <= (aximInt.ar.len==0);
          aximIntFb.r.resp <= 2'd0;
          aximIntFb.r.data <= mem[physical_address(aximInt.ar.addr, 0)];
          `ifdef OCSIM_AXIM_MEMORY_DEBUG
          $display("%t %m: DEBUG: reading %x from %x on port %0d (model addr %x)", $realtime,
                   mem[physical_address(aximInt.ar.addr, 0)],
                   aximInt.ar.addr, port,
                   physical_address(aximInt.ar.addr, 0));
          `endif
        end
      end
    end

  end // block: aximPort

endmodule // ocsim_axim_memory
