
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"

`ifndef __OC_BOARD_DEFINES_VH
`define __OC_BOARD_DEFINES_VH

// if OC_BOARD_SEED isn't already defined, set it to OC_SEED if that's defined, else 1
`OC_IFNDEFDEFINE_TO(OC_SEED, 1)
`OC_IFNDEFDEFINE_TO(OC_BOARD_SEED, `OC_SEED)

`OC_IFDEF_DEFINE(OC_BOARD_PCIE_X16, OC_BOARD_PCIE_X8)
`OC_IFDEF_DEFINE(OC_BOARD_PCIE_X8, OC_BOARD_PCIE_X4)
`OC_IFDEF_DEFINE(OC_BOARD_PCIE_X4, OC_BOARD_PCIE_X2)
`OC_IFDEF_DEFINE(OC_BOARD_PCIE_X2, OC_BOARD_PCIE_X1)

`endif // __OC_BOARD_DEFINES_VH
