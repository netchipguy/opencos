// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_csr_synchronizer
  #(
    parameter     type CsrType = oclib_pkg::csr_32_s,
    parameter     type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter int CsrSelectBits = 1,
    parameter int SyncCycles = 3,
    parameter int SkewCycles = 2,
    parameter bit UseResetIn = oclib_pkg::False,
    parameter bit UseResetOut = oclib_pkg::False,
    parameter bit ResetInSync = oclib_pkg::False,
    parameter bit ResetOutSync = oclib_pkg::False,
    parameter int ResetInPipeline = 0,
    parameter int ResetOutPipeline = 0
    )
  (
   input                            reset = 1'b0,
   input                            resetIn = 1'b0,
   input                            clockIn,
   input [CsrSelectBits-1:0]        csrSelectIn = { CsrSelectBits { 1'b1 }},
   input                            CsrType csrIn,
   output                           CsrFbType csrInFb,
   input                            resetOut = 1'b0,
   input                            clockOut,
   output logic [CsrSelectBits-1:0] csrSelectOut,
   output                           CsrType csrOut,
   input                            CsrFbType csrOutFb
   );

  localparam int                    DataWidth = $bits(csrIn.wdata);
  localparam int                    AddressWidth = $bits(csrIn.address);

  logic                             resetInSync;
  logic                             resetOutSync;

  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetInSync), .ResetPipeline(ResetInPipeline))
  uRESET_IN (.clock(clockIn), .in(UseResetIn ? resetIn : reset), .out(resetInSync));

  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetOutSync), .ResetPipeline(ResetOutPipeline))
  uRESET_OUT (.clock(clockOut), .in(UseResetOut ? resetOut : reset), .out(resetOutSync));

  // Synchronize the csr input bus.  This is easy because all the signals are level, not pulse.  We
  // will still have to take care to not assume all signals arrive at far side on the same clock (as
  // always one clock skew is tolerated on async crossing)

  logic [CsrSelectBits-1:0]         csrSelectInSync;
  CsrType                           csrInSync;

  oclib_synchronizer #(.Width(CsrSelectBits + $bits(csrIn)), .SyncCycles(SyncCycles))
  uREQ_SYNC (.clock(clockOut), .in({csrSelectIn, csrIn}), .out({csrSelectInSync, csrInSync}));

  // Look at synchronized version of csrIn and generate csrOut.  The csrOutFb has two pulsed signals
  // (ready, error) which we convert to toggle form for clock crossing.

  logic                       csrOutWrite;
  logic                       csrOutRead;
  enum                        logic [1:0] { StOutIdle, StOutStart, StOutWait, StOutFinish } csrOutState;
  logic                       csrToggleReady;
  logic                       csrToggleError;
  logic [DataWidth-1:0]       csrReadData;

  always_ff @(posedge clockOut) begin
    if (resetOutSync) begin
      csrOutWrite <= 1'b0;
      csrOutRead <= 1'b0;
      csrSelectOut <= '0;
      csrOutState <= StOutIdle;
      csrToggleReady <= 1'b0;
      csrToggleError <= 1'b0;
      csrReadData <= '0;
    end
    else begin
      case (csrOutState)

        StOutIdle : begin
          if (csrInSync.read || csrInSync.write) begin
            csrOutState <= StOutStart;
          end
        end // StOutIdle

        StOutStart : begin
          csrSelectOut <= csrSelectInSync;
          csrOutWrite <= csrInSync.write;
          csrOutRead <= csrInSync.read;
          csrOutState <= StOutWait;
        end // StOutStart

        StOutWait : begin
          if (csrOutFb.ready || csrOutFb.error) begin
            csrSelectOut <= '0;
            csrOutWrite <= 1'b0;
            csrOutRead <= 1'b0;
            csrToggleReady <= (csrToggleReady ^ csrOutFb.ready);
            csrToggleError <= (csrToggleError ^ csrOutFb.error);
            csrOutState <= StOutFinish;
            csrReadData <= csrOutFb.rdata;
         end
        end // StOutWait

        StOutFinish : begin
          if (!(csrInSync.read || csrInSync.write)) begin
            csrOutState <= StOutIdle;
          end
        end // StOutFinish

      endcase // case (csrOutState)
    end // else: !if(resetOutSync)
  end // always_ff @ (posedge clockOut)

  always_comb begin
    csrOut = csrInSync;
    csrOut.write = csrOutWrite;
    csrOut.read = csrOutRead;
  end

  // Monitor the ready/error toggle strobes, wait a cycle for all signals to come across, then
  // drive csrInFb

  logic csrToggleErrorSync;
  logic csrToggleReadySync;
  logic [DataWidth-1:0] csrReadDataSync;

  oclib_synchronizer #(.Width(2), .SyncCycles(SyncCycles+SkewCycles))
  uRESP_CONTROL_SYNC (.clock(clockOut), .in({csrToggleError, csrToggleReady}),
                      .out({csrToggleErrorSync, csrToggleReadySync}));

  oclib_synchronizer #(.Width(DataWidth), .SyncCycles(SyncCycles))
  uRESP_DATA_SYNC (.clock(clockOut), .in(csrReadData),
                   .out(csrReadDataSync));

  enum                        logic { StInIdle, StInGo } csrInState;
  logic csrToggleErrorIn;
  logic csrToggleReadyIn;

  always_ff @(posedge clockIn) begin
    if (resetInSync) begin
      csrInState <= StInIdle;
      csrInFb <= '0;
      csrToggleReadyIn <= csrToggleReadySync;
      csrToggleErrorIn <= csrToggleErrorSync;
    end
    else begin
      case (csrInState)

        StInIdle : begin
          csrInFb.ready <= 1'b0;
          csrInFb.error <= 1'b0;
          if ((csrToggleErrorIn ^ csrToggleErrorSync) || (csrToggleReadyIn ^ csrToggleReadySync)) begin
            csrInState <= StInGo;
          end
        end // StInIdle

        StInGo : begin
          csrInFb.ready <= (csrToggleReadyIn ^ csrToggleReadySync);
          csrInFb.error <= (csrToggleErrorIn ^ csrToggleErrorSync);
          csrInFb.rdata <= csrReadDataSync;
          csrToggleReadyIn <= csrToggleReadySync;
          csrToggleErrorIn <= csrToggleErrorSync;
          csrInState <= StInIdle;
        end // StInGo

      endcase // case (csrInState)
    end // else: !if(resetInSync)
  end // always_ff @ (posedge clockIn)

endmodule // oclib_csr_synchronizer
