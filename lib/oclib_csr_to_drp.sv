
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_csr_to_drp
  #(
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter         type DrpType = oclib_pkg::drp_s,
    parameter         type DrpFbType = oclib_pkg::drp_fb_s,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0,
    parameter [31:0]  AnswerToBlock = oclib_pkg::BcBlockIdAny,
    parameter [3:0]   AnswerToSpace = oclib_pkg::BcSpaceIdAny
    )
  (
   input  clock,
   input  reset,
   input  csrSelect = 1'b1,
   input  CsrType csr,
   output CsrFbType csrFb,
   output DrpType drp,
   input  DrpFbType drpFb
   );

  localparam integer DataW = $bits(drp.wdata);
  localparam integer AddressW = $bits(drp.address);

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // check that we are actually selected
  logic          actualCsrSelect;
  oclib_csr_check_selected #(.CsrType(CsrType), .AnswerToBlock(AnswerToBlock), .AnswerToSpace(AnswerToSpace))
  uCHECK_SELECTED (.csrSelect(csrSelect), .csr(csr), .match(actualCsrSelect));

  enum           logic [1:0] { StIdle, StWrite, StRead, StDone } state;

  always_ff @(posedge clock) begin
    if (resetSync) begin
      drp <= '0;
      csrFb <= '0;
      state <= StIdle;
    end
    else begin
      case (state)

        StIdle : begin
          if (csr.write && actualCsrSelect) begin
            drp.enable <= 1'b1;
            drp.write <= 1'b1;
            drp.address <= csr.address[AddressW-1:0];
            drp.wdata <= csr.wdata[DataW-1:0];
            state <= StWrite;
          end
          else if (csr.read && actualCsrSelect) begin
            drp.enable <= 1'b1;
            drp.address <= csr.address[AddressW-1:0];
            state <= StRead;
          end
        end // StIdle

        StWrite : begin
          drp <= '0;
          if (drpFb.ready) begin
            csrFb.ready <= 1'b1;
            state <= StDone;
          end
        end // StWrite

        StRead : begin
          drp <= '0;
          if (drpFb.ready) begin
            csrFb.rdata <= drpFb.rdata;
            csrFb.ready <= 1'b1;
            state <= StDone;
          end
        end // StRead

        StDone : begin
          csrFb.ready <= 1'b0;
          if ((!csr.read) && (!csr.write)) begin
            state <= StIdle;
          end
        end // StDone

      endcase // case (state)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_csr_to_drp
