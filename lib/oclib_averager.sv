
// SPDX-License-Identifier: MPL-2.0

module oclib_averager #(parameter InWidth = 1,
                        parameter OutWidth = 9,
                        parameter TimeShift = 8)
  (
   input                       clock,
   input                       reset,
   input [InWidth-1:0]         in,
   input                       inValid = 1'b1,
   output logic [OutWidth-1:0] out
   );

  localparam TotalWidth = OutWidth + TimeShift;
  localparam InShift = (OutWidth - InWidth);

  logic [TotalWidth-1:0]           outFull;
  logic [TotalWidth:0]             outFullInc;
  logic [TotalWidth:0]             outFullDec;

  always @(posedge clock) begin
    if (reset) begin
      outFull <= '0;
    end
    else if (inValid) begin
      outFull <= outFullDec[TotalWidth-1:0];
    end
  end

  assign out = (outFull >> TimeShift);
  assign outFullInc = ({1'b0,outFull} + (inValid ? { in , {InShift{1'b0}} } : '0));
  assign outFullDec = (outFullInc - (outFull >> TimeShift));

endmodule // lib_average
