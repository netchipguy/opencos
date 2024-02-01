
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_libraries.vh"

module oclib_synchronizer #(parameter integer Width = 1,
                            parameter integer Enable = 1,
                            parameter integer SyncCycles = 3 )
  (
   input                    clock,
   input [Width-1:0]        in,
   output logic [Width-1:0] out
   );

  if ((Enable == 0) || (SyncCycles==0)) begin
    assign out = in;
  end
  else begin
`ifdef OC_LIBRARY_BEHAVIORAL
    logic [Width-1:0]         pipe [SyncCycles-1:0];
    always @(posedge clock) begin
      for (int i=0; i<SyncCycles; i=i+1) pipe[i] <= ((i == 0) ? in : pipe[i-1]);
    end
    // assign output bus from the end of the data pipe
    assign out = pipe[SyncCycles-1];
`elsif OC_LIBRARY_XILINX
   `OC_STATIC_ASSERT(SyncCycles<=10);
   `OC_STATIC_ASSERT(SyncCycles>=2);
    xpm_cdc_array_single #(.DEST_SYNC_FF(SyncCycles), .INIT_SYNC_FF(0), .SIM_ASSERT_CHK(0),
                           .SRC_INPUT_REG(0), .WIDTH(Width) )
    uXPM (.dest_clk(clock), .dest_out(out), .src_clk(1'b0), .src_in(in) );
`else
    `OC_STATIC_ERROR("Need a library (OC_LIBRARY_*) defined!");
`endif
  end

endmodule // oclib_synchronizer
