
// SPDX-License-Identifier: MPL-2.0

module oclib_pulse_stretcher #(parameter integer Width = 1, // each input will be stretched independently to each output
                               parameter integer Cycles = 1000 ) // tip: set to your ClockHz param for a 1 second pulse
  (
   input                    clock,
   input                    reset,
   input [Width-1:0]        in,
   output logic [Width-1:0] out
   );

  if (Cycles < 2) begin
    assign out = in;
  end
  else begin
    localparam               CounterWidth = $clog2(Cycles);
    logic [CounterWidth-1:0] counter [Width-1:0];
    always @(posedge clock) begin
      for (int i=0; i<Width; i++) begin
        out[i] <= |(counter[i]);
        if (reset) begin
          counter[i] <= '0;
        end
        else if (in) begin
          counter[i] <= Cycles-1;
        end
        else begin
          counter[i] <= ((|counter[i]) ? (counter[i]-1) : '0);
        end
      end // for (int i=0; i<Width; i++)
    end // always @ (posedge clock)
  end // else: !if(Cycles < 2)

endmodule // oclib_pulse_stretcher
