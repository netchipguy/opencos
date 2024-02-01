
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_csr_to_axil
  #(
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter         type AxilType = oclib_pkg::axil_32_s,
    parameter         type AxilFbType = oclib_pkg::axil_32_fb_s,
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
   output AxilType axil,
   input  AxilFbType axilFb
   );

  localparam integer DataWidth = $bits(axil.wdata);
  localparam integer AddressWidth = $bits(axil.awaddr);

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
      axil <= '0;
      csrFb <= '0;
      state <= StIdle;
    end
    else begin
      case (state)

        StIdle : begin
          if (csr.write && actualCsrSelect) begin
            axil.awvalid <= 1'b1;
            axil.wvalid <= 1'b1;
            axil.awaddr <= csr.address[AddressWidth-1:0];
            axil.wdata <= csr.wdata[DataWidth-1:0];
            axil.wstrb <= {DataWidth/8{1'b1}};
            state <= StWrite1;
          end
          else if (csr.read && actualCsrSelect) begin
            axil.arvalid <= 1'b1;
            axil.araddr <= csr.address[AddressWidth-1:0];
            state <= StRead1;
          end
        end // StIdle

        StWrite1 : begin
          if (axilFb.awready) axil.awvalid <= 1'b0;
          if (axilFb.wready) axil.wvalid <= 1'b0;
          if ((!axil.awvalid) && (!axil.wvalid)) begin
            axil.bready <= 1'b1;
            state <= StWrite2;
          end
        end // StWrite1

        StWrite2 : begin
          if (axilFb.bvalid) begin
            axil.bready <= 1'b0;
            csrFb.ready <= 1'b1;
            csrFb.error <= (axilFb.bresp != 2'd0);
            state <= StDone;
          end
        end // StWrite2

        StRead1 : begin
          if (axilFb.arready) axil.arvalid <= 1'b0;
          if (!axil.arvalid) begin
            axil.rready <= 1'b1;
            state <= StRead2;
          end
        end // StRead1

        StRead2 : begin
          if (axilFb.rvalid) begin
            axil.rready <= 1'b0;
            csrFb.ready <= 1'b1;
            csrFb.rdata <= axilFb.rdata;
            csrFb.error <= (axilFb.rresp != 2'd0);
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

endmodule // oclib_csr_to_axil
