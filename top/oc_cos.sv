
`include "top/oc_top_pkg.sv"
`include "lib/oclib_defines.vh"

module oc_cos
  #(
    // *** MISC ***
    parameter integer Seed = 0,
    // *** REFCLOCK ***
    parameter integer RefClockCount = 1,
    `OC_LOCALPARAM_SAFE(RefClockCount),
    parameter integer RefClockHz [0:RefClockCount-1] = {100_000_000},
    // *** TOP CLOCK ***
    parameter integer ClockTop = oc_top_pkg::ClockIdSingleEndedRef(0),
    // *** LED ***
    parameter integer LedCount = 0,
    `OC_LOCALPARAM_SAFE(LedCount),
    // *** UART ***
    parameter integer UartCount = 0,
    `OC_LOCALPARAM_SAFE(UartCount),
    parameter integer UartBaud [0:UartCountSafe-1] = {115200},
    parameter integer UartControl = 0
    )
  (
   // *** REFCLOCK ***
   input [RefClockCountSafe-1:0]    clockRef,
   // *** RESET ***
   input                            hardReset,
   // *** LED ***
   output logic [LedCountSafe-1:0]  ledOut,
   // *** UART ***
   input [UartCountSafe-1:0]        uartRx,
   output logic [UartCountSafe-1:0] uartTx
   );

  logic                             clockTop;
  assign clockTop = clockRef[ClockTop];

  logic [31:0]  count = Seed;
  always @(posedge clockTop) begin
    if (hardReset) begin
      count <= '0;
      ledOut <= 3'b101;
    end
    else begin
      count <= (count + 1);
      ledOut <= count[29:27];
    end
  end

  // loopback USB UART for now
  assign uartTx[0] = uartRx[0];
  // idle SC UART for now
  assign uartTx[1] = 1'b1;

endmodule // oc_cos
