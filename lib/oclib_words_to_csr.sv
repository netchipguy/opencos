
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module oclib_words_to_csr
  #(
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input        clock,
   input        reset,
   input        CsrType wordInData,
   input        wordInValid,
   output logic wordInReady,
   output       CsrFbType wordOutData,
   output logic wordOutValid,
   input        wordOutReady,
   output       CsrType csr,
   input        CsrFbType csrFb
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // request data
  CsrType        csrFromWord;
  logic          csrReadOut;
  logic          csrWriteOut;
  always_comb begin
    csrFromWord = wordInData;
    csr = wordInData;
    csr.read = csrReadOut;
    csr.write = csrWriteOut;
  end

  // response data
  always_ff @(posedge clock) begin
    if (csrFb.ready) begin
      wordOutData <= csrFb;
    end
  end

  // state machine
  enum logic [1:0] { StIdle, StWait, StResp } state;

  always_ff @(posedge clock) begin
    if (resetSync) begin
      csrReadOut <= 1'b0;
      csrWriteOut <= 1'b0;
      wordInReady <= 1'b0;
      wordOutValid <= 1'b0;
      wordOutData <= '0; // we reset whole word as it may have strobes like "ready"
      state <= StIdle;
    end
    else begin
      if (csrFb.ready) wordOutData <= csrFb;

      case (state)

        StIdle : begin
          wordInReady <= 1'b1;
          if (wordInValid && wordInReady) begin
            csrReadOut <= csrFromWord.read;
            csrWriteOut <= csrFromWord.write;
            state <= StWait;
            wordInReady <= 1'b0;
          end
        end // StIdle

        StWait : begin
          if (csrFb.ready) begin
            csrReadOut <= 1'b0;
            csrWriteOut <= 1'b0;
            state <= StResp;
            wordOutValid <= 1'b1;
          end
        end // StWait

        StResp : begin
          if (wordOutValid && wordOutReady) begin
            wordOutValid <= 1'b0;
            state <= StIdle;
          end
        end // StResp

      endcase // case (state)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_words_to_csr
