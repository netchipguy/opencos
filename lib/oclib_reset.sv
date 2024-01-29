
// SPDX-License-Identifier: MPL-2.0

module oclib_reset #(
                   parameter integer StartPipeCycles = 8,
                   parameter integer ResetCycles = 32,
                   parameter integer ResetPipeFlops = 0, // set this to distribute reset widely, but lose async reset assertion
                   parameter bit ResetInActiveLow = 1'b0,
                   parameter bit ResetOutActiveLow = 1'b0
                   )
  (
   input        clock,
   input        in = ResetInActiveLow, // in FPGA, this can be tied off "deasserted" and will still assert once after clocks start
   output logic out
   );

  // First, we generate resetLocal, which asserts immediately at both power up and assertion of reset "in".
  // resetLocal will deassert synchronously after StartPipeCycles, which is a pipeline that provides for
  // metastability resolution as well as just ignoring the first couple of clock pulses which maybe unreliable.
  (* dont_touch = "true", shreg_extract = "no" *)
  logic [StartPipeCycles-1:0] startPipe = '0; // should cause auto-reset at bitfile load
  logic resetLocal;
  logic resetInActiveHigh;
  assign resetInActiveHigh = (ResetInActiveLow ? ~in : in);
  always_ff @(posedge clock or posedge resetInActiveHigh) begin // resetInActiveHigh: assert and deassert async
    if (resetInActiveHigh) startPipe <= '0;
    else startPipe <= {startPipe[StartPipeCycles-2:0], 1'b1};
  end
  assign resetLocal = ~startPipe[StartPipeCycles-1];

  // Second, we optionally stretch the clock to ensure it is ResetCycles in length, creating resetStretched.
  // resetStretched also asserts asynchronously, and deasserts synchronously.  Fundamentally, it uses a
  // counter (instead of a shift register) hence requires a synchronous-deasserting reset (resetLocal) but
  // can generate much longer reset pulses -- scaling O(logN) instead of O(N)
  logic                resetStretched;
  if (ResetCycles) begin
    localparam CounterW = $clog2(ResetCycles);
    logic [CounterW-1:0] resetCount;
    logic                resetOutActiveHigh;
    assign resetStretched = (ResetOutActiveLow ? ~resetOutActiveHigh: resetOutActiveHigh);
    always_ff @(posedge clock or posedge resetLocal) begin // resetLocal: assert async, deassert sync
      if (resetLocal) begin
        resetOutActiveHigh <= 1'b1;
        resetCount <= '0;
      end
      else if (resetCount == (ResetCycles-1)) begin
        resetOutActiveHigh <= 1'b0;
      end
      else begin
        resetCount <= (resetCount + 'd1);
      end
    end
  end
  else begin
    assign resetStretched = resetLocal;
  end

  // Finally, we optionally add a few simple pipeline flops at the end of the above.
  // Giving a couple of extra "pipe flops" at the end lets the router duplicate the flops, but we lose the
  // async assertion capability. Will need to experiment to see if there's a way to retain this, as it's
  // nice to be able to assure that reset will assert regardless of clock, that logic won't see several
  // clocks before reset asserts, etc.
  if (ResetPipeFlops) begin
    logic [ResetPipeFlops-1:0] resetPipe;
    always_ff @(posedge clock) begin
      if (resetLocal) resetPipe <= '0;
      else resetPipe <= { resetPipe, resetStretched };
    end
    assign out = resetPipe[ResetPipeFlops-1];
  end
  else begin
    assign out = resetStretched;
  end

endmodule // oclib_reset
