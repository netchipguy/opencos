
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_csr_to_apb
  #(
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter         type ApbType = oclib_pkg::apb_s,
    parameter         type ApbFbType = oclib_pkg::apb_fb_s,
    parameter bit     ApbSlaveError = oclib_pkg::True,
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
   output ApbType apb,
   input  ApbFbType apbFb
   );

  localparam integer DataWidth = $bits(csr.wdata);
  localparam integer AddressWidth = $bits(csr.address);

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // check that we are actually selected
  logic          actualCsrSelect;
  oclib_csr_check_selected #(.CsrType(CsrType), .AnswerToBlock(AnswerToBlock), .AnswerToSpace(AnswerToSpace))
  uCHECK_SELECTED (.csrSelect(csrSelect), .csr(csr), .match(actualCsrSelect));

  enum           logic [2:0] { StIdle, StWrite1, StWrite2, StRead1, StRead2, StDone } state;

  always_ff @(posedge clock) begin
    if (resetSync) begin
      apb <= '0;
      csrFb <= '0;
      state <= StIdle;
    end
    else begin
      case (state)

        StIdle : begin
          if (csr.write && actualCsrSelect) begin
            apb.select <= 1'b1;
            apb.write <= 1'b1;
            apb.address <= csr.address[AddressWidth-1:0];
            apb.wdata <= csr.wdata[DataWidth-1:0];
            state <= StWrite1;
          end
          else if (csr.read && actualCsrSelect) begin
            apb.select <= 1'b1;
            apb.write <= 1'b0;
            apb.address <= csr.address[AddressWidth-1:0];
            state <= StRead1;
          end // StIdle
        end

        StWrite1 : begin
          apb.enable <= 1'b1;
          state <= StWrite2;
        end // StWrite1

        StWrite2 : begin
          if (apbFb.ready) begin
            csrFb.ready <= 1'b1;
            csrFb.error <= apbFb.error;
            apb.select <= 1'b0;
            apb.enable <= 1'b0;
            apb.write <= 1'b0;
            state <= StDone;
          end
        end // StWrite2

        StRead1 : begin
          apb.enable <= 1'b1;
          state <= StRead2;
        end // StRead1

        StRead2 : begin
          if (apbFb.ready) begin
              csrFb.ready <= 1'b1;
            csrFb.error <= apbFb.error;
            csrFb.rdata <= apbFb.rdata;
            apb.select <= 1'b0;
            apb.enable <= 1'b0;
            state <= StDone;
          end
        end // StRead2

        StDone : begin
          csrFb.ready <= 1'b0;
          if ((!csr.read) && (!csr.write)) begin
            state <= StIdle;
          end
        end // StDone

      endcase // case (state)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_csr_to_apb
