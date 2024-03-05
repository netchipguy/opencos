
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_bc_mux #(
                      parameter     type BcType = oclib_pkg::bc_8b_bidi_s,
                      parameter int SyncCycles = 3,
                      parameter bit ResetSync = oclib_pkg::False,
                      parameter int ResetPipeline = 0
                      )
  (
   input  clock,
   input  reset,
   input  BcType aIn,
   output BcType aOut,
   input  BcType bIn,
   output BcType bOut,
   output BcType muxOut,
   input  BcType muxIn
   );

  logic   resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  logic   lastWasB;
  enum    logic [1:0] { MuxIdle, MuxSend } muxState;
  enum    logic [1:0] { DemuxIdle, DemuxSendA, DemuxSendB } demuxState;

  always_ff @(posedge clock) begin
    if (resetSync) begin
      aOut <= '0;
      bOut <= '0;
      muxOut <= '0;
      muxState <= MuxIdle;
      demuxState <= DemuxIdle;
      lastWasB <= oclib_pkg::False;
    end
    else begin
      aOut.ready <= 1'b0;
      bOut.ready <= 1'b0;
      muxOut.ready <= 1'b0;
      case (muxState)
        MuxIdle: begin
          if (aIn.valid) begin
            aOut.ready <= 1'b1;
            muxOut.data <= aIn.data;
            muxOut.valid <= 1'b1;
            muxState <= MuxSend;
            lastWasB <= oclib_pkg::False;
          end
          else if (bIn.valid) begin
            bOut.ready <= 1'b1;
            muxOut.data <= bIn.data;
            muxOut.valid <= 1'b1;
            muxState <= MuxSend;
            lastWasB <= oclib_pkg::True;
          end
        end
        MuxSend: begin
          if (muxIn.ready) begin
            muxState <= MuxIdle;
            muxOut.valid <= 1'b0;
          end
        end
      endcase

      case (demuxState)
        DemuxIdle: begin
          if (muxIn.valid) begin
            muxOut.ready <= 1'b1;
            if (lastWasB) begin
              bOut.data <= muxIn.data;
              bOut.valid <= 1'b1;
              demuxState <= DemuxSendB;
            end
            else begin
              aOut.data <= muxIn.data;
              aOut.valid <= 1'b1;
              demuxState <= DemuxSendA;
            end
          end
        end
        DemuxSendA: begin
          if (aIn.ready) begin
            demuxState <= DemuxIdle;
            aOut.valid <= 1'b0;
          end
        end
        DemuxSendB: begin
          if (bIn.ready) begin
            demuxState <= DemuxIdle;
            bOut.valid <= 1'b0;
          end
        end
      endcase

    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_bc_mux
