
// SPDX-License-Identifier: MPL-2.0

`ifndef __OCLIB_UART_PKG
`define __OCLIB_UART_PKG

package oclib_uart_pkg;

  localparam ErrorWidth = 3;
  localparam ErrorInvalidStart = 0;
  localparam ErrorInvalidStop = 1;
  localparam ErrorOverflow = 2;

endpackage
`endif // __OCLIB_UART_PKG
