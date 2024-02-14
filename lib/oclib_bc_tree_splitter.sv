
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_bc_tree_splitter
  #(
    parameter                        type BcType = oclib_pkg::bc_8b_bidi_s,
    parameter                        type UpProtocol = oclib_pkg::csr_32_s,
    parameter                        type DownProtocol = oclib_pkg::csr_32_s,
    localparam integer               UpProtocolWidth = $bits(UpProtocol), // wave debug
    localparam integer               DownProtocolWidth = $bits(DownProtocol), // wave debug
    parameter bit                    DetectReset = oclib_pkg::False,
    parameter bit                    RequestReset = oclib_pkg::False,
    parameter int                    Outputs = 8,
                                     `OC_LOCALPARAM_SAFE(Outputs),
    localparam integer               BlockIdBits = oclib_pkg::BlockIdBits,
    localparam integer               BlockBytes = (BlockIdBits/8),
    localparam [BlockIdBits-1:0]     DefaultKey = { BlockIdBits {1'b1} },
    localparam [BlockIdBits-1:0]     DefaultMask = { BlockIdBits {1'b0} },
    parameter [BlockBytes-1:0] [7:0] OutputBlockIdKey [0:OutputsSafe-1] = '{ OutputsSafe { DefaultKey } }, // default is output #
    parameter [BlockBytes-1:0] [7:0] OutputBlockIdMask [0:OutputsSafe-1] = '{ OutputsSafe { DefaultMask } }, // default exact match
    parameter integer                SyncCycles = 0,
    parameter bit                    ResetSync = oclib_pkg::False,
    parameter integer                ResetPipeline = 0
    )
  (
   input        clock,
   input        reset,
   input        BcType upIn,
   output       BcType upOut,
   output       BcType downOut [0:OutputsSafe-1],
   input        BcType downIn [0:OutputsSafe-1],
   output logic resetRequest
   );

  // synchronize/pipeline reset as needed
  logic                            resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  logic [BlockBytes-1:0] [7:0] block;
  logic [7:0]                    length;
  logic [7:0]                    counter;
  logic [OutputsSafe-1:0]        mask;

  enum logic [2:0] { StLength, StBlock, StCalcMask,
                     StOutLength, StOutBlock, StOutCopy, StOutCopyWait } state;

  always_ff @(posedge clock) begin
    if (state == StCalcMask) begin
      for (int i=0; i<Outputs; i++) begin
        // by default downOut[0] responds to block 0, downOut[1] to block 1, etc.
        // different addresses can be provided via setting OutputBlockIdKey (say '{2,3,4,5})
        // and different RANGES can be given (for later subdecode) using IdKey (say '{ 'h100, 'h200, 'h400, 'h440} ) and
        // IdMask (say '{ 'hff, 'h1ff, 'h3f, 'h3f })
        mask[i] <= ((OutputBlockIdKey[i] == { BlockIdBits {1'b1} }) ? (block == i) :
                    ((block & ~OutputBlockIdMask[i]) == OutputBlockIdKey[i]));
      end
    end
  end

  BcType downOutInternal;
  BcType downInInternal;

  always_comb begin
    downInInternal = '0;
    for (int i=0; i<Outputs; i++) begin
      downOut[i].data = downOutInternal.data;
      downOut[i].valid = downOutInternal.valid && mask[i];
      // this reverse path vvvv is really bad for now
      downOut[i].ready = downOutInternal.ready;
      if (downIn[i].valid) begin
        downInInternal.valid = 1'b1;
        downInInternal.data = downIn[i].data;
      end
      if (downIn[i].ready && mask[i]) begin
        downInInternal.ready = 1'b1;
      end
    end
  end

  always_ff @(posedge clock) begin
    if (resetSync) begin
      downOutInternal <= '0;
      upOut <= '0;
      block <= '0;
      length <= '0;
      counter <= '0;
      state <= StLength;
      resetRequest <= 1'b0;
    end
    else begin
      case (state)

        // eventually a non valid length here (>112) , such as 126 "~", should signal synchronization
        // and reset operations.  We don't iterate a length >120 and so we are guaranteed to return
        // to initial state if we receive >100 NOPs (or RESET, ID).  We can tunnel these tokens too
        // if we get a 112>length>120.  The BC infra will not trigger until 120 and will treat
        // smaller as a valid message, but it will trigger leaf nodes.

        StLength : begin
          upOut.ready <= 1'b1;
          downOutInternal.valid <= 1'b0;
          counter <= '0;
          if (upIn.valid && upOut.ready) begin
            length <= upIn.data;
            state <= StBlock;
          end
        end // StLength

        StBlock : begin
          upOut.ready <= 1'b1;
          downOutInternal.valid <= 1'b0;
          if (upIn.valid && upOut.ready) begin
            block <= { block[BlockBytes-2:0], upIn.data };
            counter <= (counter + 'd1);
            if (counter == (BlockBytes-1)) begin
              state <= StCalcMask;
            end
          end
        end // StBlock

        StCalcMask : begin
          counter <= 'd0;
          downOutInternal.valid <= 1'b1;
          downOutInternal.data <= length;
          state <= StOutLength;
        end // StCalcMask

        StOutLength : begin
          downOutInternal.valid <= 1'b1;
          if (downOutInternal.valid && downInInternal.ready) begin
            downOutInternal.data <= block[counter];
            //counter <= (counter + 'd1);
            state <= StOutBlock;
          end
        end // StOutLength

        StOutBlock : begin
          downOutInternal.valid <= 1'b1;
          if (downOutInternal.valid && downInInternal.ready) begin
            downOutInternal.data <= block[counter];
            counter <= (counter + 'd1);
            if (counter == (BlockBytes-1)) begin
              // we expect counter be to at 2 (BlockBytes) entering the next state
              state <= StOutCopy;
              downOutInternal.valid <= 1'b0;
              upOut.ready <= 1'b1;
            end
          end
        end // StOutBlock

        StOutCopy : begin
          // we are showing upOut.ready = 1, downOutInternal.valid = 0
          if (upIn.valid) begin
            upOut.ready <= 1'b0;
            downOutInternal.valid <= 1'b1;
            downOutInternal.data <= upIn.data;
            counter <= (counter + 'd1);
            state <= StOutCopyWait;
          end
        end // StOutCopy

        StOutCopyWait : begin
          // we are showing upOut.ready = 0, downOutInternal.valid = 1
          if (downInInternal.ready) begin
            downOutInternal.valid <= 1'b0;
            if (counter == (length-1)) begin
              // for now we are not very smart, we just split the downstream and OR together all the upstream
              // which works only because downstream never speak until spoken to.  Eventually we will want
              // a separate machine listening to the inputs and at least collecting error/interrupt info.
              state <= StLength;
            end
            else begin
              upOut.ready <= 1'b1;
              state <= StOutCopy;
            end
          end
        end // StOutCopyWait

      endcase // case (state)

      // here's the "not very smart" upwards copy logic

      if (!upOut.valid) begin
        // we are not showing any data upwards
        if (downOutInternal.ready && downInInternal.valid) begin
          // we are being give data from downstream
          upOut.valid <= 1'b1;
          upOut.data <= downInInternal.data;
          downOutInternal.ready <= 1'b0; // not accepting more now
        end
        else begin
          downOutInternal.ready <= 1'b1;
        end
      end
      else begin
        // we are showing data upwards
        if (upIn.ready) begin // and it's being accepted
          upOut.valid <= 1'b0;
          downOutInternal.ready <= 1'b1;
        end
      end

    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)


endmodule
