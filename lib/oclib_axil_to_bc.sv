
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

// Takes a 256-byte space in the AXIL
//    0 - 127 : blocking data port, one 32-bit port aliased 32 times to allow up to 128B burst access
//  128 - 191 : non-blocking control debug port, reading provides state of signals, never blocks, doesn't consume IN_FIFO data
//  192 - 255 : non-blocking access port, provides complete state as above, but a read will consume any data showing on IN_FIFO

module oclib_axil_to_bc
  #(
    parameter     type AxilType = oclib_pkg::axil_32_s,
    parameter     type AxilFbType = oclib_pkg::axil_32_fb_s,
    parameter     type BcType = oclib_pkg::bc_8b_bidi_s,
    parameter bit InFifoEnable = oclib_pkg::True,
    parameter int InFifoDepth = (InFifoEnable ? 32 : 0),
    parameter bit OutFifoEnable = oclib_pkg::True,
    parameter int OutFifoDepth = (OutFifoEnable ? 32 : 0),
    // the AFULL signals will tell us whether it's safe to burst 8 bytes in or out
    parameter int InFifoAlmostFullThresh = 8,
    parameter int OutFifoAlmostFullThresh = (OutFifoDepth - 8),
    parameter integer SyncCycles = 3,
    parameter bit ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input  clock,
   input  reset,
   input  AxilType axil,
   output AxilFbType axilFb,
   output BcType bcOut,
   input  BcType bcIn
   );

  logic                         resetSync;

  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  enum                          logic [3:0] { StIdle, StReadControl, StReadData, StReadAck,
                                              StWriteControl, StWriteData, StWriteAck } state;

  BcType bcFifoOut, bcFifoIn;
  logic outFifoAlmostFull;
  logic inFifoAlmostFull;
  logic [9:0] stallCounter;
  logic       stallTimeout;
  assign stallTimeout = (&stallCounter);

  always_ff @(posedge clock) begin
    if (resetSync) begin
      bcFifoOut <= '0;
      state <= StIdle;
      axilFb <= '0;
      stallCounter <= '0;
    end
    else begin
      bcFifoOut <= '0;
      stallCounter <= '0;
      case (state)
        StIdle : begin
          axilFb <= '0;
          if (axil.awvalid) begin
            state <= (axil.awaddr[7] ? StWriteControl : StWriteData);
            axilFb.awready <= 1'b1;
          end
          else if (axil.arvalid) begin
            state <= (axil.araddr[7] ? StReadControl : StReadData);
            axilFb.arready <= 1'b1;
          end
        end
        StWriteControl : begin
          axilFb <= '0;
          // awvalid&&awready is asserted, we have one cycle to use the address, right now don't need it
          if (axil.wvalid) begin
            // we don't do anything on control writes for now.  I'm sure stuff will eventually wind up here
            axilFb.wready <= 1'b1;
            axilFb.bvalid <= 1'b1;
            axilFb.bresp <= 'd0;
            state <= StWriteAck;
          end
        end
        StWriteData : begin
          axilFb <= '0;
          // awvalid&&awready is asserted, we have one cycle to use the address, right now don't need it
          if (axil.wvalid && bcFifoIn.ready) begin
            axilFb.wready <= 1'b1;
            axilFb.bvalid <= 1'b1;
            axilFb.bresp <= 'd0;
            bcFifoOut.data <= axil.wdata[7:0];
            bcFifoOut.valid <= 1'b1; // we already checked we have ready, which from FIFO can't go away
            state <= StWriteAck;
          end
        end
        StWriteAck : begin
          // maintaining previous axilFb...
          axilFb.wready <= 1'b0;
          if (axil.bready) begin
            axilFb.bvalid <= 1'b0;
            state <= StIdle;
          end
        end
        StReadControl : begin
          // this is a non blocking read of pretty much all the state
          // arvalid&&arready is asserted, we have one cycle to use the address
          axilFb <= '0;
          axilFb.rvalid <= 1'b1;
          axilFb.rdata <= { 6'd0, inFifoAlmostFull, outFifoAlmostFull,                // 25:24
                            4'd0, bcIn.valid, bcIn.ready, bcOut.valid, bcOut.ready,   // 19:16
                            7'd0, bcFifoIn.valid,                                     // 8
                            bcFifoIn.data};                                           // 7:0
          bcFifoOut.ready <= axil.araddr[6]; // in the upper part of the control range we ack
          state <= StReadAck;
        end
        StReadData : begin
          // this is a blocking read of the control FIFO
          // arvalid&&arready is asserted, we have one cycle to use the address
          axilFb <= '0;
          bcFifoOut.ready <= 1'b1;
          stallCounter <= (stallCounter + 1);
          axilFb.rdata <= { 6'd0, inFifoAlmostFull, outFifoAlmostFull,                // 25:24
                            8'd0,
                            stallTimeout, 6'd0, bcFifoIn.valid, // indicate timeout   // 15,8
                            bcFifoIn.data};                                           // 7:0
          if (stallTimeout || (bcFifoIn.valid && bcFifoOut.ready)) begin
            bcFifoOut.ready <= 1'b0;
            axilFb.rvalid <= 1'b1;
            state <= StReadAck;
          end
        end
        StReadAck : begin
          // maintaining previous axilFb...
          if (axil.rready) begin
            axilFb.rvalid <= 1'b0;
            state <= StIdle;
          end
        end
      endcase // case (state)
    end
  end

  oclib_fifo #(.Width($bits(bcFifoOut.data)), .Depth(InFifoDepth), .AlmostFull(InFifoAlmostFullThresh))
  uIN_FIFO (.clock(clock), .reset(resetSync), .almostFull(inFifoAlmostFull),
            .inData(bcFifoOut.data), .inValid(bcFifoOut.valid), .inReady(bcFifoIn.ready),
            .outData(bcOut.data), .outValid(bcOut.valid), .outReady(bcIn.ready));

  oclib_fifo #(.Width($bits(bcIn.data)), .Depth(OutFifoDepth), .AlmostFull(OutFifoAlmostFullThresh))
  uOUT_FIFO (.clock(clock), .reset(resetSync), .almostFull(outFifoAlmostFull),
            .inData(bcIn.data), .inValid(bcIn.valid), .inReady(bcOut.ready),
            .outData(bcFifoIn.data), .outValid(bcFifoIn.valid), .outReady(bcFifoOut.ready));

endmodule // oclib_axil_to_bc
