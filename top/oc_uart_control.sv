
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"
`include "lib/oclib_uart_pkg.sv"

module oc_uart_control
  #(
    parameter integer            ClockHz = 100_000_000,
    parameter integer            Baud = 115_200,
    parameter                    type UartBcType = oclib_pkg::bc_8b_bidi_s, // if uart is physically far from rest of this block
    parameter                    type BcType = oclib_pkg::bc_8b_bidi_s,
    parameter                    type BcProtocol = oclib_pkg::csr_32_s,
    parameter logic [0:1] [7:0]  BlockTopCount = '0,
    parameter logic [0:1] [7:0]  BlockUserCount = '0,
    parameter logic [7:0]        UserCsrCount = '0,
    parameter logic [7:0]        UserAximSourceCount = '0,
    parameter logic [7:0]        UserAximSinkCount = '0,
    parameter logic [7:0]        UserAxisSourceCount = '0,
    parameter logic [7:0]        UserAxisSinkCount = '0,
    parameter bit                ResetSync = oclib_pkg::False,
    parameter integer            ErrorWidth = oclib_uart_pkg::ErrorWidth,
    parameter logic [0:15] [7:0] UserSpace = `OC_VAL_ASDEFINED_ELSE(USER_APP_STRING, "none            ")
    )
  (
   input                         clock,
   input                         reset,
   output logic                  resetOut,
   output logic [ErrorWidth-1:0] uartError,
   input                         uartRx,
   output logic                  uartTx,
   input                         BcType bcIn,
   output                        BcType bcOut
   );

  logic                         vioReset;
  logic                         resetSync;

  oclib_synchronizer #(.Enable(ResetSync))
  uRESET_SYNC (.clock(clock), .in(reset || vioReset), .out(resetSync));

  // Philosophy here is to not backpressure the RX channel.  We dont want to block attempts to
  // reset or resync, and you cannot overrun the RX state machine when following the protocol.

  UartBcType bcRx, bcTx;

  oclib_uart #(.ClockHz(ClockHz), .Baud(Baud), .BcType(UartBcType))
  uUART (.clock(clock), .reset(resetSync), .error(uartError),
         .rx(uartRx), .tx(uartTx),
         .bcOut(bcRx), .bcIn(bcTx));

  // Instantiate generic serial controller

  oc_bc_control #(.ClockHz(ClockHz),
                  .ExtBcType(UartBcType),
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
            .extBcIn(bcRx), .extBcOut(bcTx),
            .bcOut(bcOut), .bcIn(bcIn));

  // **************************
  // DEBUG LOGIC
  // **************************

`ifdef OC_UART_CONTROL_INCLUDE_VIO_DEBUG
  `OC_DEBUG_VIO(uVIO, clock, 32, 32,
                { resetSync, resetOut, vioReset,
                  bcTx.valid, bcTx.ready,
                  bcRx.valid, bcRx.ready,
                  bcOut.valid, bcOut.ready,
                  bcIn.valid, bcIn.ready,
                  uartRx, uartTx },
                { vioReset });
`else
  assign vioReset = '0;
`endif

`ifdef OC_UART_CONTROL_INCLUDE_ILA_DEBUG
  `OC_DEBUG_ILA(uILA, clock, 8192, 128, 32,
                { resetOut, resetSync, vioReset,
                  uartError, uartRx, uartTx,
                  bcTx, bcRx, bcOut, bcIn },
                { resetOut, resetSync, vioReset,
                  (|uartError), uartRx, uartTx,
                  bcTx.valid, bcTx.ready,
                  bcRx.valid, bcRx.ready,
                  bcOut.valid, bcOut.ready,
                  bcIn.valid, bcIn.ready });
`endif

endmodule // oc_uart_control
