
// SPDX-License-Identifier: MPL-2.0

module oclib_debounce #(
                      parameter Cycles = 100,
                      parameter ResetSync = 0
                      )
  (
   input clock,
   input reset,
   input in,
   output logic out
   );

  wire                             resetQ;
  oclib_synchronizer #(.Enable(ResetSync)) uRESET_SYNC (clock, reset, resetQ);

  localparam CounterW = $clog2(Cycles+1);
  logic [CounterW-1:0] counter;
  logic                inQ;
  logic                counterTC;

  oclib_synchronizer uSYNC (clock, in, inQ);

  always_ff @(posedge clock) begin
    counterTC <= (counter >= Cycles);
    if (resetQ) begin
      counter <= '0;
      out <= inQ;
    end
    else begin
      case (out)
        1'b0 : begin // we are currently outputting zero
          if (inQ) begin // we are receiving a one
            if (counterTC) begin // and have been for long enough
              out <= 1'b1;
              counter <= '0;
            end
            else begin
              counter <= (counter + 'd1);
            end
          end
          else begin // we are receiving a zero
            counter <= '0;
          end
        end
        1'b1 : begin
          if (inQ) begin // we are receiving a one
            counter <= '0;
          end
          else begin // we are receiving a zero
            if (counterTC) begin // and have been for long enough
              out <= 1'b0;
              counter <= '0;
            end
            else begin
              counter <= (counter + 'd1);
            end
          end
        end
      endcase // case (out)
    end // else: !if(reset)
  end

endmodule // oclib_debounce
