
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_pipeline #(parameter integer Width = 1,
                        parameter integer Length = 0,
                        parameter bit     DontTouch = oclib_pkg::False,
                        parameter bit     NoShiftRegister = oclib_pkg::False
                        )
  (
   input                    clock,
   input [Width-1:0]        in,
   output logic [Width-1:0] out
   );

  if (Length) begin
    // TODO: validate these do what they are expected to do
    (* dont_touch = (DontTouch ? "true" : "false"),
     shreg_extract = ((NoShiftRegister || (Length==1)) ? "false" : "true") *)
    logic [Width-1:0] inPipe [Length-1:0];
    always_ff @(posedge clock) begin
      for (int i=0; i<Length; i++) begin
        inPipe[i] <= ((i==0) ? in : inPipe[i-1]);
      end
    end
    assign out = inPipe [Length-1];
  end
  else begin
    assign out = in;
  end

endmodule // oclib_pipeline
