
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oclib_axil_demux
  #(
    parameter                   type AxilType = oclib_pkg::axil_32_s,
    parameter                   type AxilFbType = oclib_pkg::axil_32_fb_s,
    parameter int               AddressBits = 32,
    parameter [AddressBits-1:0] SelectBAddress = (1 << (AddressBits-1)),
    parameter [AddressBits-1:0] SelectBMask = { 1'b1 , {AddressBits-1{1'b0}} }
    )
  (
   input  clock,
   input  reset,
   input  AxilType axilIn,
   output AxilFbType axilInFb,
   output AxilType axilA,
   input  AxilFbType axilAFb,
   output AxilType axilB,
   input  AxilFbType axilBFb
   );

  logic   bSelectRead;
  logic   bSelectWrite;

  assign bSelectRead = ((axilIn.araddr & SelectBMask) == (SelectBAddress & SelectBMask));
  assign bSelectWrite = ((axilIn.awaddr & SelectBMask) == (SelectBAddress & SelectBMask));

  logic   readingA;
  logic   writingA;
  logic   readingB;
  logic   writingB;

  always_comb begin
    axilA = axilIn;
    axilB = axilIn;
    axilA.awvalid = (writingA && axilIn.awvalid);
    axilA.wvalid  = (writingA && axilIn.wvalid);
    axilA.bready  = (writingA && axilIn.bready);
    axilA.arvalid = (readingA && axilIn.arvalid);
    axilA.rready  = (readingA && axilIn.rready);
    axilB.awvalid = (writingB && axilIn.awvalid);
    axilB.wvalid  = (writingB && axilIn.wvalid);
    axilB.bready  = (writingB && axilIn.bready);
    axilB.arvalid = (readingB && axilIn.arvalid);
    axilB.rready  = (readingB && axilIn.rready);
    axilInFb = ((writingA || readingA) ? axilAFb :
                (writingB || readingB) ? axilBFb :
                '0);
  end

  enum    logic [1:0] { StIdle, StRead, StWrite } state;

  always_ff @(posedge clock) begin
    if (reset) begin
      state <= StIdle;
      readingA <= 1'b0;
      readingB <= 1'b0;
      writingA <= 1'b0;
      writingB <= 1'b0;
    end
    else begin
      case (state)
        StIdle : begin
          readingA <= 1'b0;
          readingB <= 1'b0;
          writingA <= 1'b0;
          writingB <= 1'b0;
          if (axilIn.arvalid) begin
            readingA <= !bSelectRead;
            readingB <= bSelectRead;
            state <= StRead;
          end
          else if (axilIn.awvalid) begin
            writingA <= !bSelectWrite;
            writingB <= bSelectWrite;
            state <= StWrite;
          end
        end
        StRead : begin
          if (axilInFb.rvalid && axilIn.rready) begin
            state <= StIdle;
          end
        end
        StWrite : begin
          if (axilInFb.bvalid && axilIn.bready) begin
            state <= StIdle;
          end
        end
      endcase // case (state)
    end
  end

endmodule // oclib_axil_demux

