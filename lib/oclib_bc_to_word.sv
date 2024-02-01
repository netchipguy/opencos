
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_bc_to_word
 #(
   parameter integer WordWidth = 64,
   parameter integer ShiftFanout = 16,
   parameter integer SyncCycles = 3,
   parameter bit     ResetSync = oclib_pkg::False,
   parameter integer ResetPipeline = 0,
   parameter bit     PrefixLength = oclib_pkg::True
  )
  (
   input                        clock,
   input                        reset,
   input                        oclib_pkg::bc_8b_s bc,
   output                       oclib_pkg::bc_8b_fb_s bcFb,
   output logic [WordWidth-1:0] wordData,
   output logic                 wordValid,
   input                        wordReady
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // Datapath Logic
  logic                     byteShift;
  logic                     byteShiftDone;
  // this shift may be very wide (thousands of bits) and very fast (>500MHz) so we can't fanout a single
  // shift_enable to all those flops.  Instead, we divide into "shift groups" and then shift the leftmost
  // group first, then a cycle later then next left-most, etc, until we are shifting our new byte into
  // the rightmost bits.  therefore, the first byte winds up in the leftmost (MSB) bits.  also note that
  // taking several cycles to shift is assumed to not be a problem, as this is coming from some slow interface
  // off-chip (even PCIe would be giving us 4 bytes every 200ns or so).
  localparam integer ShiftGroups = ((WordWidth+ShiftFanout-1)/ShiftFanout);
  logic [ShiftGroups-1:0] byteShiftPipe;
  always_ff @(posedge clock) begin
    byteShiftPipe <= {byteShift,byteShiftPipe[ShiftGroups-1:1]}; // shift leftmost bits first
    for (int i=WordWidth-1; i>=8; i--) begin
      wordData[i] <= (byteShiftPipe[(i/ShiftFanout)] ? wordData[i-8] : wordData[i]);
    end
    for (int i=7; i>=0; i--) begin
      wordData[i] <= (byteShiftPipe[0] ? bc.data[i] : wordData[i]);
    end
  end
  assign byteShiftDone = byteShiftPipe[0]; // we are done when the rightmost bits are shifting

  // Control Logic
  localparam integer WordBytes = ((WordWidth+7)/8);
  localparam ByteCounterW = $clog2(WordBytes);

  logic [ByteCounterW-1:0]  length;
  logic [ByteCounterW-1:0]  byteCounter;
  logic                     byteCounterTC;
  enum                      logic [1:0] { StIdle, StShift, StNext, StDone } state;

  always_ff @(posedge clock) begin
    byteCounterTC <= (byteCounter == (PrefixLength ? (length-2) : (WordBytes-1)));
    if (resetSync) begin
      bcFb.ready <= 1'b0;
      wordValid <= 1'b0;
      byteCounter <= '0;
      length <= WordBytes;
      state <= StIdle;
    end
    else begin
      bcFb.ready <= 1'b0;
      byteShift <= 1'b0;
      wordValid <= (wordValid && !wordReady);
      case (state)

        StIdle : begin
          byteCounter <= '0;
          if (bc.valid && ~wordValid) begin
            if (PrefixLength) begin
              length <= bc.data;
              state <= StNext;
              bcFb.ready <= 1'b1;
            end
            else begin
              byteShift <= 1'b1;
              state <= StShift;
            end
          end
        end // StIdle

        StShift : begin
          if (byteShiftDone) begin
            bcFb.ready <= 1'b1;
            byteCounter <= (byteCounter + 'd1);
            if (byteCounterTC) begin
              wordValid <= 1'b1;
              state <= StDone;
            end
            else begin
              state <= StNext;
            end
          end
        end // StShift

        StNext : begin
          if (bc.valid && ~bcFb.ready) begin
            byteShift <= 1'b1;
            state <= StShift;
          end
        end // StNext

        StDone : begin
          if (wordReady) begin
            state <= StIdle;
          end
        end // StDone

      endcase // case (state)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_bc_to_word
