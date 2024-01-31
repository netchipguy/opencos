// SPDX-License-Identifier: MPL-2.0

`ifndef __OCSIM_DEFINES_VH
`define __OCSIM_DEFINES_VH

`include "lib/oclib_defines.vh"

`define OC_RAND_PERCENT(p) ((({$random}%100000) < (p*1000.0)) ? 1'b1 : 1'b0)
`define OC_RAND_INT_RANGE(a,b) (a + ({$random}%(b-a+1)))

`endif // __OCSIM_DEFINES_VH
