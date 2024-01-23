
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_libraries.vh"

`ifndef __OC_BOARD_DEFINES_VH
`define __OC_BOARD_DEFINES_VH

// if OC_BOARD_SEED isn't already defined, set it to OC_SEED if that's defined, else 1
`OC_IFNDEFDEFINE_TO(OC_BOARD_SEED, `OC_VAL_ASDEFINED_ELSE(OC_SEED, 1))

`endif // __OC_BOARD_DEFINES_VH
