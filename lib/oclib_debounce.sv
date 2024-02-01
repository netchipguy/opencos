
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_debounce #(
                      parameter integer DebounceCycles = 100,
                      parameter integer SyncCycles = 3,
                      parameter bit     ResetSync = oclib_pkg::False,
                      parameter integer ResetPipeline = 0
                      )
  (
   input        clock,
   input        reset,
   input        in,
   output logic out
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  localparam CounterW = $clog2(DebounceCycles+1);
  logic [CounterW-1:0] counter;
  logic                inSync;
  logic                counterTC;

  oclib_synchronizer #(.SyncCycles(SyncCycles))
  uSYNC (.clock(clock), .in(in), .out(inSync));

  always_ff @(posedge clock) begin
    counterTC <= (counter >= DebounceCycles);
    if (resetSync) begin
      counter <= '0;
      out <= inSync;
    end
    else begin
      case (out)

        1'b0 : begin // we are currently outputting zero
          if (inSync) begin // we are receiving a one
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
        end // out == 1'b0

        1'b1 : begin
          if (inSync) begin // we are receiving a one
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
        end // out == 1'b1

      endcase // case (out)
    end // else: !if(reset)
  end // always_ff @ (posedge clock)

endmodule // oclib_debounce
