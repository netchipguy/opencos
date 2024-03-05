
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"

package oclib_memory_bist_pkg;

  localparam MaxAxim = `OC_VAL_ASDEFINED_ELSE(OCLIB_MEMORY_BIST_MAX_AXIM, 32);
  localparam MaxAddressWidth = `OC_VAL_ASDEFINED_ELSE(OCLIB_MEMORY_BIST_MAX_DATA_WIDTH, 34);
  localparam MaxDataWidth = `OC_VAL_ASDEFINED_ELSE(OCLIB_MEMORY_BIST_MAX_DATA_WIDTH, 256);
  localparam AximCountWidth = $clog2(MaxAxim);

  typedef struct packed {
    logic                                go;
    logic [7:0]                          sts_port_select;
    logic [7:0]                          sts_csr_select;
    logic [5:0]                          address_port_shift;
    logic [7:0]                          write_mode;
    logic [7:0]                          read_mode;
    logic [31:0]                         op_count;
    logic [7:0]                          wait_states;
    logic [3:0]                          burst_length;
    logic [MaxAxim-1:0]                  axim_enable;
    logic [7:0]                          read_max_id;
    logic [7:0]                          write_max_id;
    logic [MaxAddressWidth-1:0]          address;
    logic [MaxAddressWidth-1:0]          address_inc;
    logic [MaxAddressWidth-1:0]          address_inc_mask;
    logic [MaxAddressWidth-1:0]          address_random_mask;
    logic [AximCountWidth-1:0]           address_port_mask;
    logic [(MaxDataWidth/8)-1:0] [7:0]   data;
  } cfg_s;

  typedef struct packed {
    logic                                done;
    logic [31:0]                         signature;
    logic [31:0]                         error;
    logic [31:0]                         rdata;
    logic [(MaxDataWidth/8)-1:0] [7:0]   data;
  } sts_s;

endpackage // oclib_memory_bist_pkg
