
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_protect
  #(
    parameter integer       ClockHz = 100_000_000,
    parameter logic [31:0]  BitstreamID = `OC_VAL_ASDEFINED_ELSE(TARGET_BITSTREAM_ID, 32'h89abcdef),
    parameter logic [127:0] BitstreamKey = `OC_VAL_ASDEFINED_ELSE(TARGET_BITSTREAM_KEY,
                            128'h44444444_33333333_22222222_11111111),
    parameter bit           EnableSkeletonKey = `OC_VAL_ASDEFINED_ELSE(TARGET_PROTECT_SKELETON_KEY, oclib_pkg::False),
    parameter bit           EnableTimedLicense = `OC_VAL_ASDEFINED_ELSE(TARGET_PROTECT_TIMED_LICENSE, oclib_pkg::False),
    parameter bit           EnableParanoia = `OC_VAL_ASDEFINED_ELSE(TARGET_PROTECT_PARANOIA, oclib_pkg::False),
    parameter integer       TimedSeconds = `OC_VAL_ASDEFINED_ELSE(TARGET_PROTECT_TIMED_SECONDS, 3600),
    parameter               type CsrType = oclib_pkg::csr_32_s,
    parameter               type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter               type CsrProtocol = oclib_pkg::csr_32_s,
    parameter integer       SyncCycles = 3,
    parameter bit           ResetSync = oclib_pkg::False,
    parameter integer       ResetPipeline = 0
                    )
 (
  input        clock,
  input        reset,
  input        CsrType csr,
  output       CsrFbType csrFb,
  output logic unlocked
  );

  logic                           resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // Get FPGA serial number
  localparam SerialBits = 32;
  logic [SerialBits-1:0] serial;
  oclib_fpga_serial #(.SerialBits(SerialBits)) uSERIAL (.clock(clock), .reset(resetSync), .serial(serial));

  // decryption block
  localparam integer Words = 2; // we always decrypt a 2-word chunk

  logic                    decryptGo;
  logic [Words-1:0] [31:0] ciphertext;
  logic                    decryptDone;
  logic [Words-1:0] [31:0] plaintext;

  oclib_xxtea uDEC (.clock(clock), .go(decryptGo), .in(ciphertext), .key(BitstreamKey),
                    .done(decryptDone), .out(plaintext));

  // timer block
  logic                    timerUnlock;
  if (EnableTimedLicense) begin
    localparam integer       TimerLength = (TimedSeconds * ClockHz);
    localparam               TimerWidth = $clog2(TimerLength);
    logic [TimerWidth-1:0]   timerCounter;
    always_ff @(posedge clock) begin
      if (resetSync) begin
        timerCounter <= '0;
        timerUnlock <= 1'b0;
      end
      else begin
        timerCounter <= (timerUnlock ? (timerCounter + 'd1) : '0);
        timerUnlock <= (timerUnlock ? !(timerCounter == (TimerLength-1)) :
                        // Timed License is triggered by making out a license to the inverse of Bitstream ID
                        ((decryptDone && (plaintext == { ~BitstreamID, serial })) ||
                         // Features stack, you can make a skeleton timed license, for universal demo key
                         ( EnableSkeletonKey && (plaintext == { BitstreamID, 32'h12345678 }))));
      end
    end // always_ff
  end // if (EnableTimedLicense)
  else begin
    assign timerUnlock = 1'b0;
  end

  // check plaintext
  logic permanentUnlock;
  always_ff @(posedge clock) begin
    unlocked <= (permanentUnlock || timerUnlock);
    permanentUnlock <= (resetSync ? 1'b0 :
                        decryptDone ? ((plaintext == { BitstreamID, serial }) ||
                                       // Skeleton key feature will unlock any FPGA with a license made out to magic serial,
                                       // for escrow, development phase work, etc.
                                       ( EnableSkeletonKey && (plaintext == { BitstreamID, 32'h12345678 }))) :
                        permanentUnlock);
  end

  // Implement address space 0
  localparam integer NumCsr = 8; // 0 id, 1 control, 2-3 ciphertext, 4 fpga_serial, 5 bitstream_id, 6,7 plaintext (if !paranoid)
  localparam logic [31:0] CsrId = { oclib_pkg::CsrIdProtect,
                                    13'd0, EnableParanoia, EnableTimedLicense, EnableSkeletonKey };
  logic [0:NumCsr-1] [31:0] csrOut;
  logic [0:NumCsr-1] [31:0] csrIn;

  oclib_csr_array #(.CsrType(CsrType), .CsrFbType(CsrFbType), .CsrProtocol(CsrProtocol),
                    .NumCsr(NumCsr),
                    .CsrRwBits   ({ 32'h00000000, 32'h00000001, {2{32'hffffffff}}, {4{32'h00000000}}  }),
                    .CsrRoBits   ({ 32'h00000000, 32'he0000000, {2{32'h00000000}}, {4{32'hffffffff}}  }),
                    .CsrFixedBits({ 32'hffffffff, 32'h00000000, {2{32'h00000000}}, {4{32'h00000000}}  }),
                    .CsrInitBits ({        CsrId, 32'h00000000, {2{32'h00000000}}, {4{32'h00000000}}   }))
  uCSR (.clock(clock), .reset(resetSync),
        .csr(csr), .csrFb(csrFb),
        .csrRead(), .csrWrite(),
        .csrOut(csrOut), .csrIn(csrIn));

  assign decryptGo = csrOut[1][0];
  assign ciphertext = {csrOut[3], csrOut[2]};
  assign csrIn[1][31] = permanentUnlock;
  assign csrIn[1][30] = timerUnlock;
  assign csrIn[1][29] = decryptDone;
  assign csrIn[4] = serial;
  assign csrIn[5] = BitstreamID;
  assign csrIn[6] = (EnableParanoia ? '0 : plaintext[0]);
  assign csrIn[7] = (EnableParanoia ? '0 : plaintext[1]);

  `ifdef OC_PROTECT_INCLUDE_ILA_DEBUG
  `OC_DEBUG_ILA(uILA, clock, 1024, 512, 32,
                { ciphertext, plaintext, serial, BitstreamID, BitstreamKey
                  },
                { resetSync, permanentUnlock, timerUnlock, decryptGo, decryptDone});
  `endif // OC_CHIPMON_INCLUDE_ILA_DEBUG

endmodule // oc_protect
