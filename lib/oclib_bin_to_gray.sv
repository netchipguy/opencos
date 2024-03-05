
module oclib_bin_to_gray #(
                           parameter int Width = 8
                           )
  (
   input [Width-1:0]        bin,
   output logic [Width-1:0] gray
   );

  for (genvar i=0; i<(Width-1); i=i+1) begin
    assign gray[i] = (bin[i] ^ bin[i+1]);
  end
  assign gray[Width-1] = bin[Width-1];

endmodule // oclib_bin_to_gray
