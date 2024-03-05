
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

// TODO: this should probably be called bc_bidi_to_csr
// TODO: this will need to take a BcCsrProtocol or equiv, and convert to outbound CSR type.  Right now it's assumed equal.

module oclib_bc_to_csr
  #(
    parameter         type BcType = oclib_pkg::bc_8b_bidi_s,
//    parameter integer BcCsrOptions = oclib_pkg::DefaultBcCsrOptions,
//    parameter integer BcCsrBlock = oclib_pkg::BcBlockIdAny,
//    parameter integer CsrDatapathWidth = 32,
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter integer SyncCycles = 0,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input  clock,
   input  reset,
   input  BcType bcIn,
   output BcType bcOut,
   output CsrType csr,
   input  CsrFbType csrFb
   );

  // synchronize/pipeline reset as needed
  logic                            resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // convert BC to words

  localparam integer               WordRequestWidth = $bits(CsrType);
  localparam integer               WordResponseWidth = $bits(CsrFbType);

  logic [WordRequestWidth-1:0]     wordRequestData;
  logic                            wordRequestValid;
  logic                            wordRequestReady;
  logic [WordResponseWidth-1:0]    wordResponseData;
  logic                            wordResponseValid;
  logic                            wordResponseReady;

  oclib_bc_bidi_to_words #(.BcType(BcType),
                           .WordInWidth(WordResponseWidth), .WordOutWidth(WordRequestWidth))
  uBC_BIDI_TO_WORDS (.clock(clock), .reset(resetSync),
                     .bcIn(bcIn), .bcOut(bcOut),
                     .wordOutData(wordRequestData), .wordOutValid(wordRequestValid), .wordOutReady(wordRequestReady),
                     .wordInData(wordResponseData), .wordInValid(wordResponseValid), .wordInReady(wordResponseReady));

  // convert words to CSR

  oclib_words_to_csr #(.CsrType(CsrType), .CsrFbType(CsrFbType))
  uWORDS_TO_CSR (.clock(clock), .reset(resetSync),
                 .wordInData(wordRequestData), .wordInValid(wordRequestValid), .wordInReady(wordRequestReady),
                 .wordOutData(wordResponseData), .wordOutValid(wordResponseValid), .wordOutReady(wordResponseReady),
                 .csr(csr), .csrFb(csrFb));

endmodule // oclib_bc_to_csr
