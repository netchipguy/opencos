
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_chipmon #(
                    parameter integer ClockHz = 100_000_000,
                    parameter         type CsrType = oclib_pkg::csr_32_s,
                    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
                    parameter         type CsrProtocol = oclib_pkg::csr_32_s,
                    parameter bit     InternalReference = oclib_pkg::True,
                    parameter real    WarningTempHigh = 85.0, // when to assert warning condition (throttling)
                    parameter real    WarningTempLow = 83.0, // when to deassert warning condition
                    parameter real    ErrorTempHigh = 95.0, // when to assert error condition
                    parameter real    ErrorTempLow = 93.0, // when to deassert error condition
                    parameter real    WarningVccIntHigh = 0.880,
                    parameter real    WarningVccIntLow = 0.820,
                    parameter real    WarningVccAuxHigh = 1.850,
                    parameter real    WarningVccAuxLow = 1.750,
                    parameter real    WarningVccBramHigh = 0.880,
                    parameter real    WarningVccBramLow = 0.820,
                    parameter bit     CsrEnable = oclib_pkg::True,
                    parameter integer SyncCycles = 3,
                    parameter bit     ResetSync = oclib_pkg::False,
                    parameter integer ResetPipeline = 0
                 )
  (
   input        clock,
   input        reset,
   input        CsrType csr,
   output       CsrFbType csrFb,
   input        scl = 1'b1,
   output logic sclTristate,
   input        sda = 1'b1,
   output logic sdaTristate,
   output logic thermalWarning,
   output logic thermalError
   );

  logic                           resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

