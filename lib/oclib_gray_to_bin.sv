
module oclib_gray_to_bin #(
                           parameter int Width = 8
                           )
  (
   input [Width-1:0]        gray,
   output logic [Width-1:0] bin
   );

  for (genvar i=0; i<Width; i=i+1) begin
    assign bin[i] = ^(gray >> i);
  end

endmodule // oclib_gray_to_bin
