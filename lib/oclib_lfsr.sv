
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"

module oclib_lfsr #(parameter Seed = 1,
                    parameter OutWidth = 32,
                    parameter LfsrWidth = ((OutWidth < 9) ? 9 :
                              (OutWidth < 17) ? 17 :
                              (OutWidth < 33) ? 33 :
                              (OutWidth < 39) ? 39 :
                              65),
                    parameter Poly = ((LfsrWidth == 9) ? 'h110 : // 9th & 5th
                              (LfsrWidth == 17) ? 'h1_2000 : // 17 & 14
                              (LfsrWidth == 33) ? 33'h1_0008_0000 : // 33 & 20
                              (LfsrWidth == 39) ? 39'h44_0000_0000 : // 39 & 35
                              (LfsrWidth == 65) ? 65'h1_0000_4000_0000_0000 : // 65 & 47
                              -1)
                      )
  (
   input                       clock,
   input                       reset,
   input                       enable = 1, // if enable isn't connected, default it to 1
   output logic [OutWidth-1:0] out
   );

  `OC_STATIC_ASSERT(LfsrWidth >= OutWidth);
  `OC_STATIC_ASSERT(Seed != 0);
  `OC_STATIC_ASSERT(Poly[LfsrWidth-1] != 0); // MSB of the Poly must be set
  `OC_STATIC_ASSERT(Poly != -1); // An unknown LfsrWidth has been selected, so a Poly must be supplied

  // based on https://www.xilinx.com/support/documentation/application_notes/xapp052.pdf
  // ... one of the best app notes ever written, I've used it for 25 years now!
  // check there for theory and to add support for more widths, just note that it numbers bits with LSB=1,
  // so subtract 1 from each entry in "XNOR from" column

  logic [LfsrWidth-1:0]         lfsr;
  logic [LfsrWidth-1:0]         lfsr_d;

  // this is somewhat tricky.  we are leaning on synthesis to optimize this, and it will, we'll wind up with
  // one LUT stage of logic feeding each flop.
  always_comb begin
    lfsr_d = lfsr;
    for (int i=0; i<LfsrWidth; i++) begin
      lfsr_d = {lfsr_d[LfsrWidth-2:0], ^~(lfsr_d & Poly)};
    end
  end

  always_ff @(posedge clock) begin
    lfsr <= (reset ? Seed : (enable ? lfsr_d : lfsr));
  end

  assign out = lfsr[OutWidth-1:0];

endmodule // oclib_lfsr
