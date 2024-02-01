
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_word_to_bc
  #(
    parameter integer WordWidth = 64,
    parameter integer ShiftFanout = 16,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0,
    parameter bit     PrefixLength = oclib_pkg::True
    )
  (
   input                 clock,
   input                 reset,
   input [WordWidth-1:0] wordData,
   input                 wordValid,
   output logic          wordReady,
   output                oclib_pkg::bc_8b_s bc,
   input                 oclib_pkg::bc_8b_fb_s bcFb
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  localparam integer WordBytes = ((WordWidth+7)/8);
  localparam ByteCounterW = $clog2(WordBytes);

  // Datapath Logic
  logic [ByteCounterW-1:0] byteCounter;
  logic [7:0]              byteSelected;
  logic [0:WordBytes-1] [7:0] wordAsBytes; // note reversed order, we want byte 0 to be MSBs
  assign wordAsBytes = wordData;
  always_ff @(posedge clock) begin
    byteSelected <= wordAsBytes[byteCounter];
  end

  // Control Logic
  logic                     byteCounterTC;
  logic                     lengthByte;
  enum                      logic [1:0] { StIdle, StLoad, StNext, StDone } state;

  always_ff @(posedge clock) begin
    byteCounterTC <= (byteCounter == (WordBytes-1));
    if (resetSync) begin
      bc.data <= '0;
      bc.valid <= 1'b0;
      wordReady <= 1'b0;
      byteCounter <= '0;
      lengthByte <= 1'b0;
      state <= StIdle;
    end
    else begin
      wordReady <= 1'b0;
      bc.valid <= (bc.valid && !bcFb.ready);
      case (state)
        StIdle : begin
          byteCounter <= '0;
          if (wordValid && ~bc.valid && ~wordReady) begin
            state <= StLoad;
            lengthByte <= PrefixLength;
          end
        end
        StLoad : begin
          bc.valid <= 1'b1;
          if (lengthByte) begin
            bc.data <= (WordBytes+1);
            lengthByte <= 1'b0;
            state <= StNext;
          end else begin
            bc.data <= byteSelected;
            byteCounter <= (byteCounter + 'd1);
            state <= (byteCounterTC ? StDone : StNext);
          end
        end
        StNext : begin // during this cycle, the byteCounter is used to latch next into byteSelected
          if (bcFb.ready) begin
            state <= StLoad;
          end
        end
        StDone : begin
          if (bcFb.ready) begin
            wordReady <= 1'b1;
            state <= StIdle;
          end
        end
      endcase // case (state)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_word_to_bc
