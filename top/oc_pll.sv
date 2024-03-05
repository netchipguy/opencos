
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_pll
  #(
    // Use these parameters for vendor-independent, automatic PLL setup
    parameter longint RefClockHz = 100000000,
    parameter int     OutClockCount = 1,
    parameter longint Out0Hz = 225000000, // code will attempt to hit this freq exactly
    parameter longint Out1Hz = 450000000, // this block supports multiple outputs per PLL, though above we aren't yet using that
    parameter longint Out2Hz = 250000000, // these additional clocks will be hit "as close as possible" once Out0 has been used
    parameter longint Out3Hz = 200000000, // to configure VCO etc
    parameter longint Out4Hz = 100000000,
    parameter longint Out5Hz = 50000000,
    parameter longint Out6Hz = 50000000,
    parameter bit     CsrEnable = oclib_pkg::False,
    parameter bit     MeasureEnable = oclib_pkg::False,
    parameter bit     ThrottleMap = oclib_pkg::True,
    parameter bit     AutoThrottle = oclib_pkg::True,
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter         type CsrProtocol = oclib_pkg::csr_32_s,
    parameter int     SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter int     ResetPipeline = 0
    )
  (
   input                            clock = 1'b0, // used if CsrEnable, as the clock for support logic
   input                            reset = 1'b0, // optional, the MMCM doesn't need it, just AbbcEnable
   input                            thermalWarning = 1'b0,
   input                            thermalError = 1'b0,
   input                            clockRef,
   output logic [OutClockCount-1:0] clockOut,
   output logic [OutClockCount-1:0] resetOut,
   input                            CsrType csr,
   output                           CsrFbType csrFb
   );

  localparam real RefPeriodNS  = (1000000000.0/real'(RefClockHz));

  logic                             resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

`ifdef OC_LIBRARY_ULTRASCALE_PLUS

  // We are expecting to use:  MMCME4_ADV, see Xilinx UG572 for details

  // We add more parameters here, these should typically configure themselves from the ones above
  // to remain library independent.  They aren't localparams though, they can be changed if one
  // wants to get really hands-on

  function longint AbsDiff (input longint a, input longint b);
    if (a > b) return (a-b);
    else       return (b-a);
  endfunction

  function longint ComputeVcoFrequency (input longint vcoMinHz, input longint vcoMaxHz,
                                        input longint  refClockHz, input longint outClockHz,
                                        input real refMultMin, input real refMultMax, input real refMultStep,
                                        input real outDivMin, input real outDivMax, input real outDivStep);
    longint vcoHz, outHz, resultHz, errorHz;
    `OC_IFDEF_INCLUDE(OC_PLL_DEBUG_VCO_FREQUENCY,
                      $display("%t %m: Attmping to hit outClockHz:%d with refClockHz:%d", $realtime, outClockHz, refClockHz); )
    resultHz = vcoMaxHz;  // by default, we run VCO at max speed and then calculate dividers to hit output (or close)
    errorHz = vcoMaxHz * 1000; // large error by default, we want to replace this with something better
    // we start with high mult, preferring high VCO freq...
    for (real refMult = refMultMax; refMult >= refMultMin; refMult -= refMultStep) begin
      vcoHz = longint'(real'(refClockHz) * refMult);
      `OC_IFDEF_INCLUDE(OC_PLL_DEBUG_VCO_FREQUENCY,
                        $display("%t %m: debug: refMult=%.3f, vcoHz=%d", $realtime, refMult, vcoHz); )
      if ((vcoHz >= vcoMinHz) && (vcoHz <= vcoMaxHz)) begin // this is a legal VCO frequency
        for (real outDiv = outDivMin; outDiv <= outDivMax; outDiv += outDivStep) begin
          outHz = longint'(real'(vcoHz) / outDiv);
          `OC_IFDEF_INCLUDE(OC_PLL_DEBUG_VCO_FREQUENCY,
                            $display("%t %m: debug: outDiv=%.3f, outHz=%d", $realtime, outDiv, outHz); )
          if (AbsDiff(outHz, outClockHz) < errorHz) begin // we have a better result
            resultHz = vcoHz;
            errorHz = AbsDiff(outHz, outClockHz);
            `OC_IFDEF_INCLUDE(OC_PLL_DEBUG_VCO_FREQUENCY,
                              $display("%t %m: Chose new vcoHz=%d (outDiv=%.3f, outHz=%d, outClockHz=%d, error=%d)", $realtime,
                                       vcoHz, outDiv, outHz, outClockHz, errorHz); )
          end
        end
      end
    end
    return resultHz;
  endfunction

  // Compute MMCME4_ADV dividers and multipliers.  First look at desired output #0, find a valid VCO freq
  // that hits that target with minimal error.  Then compute optimal D and M to get there.  Then compute
  // the other outputs to hit their targets given the VCO freq already locked down.

  parameter longint     MinVcoHz = 1200000000;
  parameter longint     MaxVcoHz = 1600000000;
  parameter longint     TargetVcoHz = ComputeVcoFrequency(.vcoMinHz(MinVcoHz), .vcoMaxHz(MaxVcoHz),
                                                          .refClockHz(RefClockHz), .outClockHz(Out0Hz),
                                                          .refMultMin(0.125), .refMultMax(100.000), .refMultStep(0.125),
                                                          .outDivMin(0.125), .outDivMax(100.000), .outDivStep(0.125));

  `ifdef SIMULATION
    `ifdef OC_PLL_DEBUG_VCO_FREQUENCY
  initial begin : uCOMP_VCO
    longint t;
    t = ComputeVcoFrequency(.vcoMinHz(MinVcoHz), .vcoMaxHz(MaxVcoHz),
                            .refClockHz(RefClockHz), .outClockHz(Out0Hz),
                            .refMultMin(0.125), .refMultMax(100.000), .refMultStep(0.125),
                            .outDivMin(0.125), .outDivMax(100.000), .outDivStep(0.125));
  end
    `endif
  `endif

  // example math: ClockRefHz = 156_250_000, Out0Hz = 400_000_000

  parameter int     DivD = 'd1; // fixed for now, don't need precision of both D and M
  parameter int     DivMx8 = $floor((8.0*real'(TargetVcoHz)) / real'(DivD*RefClockHz)); // 81
  parameter real    RealDivM = (real'(DivMx8) / 8.0); // 10.125
  parameter real    RealVcoHz = (real'(RefClockHz)*RealDivM / real'(DivD)); // 1582MHz
  parameter int     Div0x8 = $ceil(8.0*RealVcoHz / real'(Out0Hz)); // 51
  parameter real    RealDiv0 = (real'(Div0x8) / 8.0); // 6.75
  // for clocks that don't exist, we provide safe default dividers since incoming param is probably 0
  parameter int     Div1 = (OutClockCount>1) ? $ceil(RealVcoHz / real'(Out1Hz)) : 32; // 4
  parameter int     Div2 = (OutClockCount>2) ? $ceil(RealVcoHz / real'(Out2Hz)) : 32; // 7
  parameter int     Div3 = (OutClockCount>3) ? $ceil(RealVcoHz / real'(Out3Hz)) : 32; // 8
  parameter int     Div4 = (OutClockCount>4) ? $ceil(RealVcoHz / real'(Out4Hz)) : 32; // 16
  parameter int     Div5 = (OutClockCount>5) ? $ceil(RealVcoHz / real'(Out5Hz)) : 32; // 32
  parameter int     Div6 = (OutClockCount>6) ? $ceil(RealVcoHz / real'(Out6Hz)) : 32;  // 32

  localparam        ThrottleMapW = 8;

  // We don't necessarily need CSRs to have ChipMon.  It can be statically programmed to generate
  // thermalWarning/thermalError.

  localparam int    NumCsr = 3;
  logic [0:NumCsr-1] [31:0]   csrOut;
  logic [0:NumCsr-1] [31:0]   csrIn;
  localparam int    CsrAddressControl = 1;
  localparam int    CsrAddressStatus = 2;

  oclib_pkg::drp_s    drp;
  oclib_pkg::drp_fb_s drpFb;

  if (CsrEnable) begin : csr_en

    // *** Convert incoming CSR type into two spaces: local csr and a DRP for the PLL IP

    localparam int Spaces = 2;
    localparam type CsrIntType = oclib_pkg::csr_32_s;
    localparam type CsrIntFbType = oclib_pkg::csr_32_fb_s;
    CsrIntType    [Spaces-1:0] csrInt;
    CsrIntFbType  [Spaces-1:0] csrIntFb;

    oclib_csr_adapter #(.EnableILA(`OC_VAL_IFDEF(OC_PLL_INCLUDE_ILA_DEBUG)),
                        .CsrInType(CsrType), .CsrInFbType(CsrFbType), .CsrInProtocol(CsrProtocol),
                        .CsrOutType(CsrIntType), .CsrOutFbType(CsrIntFbType),
                        .UseClockOut(oclib_pkg::False),
                        .SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline),
                        .Spaces(Spaces))
    uCSR_ADAPTER (.clock(clock), .reset(resetSync),
                  .in(csr), .inFb(csrFb),
                  .out(csrInt), .outFb(csrIntFb) );

    // *** Implement address space 0

    // 0 : CSR ID
    //   [    0] MeasureEnable
    //   [    1] ThrottleMap
    //   [    2] AutoThrottle
    //   [ 7: 4] OutClockCount
    //   [15: 8] PllType
    //   [31:16] csrId
    // 1 : Control
    //   [    0] softReset
    //   [    1] powerDown
    //   [    4] cddcReq
    //   [    5] cddcDone
    //   [   16] clkInStopped
    //   [   17] clkFbStopped
    //   [   20] thermalWarning
    //   [   21] thermalError
    //   [   31] pllLocked
    // 2..N : Clock0Control .. Clock1Control ..
    //   [    0] forcedThermalWarning
    //   [    1] enableThermalWarning
    //   [15: 8] throttleMap
    //   [31:16] count

    localparam logic [7:0]  PllType = 8'd1; // MMCME4_ADV
    localparam logic [31:0] CsrId = { oclib_pkg::CsrIdPll, PllType, 4'(OutClockCount),
                                      1'b0, AutoThrottle, ThrottleMap, MeasureEnable };

    oclib_csr_array #(.CsrType(CsrIntType), .CsrFbType(CsrIntFbType),
                      .NumCsr(NumCsr), .InputAsync(oclib_pkg::True),
                      .CsrRwBits   ({ 32'h00000000, 32'h00000013, {OutClockCount{32'h0000ff03}} }),
                      .CsrRoBits   ({ 32'h00000000, 32'h80330020, {OutClockCount{32'hffff0000}} }),
                      .CsrFixedBits({ 32'hffffffff, 32'h00000000, {OutClockCount{32'h00000000}} }),
                      .CsrInitBits ({        CsrId, 32'h00000000, {OutClockCount{32'h00000000}} }))
    uCSR (.clock(clock), .reset(resetSync),
          .csr(csrInt[0]), .csrFb(csrIntFb[0]),
          .csrRead(), .csrWrite(),
          .csrOut(csrOut), .csrIn(csrIn));

    // *** Implement address space 1

    oclib_csr_to_drp #(.CsrType(CsrIntType), .CsrFbType(CsrIntFbType))
    uCSR_TO_DRP (.clock(clock), .reset(resetSync),
                 .csr(csrInt[1]), .csrFb(csrIntFb[1]),
                 .drp(drp), .drpFb(drpFb));

  `ifdef OC_PLL_INCLUDE_ILA_DEBUG
    `OC_DEBUG_ILA(uILA, clock, 8192, 128, 32,
                  { csr, csrFb,
                    csrInt[0].write, csrInt[0].read, csrIntFb[0].ready, csrIntFb[0].error,
                    csrInt[1].write, csrInt[1].read, csrIntFb[1].ready, csrIntFb[1].error
                    },
                  { resetSync, pllLocked, softReset, powerDown,
                    thermalWarning, thermalError,
                    csr.valid, csr.ready, csrFb.valid, csrFb.ready
                    });
  `endif

  end
  else begin // !if (CsrEnable)
    assign drp = '0;
    assign csrOut = '0;
    // we should not be accessing this, i.e. it shouldn't be connected at all, but we could
    // add oclib_csr_null, which then itself should compile away to nothing if unconnected
    assign csrFb = '0;
  end // !if (CsrEnable)

  logic        softReset;
  logic        powerDown;
  logic        cddcReq;
  logic        cddcDone;
  logic        clkInStopped;
  logic        clkFbStopped;
  logic        pllLocked;

  logic        fbClock;
  logic        clockOutPll [6:0]; // this is fixed based on the ports on the physical PLL

  MMCME4_ADV #(
               .CLKOUT0_DIVIDE_F(RealDiv0),
               .CLKOUT1_DIVIDE(Div1),
               .CLKOUT2_DIVIDE(Div2),
               .CLKOUT3_DIVIDE(Div3),
               .CLKOUT4_DIVIDE(Div4),
               .CLKOUT5_DIVIDE(Div5),
               .CLKOUT6_DIVIDE(Div6),
               .CLKFBOUT_MULT_F(RealDivM),
               .DIVCLK_DIVIDE(DivD),
               .CLKIN1_PERIOD(RefPeriodNS),
               .CLKIN2_PERIOD(RefPeriodNS)
               )
  uPLL (
        .CLKIN1(clockRef),
        .CLKIN2(1'b0),
        .CLKFBIN(fbClock),
        .DCLK(clock),
        .PSCLK(),
        .RST(reset || softReset),
        .CLKINSEL(1'b1),
        .DWE(drp.write),
        .DEN(drp.enable),
        .DADDR(drp.address[6:0]),
        .DI(drp.wdata),
        .PSINCDEC(),
        .PSEN(),
        .CDDCREQ(cddcReq),
        .CLKOUT0(clockOutPll[0]),
        .CLKOUT1(clockOutPll[1]),
        .CLKOUT2(clockOutPll[2]),
        .CLKOUT3(clockOutPll[3]),
        .CLKOUT4(clockOutPll[4]),
        .CLKOUT5(clockOutPll[5]),
        .CLKOUT6(clockOutPll[6]),
        .CLKOUT0B(),
        .CLKOUT1B(),
        .CLKOUT2B(),
        .CLKOUT3B(),
        .CLKFBOUT(fbClock),
        .CLKFBOUTB(),
        .LOCKED(pllLocked),
        .DO(drpFb.rdata),
        .DRDY(drpFb.ready),
        .PSDONE(),
        .CLKINSTOPPED(clkInStopped),
        .CLKFBSTOPPED(clkFbStopped),
        .CDDCDONE(cddcDone),
        .PWRDWN(powerDown)
        );

  assign softReset = csrOut[1][0];
  assign powerDown = csrOut[1][1];
  assign cddcReq = csrOut[1][4];
  assign csrIn[1][5] = cddcDone;
  assign csrIn[1][16] = clkInStopped;
  assign csrIn[1][17] = clkFbStopped;
  assign csrIn[1][20] = thermalWarning;
  assign csrIn[1][21] = thermalError;
  assign csrIn[1][31] = pllLocked;

  for (genvar c=0; c<OutClockCount; c++) begin : clk

    logic                    forcedThermalWarning;
    logic                    enableThermalWarning;
    logic [ThrottleMapW-1:0] throttleMap;
    logic [15:0]             count;

    assign forcedThermalWarning = csrOut[c+2][0];
    assign enableThermalWarning = csrOut[c+2][1];
    assign throttleMap = csrOut[c+2][15:8];
    assign csrIn[c+2][31:16] = count;

    oclib_clock_control #(.ThrottleMapW(ThrottleMapW),
                          .ThrottleMap(ThrottleMap),
                          .AutoThrottle(AutoThrottle))
    uCLOCK_CONTROL (.clockIn(clockOutPll[c]),
                    .reset(reset),
                    .clockOut(clockOut[c]),
                    .throttleMap(throttleMap),
                    .thermalWarning((thermalWarning && enableThermalWarning) || forcedThermalWarning));

    oclib_reset #(.StartPipeCycles(3), .ResetCycles(128))
    uRESET (.clock(clockOut[c]), .in(reset || !pllLocked), .out(resetOut[c]));

    if (MeasureEnable) begin : meas

      // this block is coded to close timing at very high speed, so we don't do any more than 16-bit
      logic [15:0] prescale;
      logic        prescaleTC;

      always_ff @(posedge clockOut[c]) begin
        if (resetOut[c]) begin
          prescale <= '0;
          prescaleTC <= 1'b0;
          count <= '0;
        end
        else begin
          prescale <= (prescale + 'd1);
          prescaleTC <= (&prescale);
          count <= (prescaleTC ? (count + 'd1) : count);
        end
      end

    end // if (MeasureEnable)
    else begin
      assign count = '0;
    end

  end // block: clk

  // `ifdef OC_LIBRARY_ULTRASCALE_PLUS
`else
  // OC_LIBRARY_BEHAVIORAL

  // BEHAVIORAL IMPLEMENTATION

  // Note this implementation provides only the most basic functionality (i.e. legal behavior at outputs). It doesn't
  // implement any CSRs.  The indended use for this mode is bringing up a design in a vendor-neutral fashion, without
  // requiring any vendor libraries (i.e. just generic SystemVerilog simulation).

  localparam real Out0PeriodNS = (1000000000.0/real'(Out0Hz));
  localparam real Out1PeriodNS = (1000000000.0/real'(Out1Hz));
  localparam real Out2PeriodNS = (1000000000.0/real'(Out2Hz));
  localparam real Out3PeriodNS = (1000000000.0/real'(Out3Hz));
  localparam real Out4PeriodNS = (1000000000.0/real'(Out4Hz));
  localparam real Out5PeriodNS = (1000000000.0/real'(Out5Hz));
  localparam real Out6PeriodNS = (1000000000.0/real'(Out6Hz));

  initial begin
    for (int c=0; c<OutClockCount; c++) clockOut[c] = 1'b1;
  end

  for (genvar c=0; c<OutClockCount; c++) begin
    always_ff @(posedge clockOut[c]) resetOut[c] <= reset;
  end

  if (OutClockCount>0) always #((Out0PeriodNS/2) * 1ns) clockOut[0] = ~clockOut[0];
  if (OutClockCount>1) always #((Out1PeriodNS/2) * 1ns) clockOut[1] = ~clockOut[1];
  if (OutClockCount>2) always #((Out2PeriodNS/2) * 1ns) clockOut[2] = ~clockOut[2];
  if (OutClockCount>3) always #((Out3PeriodNS/2) * 1ns) clockOut[3] = ~clockOut[3];
  if (OutClockCount>4) always #((Out4PeriodNS/2) * 1ns) clockOut[4] = ~clockOut[4];
  if (OutClockCount>5) always #((Out5PeriodNS/2) * 1ns) clockOut[5] = ~clockOut[5];
  if (OutClockCount>6) always #((Out6PeriodNS/2) * 1ns) clockOut[6] = ~clockOut[6];

  // *** Implement address space 0

  if (CsrEnable) begin : csr_en

    localparam int NumCsr = 1;

    localparam logic [7:0] ChipMonType = 8'd0; // "NONE" IMPLEMENTATION
    localparam logic [31:0] CsrId = { oclib_pkg::CsrIdPll, ChipMonType, 8'd0 };

    logic [0:NumCsr-1] [31:0] csrOut;
    logic [0:NumCsr-1] [31:0] csrIn;

    oclib_csr_array #(.CsrType(CsrType), .CsrFbType(CsrFbType), .CsrProtocol(CsrProtocol),
                      .NumCsr(NumCsr),
                      .CsrRwBits   ({ 32'h00000000 }), .CsrRoBits   ({ 32'h00000000 }),
                      .CsrFixedBits({ 32'hffffffff }), .CsrInitBits ({        CsrId }))
    uCSR (.clock(clock), .reset(resetSync),
          .csr(csr), .csrFb(csrFb),
          .csrRead(), .csrWrite(),
          .csrOut(csrOut), .csrIn(csrIn));

    assign csrIn[0] = '0;

  end
  else begin // !if (CsrEnable)
    // we should not be accessing this, i.e. it shouldn't be connected at all, but we could
    // add oclib_csr_null, which then itself should compile away to nothing if unconnected
    assign csrFb = '0;
  end // !if (CsrEnable)

  // OC_LIBRARY_BEHAVIORAL
`endif


endmodule // oc_pll
