
// SPDX-License-Identifier: MPL-2.0

module oclib_fpga_serial #(
                           parameter integer SerialBits = 96
                           )
  (
   input                         clock,
   input                         reset,
   output logic [SerialBits-1:0] serial
   );

`ifdef SIMULATION
  assign serial = 32'h01234567;
`elsif OC_LIBRARY_ULTRASCALE_PLUS

  logic                           dna_dout;
  logic                           shift;

  DNA_PORTE2 uDNA (.DIN(1'b0),
                   .READ(reset),
                   .SHIFT(shift),
                   .CLK(clock),
                   .DOUT(dna_dout));

  localparam CountW = $clog2(SerialBits+2); // there are TWO LSBs (01) that are fixed for framing
  logic [CountW-1:0]              counter;

  always_ff @(posedge clock) begin
    if (reset) begin
      shift <= 1'b0;
      counter <= '0;
      serial <= '0;
    end
    else begin
      if (counter != (SerialBits+1)) begin // remember we need to shift two extra times to get rid of framing
        shift <= 1'b1;
        serial <= {dna_dout, serial[SerialBits-1:1]};
        counter <= (counter + 'd1);
      end
      else begin
        shift <= 1'b0;
      end
    end
  end

`endif

endmodule // oclib_fpga_serial