`ifdef OC_LIBRARY_ULTRASCALE_PLUS

  // See Xilinx UG580

  oclib_pkg::drp_s    drp;
  oclib_pkg::drp_fb_s drpFb;

  localparam integer NumCsr = 3;
  localparam integer CsrAddressControl = 1;
  localparam integer CsrAddressStatus = 2;
  localparam logic [31:0] CsrId = { oclib_pkg::CsrIdChipMon,
                                    15'd0, InternalReference };
  logic [0:NumCsr-1] [31:0] csrConfig;
  logic [0:NumCsr-1] [31:0] csrStatus;
  logic                     alertTristate;

  if (CsrEnable) begin : csr_en

    localparam Spaces = 2;
    localparam type CsrIntType = oclib_pkg::csr_32_s;
    localparam type CsrIntFbType = oclib_pkg::csr_32_fb_s;
    CsrIntType    [Spaces-1:0] csrInt;
    CsrIntFbType  [Spaces-1:0] csrIntFb;

    oclib_csr_adapter #(.CsrInType(CsrType), .CsrInFbType(CsrFbType), .CsrInProtocol(CsrProtocol),
                        .CsrOutType(CsrIntType), .CsrOutFbType(CsrIntFbType),
                        .UseClockOut(oclib_pkg::False),
                        .SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline),
                        .Spaces(Spaces))
    uCSR_ADAPTER (.clock(clock), .reset(resetSync),
                  .in(csr), .inFb(csrFb),
                  .out(csrInt), .outFb(csrIntFb) );

    // Implement address space 0
    oclib_csr_array #(.CsrType(CsrIntType), .CsrFbType(CsrIntFbType),
                      .NumCsr(NumCsr),
                      .CsrRwBits   ({ 32'h00000000, 32'h00000001, 32'h00000000 }),
                      .CsrRoBits   ({ 32'h00000000, 32'h70000000, 32'hffff0001 }),
                      .CsrFixedBits({ 32'hffffffff, 32'h00000000, 32'h00000000 }),
                      .CsrInitBits ({        CsrId, 32'h00000000, 32'h00000000 }))
    uCSR (.clock(clock), .reset(resetSync),
          .csr(csrInt[0]), .csrFb(csrIntFb[0]),
          .csrRead(), .csrWrite(),
          .csrConfig(csrConfig), .csrStatus(csrStatus));

    // Implement address space 1
    oclib_csr_to_drp #(.CsrType(CsrIntType), .CsrFbType(CsrIntFbType))
    uCSR_TO_DRP (.clock(clock), .reset(resetSync),
                 .csr(csrInt[1]), .csrFb(csrIntFb[1]),
                 .drp(drp), .drpFb(drpFb));

  end
  else begin // !if (CsrEnable)
    assign drp.enable = 1'b0;
    assign drp.address = '0;
    assign drp.write = 1'b0;
    assign drp.wdata = '0;
    assign csrConfig = '0;
  end // !if (CsrEnable)

  logic        softReset;
  logic [15:0] alarm;
  logic        jtagLocked;
  logic        jtagModified;
  logic        jtagBusy;

  // SYSMONE4 temp -> code
  function integer TempToCode (input real temp);
    if (InternalReference) return (((temp + 280.23087870) * 65536.0) / 507.5921310);
    else                   return (((temp + 279.42657680) * 65536.0) / 509.3140064);
  endfunction // TempToCode
  function integer VoltToCode (input real volt);
    return ((volt * 65536.0) / 3.0);
  endfunction // TempToCode

  localparam logic [15:0] AlarmTempHighCode = TempToCode(WarningTempHigh);
  localparam logic [15:0] AlarmTempLowCode = TempToCode(WarningTempLow) & 16'hfffe;
  localparam logic [15:0] OverTempHighCode = TempToCode(ErrorTempHigh);
  localparam logic [15:0] OverTempLowCode = TempToCode(ErrorTempLow) & 16'hfffe; // clear LSB to use hysteresis mode

  localparam logic [15:0] VccIntHighCode = VoltToCode(WarningVccIntHigh);
  localparam logic [15:0] VccIntLowCode = VoltToCode(WarningVccIntLow);
  localparam logic [15:0] VccAuxHighCode = VoltToCode(WarningVccAuxHigh);
  localparam logic [15:0] VccAuxLowCode = VoltToCode(WarningVccAuxLow);
  localparam logic [15:0] VccBramHighCode = VoltToCode(WarningVccBramHigh);
  localparam logic [15:0] VccBramLowCode = VoltToCode(WarningVccBramLow);

  localparam logic [7:0]  AdcClockDivider = (ClockHz / 4500000); // target 4.5MHz

  wire [4:0]              muxaddr;
  wire [5:0]              channel;
  wire                    eoc, eos, busy;
  wire [15:0]             adcdata;

  SYSMONE4 #(
             .INIT_40(16'h2000), // average over 64 samples
             .INIT_41(16'h2000), // Continuous Sequence
             .INIT_42({AdcClockDivider, 8'h00}),
             .INIT_43(16'h0000),
             .INIT_44(16'h0000),
             .INIT_48(16'h4701), // Temp, VCCint, VCCaux, VCCbram, calibration
             .INIT_4B(16'h4700), // Averaging Temp, VCCint, VCCaux, VCCbram
             .INIT_50(AlarmTempHighCode),
             .INIT_51(VccIntHighCode),
             .INIT_52(VccAuxHighCode),
             .INIT_53(OverTempHighCode),
             .INIT_54(AlarmTempLowCode),
             .INIT_55(VccIntLowCode),
             .INIT_56(VccAuxLowCode),
             .INIT_57(OverTempLowCode),
             .INIT_58(VccBramHighCode),
             .INIT_5C(VccBramLowCode),
             .SIM_MONITOR_FILE({`OC_ROOT, "/top/tests/oc_chipmon.sim.txt"}),
             .SIM_DEVICE(string'("ULTRASCALE_PLUS"))
             )
  uMONITOR (
            .DO(drpFb.rdata),
            .DI(drp.wdata),
            .DADDR(drp.address[7:0]),
            .DEN(drp.enable),
            .DWE(drp.write),
            .DCLK(clock),
            .DRDY(drpFb.ready),
            .RESET(reset || softReset),
            .CONVST(1'b0),
            .CONVSTCLK(1'b0),
            .VP(),
            .VN(),
            .VAUXP(),
            .VAUXN(),
            .I2C_SCLK(scl), // for connection to I2C/SMBus
            .I2C_SCLK_TS(sclTristate),
            .I2C_SDA(sda), // for connection to I2C/SMBus
            .I2C_SDA_TS(sdaTristate),
            .SMBALERT_TS(alertTristate), // when low, indicates ALERT, for connection to SMBus (generally on PCIe)
            .ADC_DATA(adcdata),
            .ALM(alarm),
            .OT(thermalError),
            .MUXADDR(muxaddr),
            .CHANNEL(channel),
            .EOC(eoc),
            .EOS(eos),
            .BUSY(busy),
            .JTAGLOCKED(jtagLocked),
            .JTAGMODIFIED(jtagModified),
            .JTAGBUSY(jtagBusy)
            );

  assign softReset = csrConfig[CsrAddressControl][0];
  // these are actually available via DRP, so maybe CsrAddressStatus should go away?
  assign csrStatus[CsrAddressStatus][0] = thermalError;
  assign csrStatus[CsrAddressStatus][31:16] = alarm;
  assign csrStatus[CsrAddressControl][28] = jtagLocked;
  assign csrStatus[CsrAddressControl][29] = jtagModified;
  assign csrStatus[CsrAddressControl][30] = jtagBusy;
  assign thermalWarning = alarm[0];

  `ifdef OC_CHIPMON_INCLUDE_ILA_DEBUG
  `OC_DEBUG_ILA(uILA, clock, 8192, 128, 32,
                { drp, drpFb,
                  reset, softReset,
                  scl, sclTristate, sda, sdaTristate,
                  jtagLocked, jtagModified, jtagBusy,
                  adcdata, muxaddr, channel,
                  eoc, eos, busy,
                  thermalError, thermalWarning,
                  alertTristate, alarm },
                { '0 });
  `endif // OC_CHIPMON_INCLUDE_ILA_DEBUG

`else // !`ifdef OC_LIBRARY_ULTRASCALE_PLUS

  // BEHAVIORAL IMPLEMENTATION

  // Note this implementation provides only the most basic functionality (i.e. legal behavior at outputs). It doesn't
  // implement any CSRs.  The indended use for this mode is bringing up a design in a vendor-neutral fashion, without
  // requiring any vendor libraries (i.e. just generic SystemVerilog simulation).

  assign csrFb = '0;
  assign sclTristate = 1'b1;
  assign sdaTristate = 1'b1;
  assign alertTristate = 1'b1;
  assign thermalWarning = 1'b0;
  assign thermalError = 1'b0;

`endif // !`ifdef OC_LIBRARY_ULTRASCALE_PLUS

endmodule // oc_chipmon
