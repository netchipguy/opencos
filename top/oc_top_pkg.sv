
`ifndef __OC_TOP_PKG
`define __OC_TOP_PKG


package oc_top_pkg;

  // ********************
  // Clock Identification
  //   0- 99         Single-ended Refclks
  // 100-199         Differential Refclks
  // 200-299         PLL Clocks
  // ********************

  parameter integer ClockIdSingleEndedRefBase = 0;
  parameter integer ClockIdDifferentialRefBase = 100;
  parameter integer ClockIdPllBase = 200;

  function integer ClockIdSingleEndedRef(input int i);
    return ClockIdSingleEndedRefBase + i;
  endfunction

  function integer ClockIdDifferentialRef(input int i);
    return ClockIdDifferentialRefBase + i;
  endfunction

  function integer ClockIdPllClock(input int i);
    return ClockIdPllBase + i;
  endfunction

endpackage // oc_top_pkg


`endif // __OC_TOP_PKG
