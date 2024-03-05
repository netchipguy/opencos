
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oclib_module_reset #(
                            parameter int SyncCycles = 3,
                            parameter bit ResetSync = oclib_pkg::False,
                            parameter int ResetPipeline = 0,
                            parameter bit DontTouch = oclib_pkg::True,
                            parameter bit NoShiftRegister = oclib_pkg::True
                            )
  (
   input        clock,
   input        in,
   output logic out
   );

  logic                     inSync;
  oclib_synchronizer #(.Enable(ResetSync), .SyncCycles(SyncCycles))
  uSYNC (.clock(clock), .in(in), .out(inSync));

  oclib_pipeline #(.Length(ResetPipeline), .DontTouch(DontTouch), .NoShiftRegister(NoShiftRegister))
  uPIPE (.clock(clock), .in(inSync), .out(out));

endmodule // oclib_module_reset
