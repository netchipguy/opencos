
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_csr_check_selected
  #(
    parameter        type CsrType = oclib_pkg::csr_32_noc_s,
    parameter [31:0] AnswerToBlock = oclib_pkg::BcBlockIdAny,
    parameter [3:0]  AnswerToSpace = oclib_pkg::BcSpaceIdAny
    )
  (
   input        csrSelect = 1'b1,
   input        CsrType csr,
   output logic match
   );

  logic         matchBlock;

  if ((type(CsrType) == type(oclib_pkg::csr_32_noc_s)) ||
      (type(CsrType) == type(oclib_pkg::csr_32_tree_s))) begin

    // this is what we want to do:
    // assign matchBlock = ((AnswerToBlock == oclib_pkg::BcBlockIdAny) || (csr.toblock == AnswerToBlock));

    // but SystemVerilog won't let us access csr.toblock, even in this "if" block where we know it
    // exists.  some tools are OK with this but some not, so we avoid it.  the key is to remember
    // that when routing serial messages we ALSO need to know the block, and we don't want to parse
    // the message, so the block is always at the FRONT (i.e. left).

    localparam CsrWidth = $bits(csr);
    assign matchBlock = ((AnswerToBlock == oclib_pkg::BcBlockIdAny) || (csr[CsrWidth-1:CsrWidth-32] == AnswerToBlock));

  end
  else begin
    assign matchBlock = oclib_pkg::True;
  end

  assign match = (csrSelect &&
                  ((AnswerToSpace == oclib_pkg::BcSpaceIdAny) || (csr.space == AnswerToSpace)) &&
                  matchBlock);

endmodule // oclib_csr_check_selected
