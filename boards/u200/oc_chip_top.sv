
// SPDX-License-Identifier: MPL-2.0

`include "boards/u200/oc_board_defines.vh"

module oc_chip_top
  #(
    // Misc
    parameter integer Seed = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_SEED, 0), // seed to generate varying implementation results
    // RefClocks
    parameter integer RefClockCount = 1,
    parameter integer RefClockHz [RefClockCount-1:0] = { 156250000 },
    parameter integer RefClockTop = 0,
    // LED
    parameter integer LedCount = `OC_VAL_ASDEFINED_ELSE(OC_BOARD_LED_COUNT,3),
    `OC_LOCALPARAM_SAFE(LedCount)
    )
  (
   input  USER_SI570_CLOCK_P, USER_SI570_CLOCK_N, // this is our generic refclk

   output STATUS_LED0_FPGA, // red, bottom
   output STATUS_LED1_FPGA, // yellow, middle
   output STATUS_LED2_FPGA  // green, top
   );

  // REFCLKS
  `OC_STATIC_ASSERT(RefClockCount>0);
  `OC_STATIC_ASSERT(RefClockCount<2);
  (* dont_touch = "yes" *)
  logic [RefClockCount-1:0] clockRef;

  IBUFDS uIBUF_USER_SI570_CLOCK (.O(clockRef[0]), .I(USER_SI570_CLOCK_P), .IB(USER_SI570_CLOCK_N));

  // LED
  `OC_STATIC_ASSERT(LedCount<=3);
  logic [LedCountSafe-1:0]  ledOut;
  if (LedCount>0) OBUF uIOBUF_STATUS_LED0_FPGA (.O(STATUS_LED0_FPGA), .I(ledOut[0]) );
  if (LedCount>1) OBUF uIOBUF_STATUS_LED1_FPGA (.O(STATUS_LED1_FPGA), .I(ledOut[1]) );
  if (LedCount>2) OBUF uIOBUF_STATUS_LED2_FPGA (.O(STATUS_LED2_FPGA), .I(ledOut[2]) );

  // TEMP LOGIC
  logic [31:0] count = Seed;
  always @(posedge clockRef[0]) begin
    count <= (count + 1);
    ledOut <= count[27:25];
  end

endmodule // oc_chip_top
