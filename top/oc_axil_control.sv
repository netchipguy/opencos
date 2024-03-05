
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_axil_control
  #(
    parameter int                     ClockHz = 100_000_000,
    parameter                         type AxilType = oclib_pkg::axil_32_s,
    parameter                         type AxilFbType = oclib_pkg::axil_32_fb_s,
    parameter                         type BcType = oclib_pkg::bc_8b_bidi_s,
    parameter                         type BcProtocol = oclib_pkg::csr_32_s,
    parameter int                     AddressBits = 32,
    parameter logic [AddressBits-1:0] ControlAddress = { { (AddressBits-8) {1'b1} }, 8'h00 }, // top of space
    parameter logic [0:1] [7:0]       BlockTopCount = '0,
    parameter logic [0:1] [7:0]       BlockUserCount = '0,
    parameter logic [7:0]             UserCsrCount = '0,
    parameter logic [7:0]             UserAximSourceCount = '0,
    parameter logic [7:0]             UserAximSinkCount = '0,
    parameter logic [7:0]             UserAxisSourceCount = '0,
    parameter logic [7:0]             UserAxisSinkCount = '0,
    parameter bit                     UseClockAxil = oclib_pkg::False,
    parameter bit                     PassThrough = oclib_pkg::False,
    parameter bit                     ResetSync = oclib_pkg::False,
    parameter logic [0:15] [7:0]      UserSpace = `OC_VAL_ASDEFINED_ELSE(USER_APP_STRING, "none            ")
    )
  (
   input        clock,
   input        reset,
   input        clockAxil,
   input        resetAxil,
   output logic resetOut,
   input        AxilType axil,
   output       AxilFbType axilFb,
   output       AxilType axilOut,
   input        AxilFbType axilOutFb = '0, // only used if PassThrough is set
   input        BcType bcIn,
   output       BcType bcOut
   );

  logic                         vioReset;
  logic                         resetSync;
  logic                         resetAxilSync;

  assign vioReset = 1'b0; // we don't have a VIO in AXIL control (yet?) just a reminder...

  oclib_synchronizer #(.Enable(ResetSync))
  uRESET_SYNC (.clock(clock), .in(reset || vioReset), .out(resetSync));

  oclib_synchronizer #(.Enable(ResetSync))
  uRESETAXIL_SYNC (.clock(clock), .in(reset || vioReset), .out(resetAxilSync));

  // Philosophy here is to not backpressure the RX channel.  We dont want to block attempts to
  // reset or resync, and you cannot overrun the RX state machine when following the protocol.

  // If we are passing through the AXIL bus, demux it via peeling off a 256-byte window

  AxilType axilControl;
  AxilFbType axilControlFb;

  if (PassThrough) begin

    oclib_axil_demux #(.AxilType(AxilType),
                       .AxilFbType(AxilFbType),
                       .SelectBAddress(ControlAddress),
                       .SelectBMask(32'hffffff00)) // steal 256B from the AXIL space for control
    uAXIL_DEMUX (.clock(clockAxil), .reset(resetAxilSync),
                 .axilIn(axil), .axilInFb(axilFb),
                 .axilA(axilOut), .axilAFb(axilOutFb),
                 .axilB(axilControl), .axilBFb(axilControlFb));

  end
  else begin
    // we aren't passing through, just pass the whole space to the state machine below
    assign axilControl = axil;
    assign axilFb = axilControlFb;
    assign axilOut = '0;
  end

  /*
     |- axil_demux -|         |- axil_to_bc -|  |-    out_fifo    -|    |-  control  -| |- top csr split ...
   axil    -> .axilB(axilControl)     ->  axilBcOut   ->   .extBcIn(fifoBcOut)  ->   bcOut  -> ...
   axilFb  -> .axilBFb(axilControlFb) <-  axilBcIn    <-   .extBcOut(fifoBcIn)  <-   bcIn   <- ...
     |- axil_demux -|         |- axil_to_bc -|  |-     in_fifo    -|    |-  control  -| |- top csr split ...

   */

  // Instantiate generic AXIL-to-BC unit

  BcType axilBcOut, axilBcIn;

  oclib_axil_to_bc #(.AxilType(AxilType),
                     .AxilFbType(AxilFbType),
                     .BcType(BcType))
  uAXIL_TO_BC (.clock(clockAxil), .reset(resetAxilSync),
               .axil(axilControl), .axilFb(axilControlFb),
               .bcOut(axilBcOut), .bcIn(axilBcIn));

  // Cross clocks from AXIL to top, if needed

  BcType fifoBcOut, fifoBcIn;
  if (UseClockAxil) begin

    oclib_async_fifo #(.Width(8), .Depth(32))
    uBC_OUT_FIFO (.clockIn(clockAxil), .clockOut(clock), .reset(reset),
                  .inData(axilBcOut.data), .inValid(axilBcOut.valid), .inReady(axilBcIn.ready),
                  .outData(fifoBcOut.data), .outValid(fifoBcOut.valid), .outReady(fifoBcIn.ready));

    oclib_async_fifo #(.Width(8), .Depth(32))
    uBC_IN_FIFO (.clockIn(clock), .clockOut(clockAxil), .reset(reset),
                 .outData(axilBcIn.data), .outValid(axilBcIn.valid), .outReady(axilBcOut.ready),
                 .inData(fifoBcIn.data), .inValid(fifoBcIn.valid), .inReady(fifoBcOut.ready));

  end
  else begin
    assign fifoBcOut = axilBcOut;
    assign axilBcIn = fifoBcIn;
  end

  // Instantiate generic serial controller

  oc_bc_control #(.ClockHz(ClockHz),
                  .ExtBcType(BcType),
                  .BcType(BcType),
                  .BcProtocol(BcProtocol),
                  .BlockTopCount(BlockTopCount),
                  .BlockUserCount(BlockUserCount),
                  .UserCsrCount(UserCsrCount),
                  .UserAximSourceCount(UserAximSourceCount),
                  .UserAximSinkCount(UserAximSinkCount),
                  .UserAxisSourceCount(UserAxisSourceCount),
                  .UserAxisSinkCount(UserAxisSinkCount),
                  .ResetSync(ResetSync))
  uCONTROL (.clock(clock), .reset(resetSync), .resetOut(resetOut),
            .extBcIn(fifoBcOut), .extBcOut(fifoBcIn),
            .bcOut(bcOut), .bcIn(bcIn));

`ifdef OC_PCIE_CONTROL_INCLUDE_ILA_DEBUG
  `OC_DEBUG_ILA(uILA1, clockAxil, 1024, 512, 32,
                { axil, axilFb,
                  axilControl, axilControlFb,
                  axilBcOut, axilBcIn,
                  fifoBcOut, fifoBcIn,
                  bcOut, bcIn },
                { resetOut, resetSync, vioReset,
                  axil.awvalid, axil.arvalid,
                  axilControl.awvalid, axilControl.arvalid,
                  axilBcIn.valid, axilBcIn.ready,
                  axilBcOut.valid, axilBcOut.ready,
                  fifoBcIn.valid, fifoBcIn.ready,
                  fifoBcOut.valid, fifoBcOut.ready,
                  bcOut.valid, bcOut.ready,
                  bcIn.valid, bcIn.ready });
  `OC_DEBUG_ILA(uILA2, clock, 8192, 128, 32,
                { resetOut, resetSync, vioReset,
                  fifoBcOut, fifoBcIn,
                  bcOut, bcIn },
                { resetOut, resetSync, vioReset,
                  fifoBcIn.valid, fifoBcIn.ready,
                  fifoBcOut.valid, fifoBcOut.ready,
                  bcOut.valid, bcOut.ready,
                  bcIn.valid, bcIn.ready });
`endif

endmodule // oc_axil_control
