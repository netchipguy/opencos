

// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_bc_adapter
  #(
    parameter type BcTypeA = oclib_pkg::bc_8b_bidi_s,
    parameter type BcTypeB = oclib_pkg::bc_8b_bidi_s,
    parameter bit AlwaysBuffer = 0
    )
  (
   input  clock,
   input  reset,
   input  BcTypeA aIn,
   output BcTypeA aOut,
   input  BcTypeB bIn,
   output BcTypeB bOut
   );

  if (type(BcTypeA) == type(BcTypeB)) begin
    assign bOut = aIn;
    assign aOut = bIn;
  end

endmodule // oclib_bc_adapter
