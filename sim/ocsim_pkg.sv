
// SPDX-License-Identifier: MPL-2.0

`ifndef __OCSIM_PKG
`define __OCSIM_PKG

package ocsim_pkg;

  localparam DataTypeZero = 0;
  localparam DataTypeOne = 1;
  localparam DataTypeRandom = 2;

  function string CharToString (input [7:0] data);
    if ((^data) === 1'bX) return "<XX>";
    if ((^data) === 1'bZ) return "<ZZ>";
    if (data == 'h00) return "<00 NULL>";
    if (data == 'h0d) return "<0d CR \\r>";
    if (data == 'h0a) return "<0a LF \\n>";
    if (data == 'h1b) return "<1b ESC>";
    if ((data >= " ") && (data <= "~")) return $sformatf("%c", data);
    return "<?>";
  endfunction // CharToString

  function int RandInt (int minimum, int maximum);
    return minimum + ($urandom % (maximum-minimum+1));
  endfunction // RandInt

  function bit RandPercent (real percent);
    // we make sure 0.0 always returns false and 100.0 always returns true
    return (percent > (real'(RandInt(1,100_000_000-1)) / 1_000_000.0));
  endfunction // RandInt

endpackage // ocsim_pkg


`endif // __OCSIM_PKG
