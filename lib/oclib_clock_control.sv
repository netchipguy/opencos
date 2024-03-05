
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_clock_control #(
                             parameter integer ThrottleMapW = 8,
                             parameter bit     ThrottleMap = oclib_pkg::False,
                             parameter bit     AutoThrottle = oclib_pkg::False,
                             parameter integer SyncCycles = 3,
                             parameter bit     ResetSync = oclib_pkg::False,
                             parameter integer ResetPipeline = 0
                             )
  (
   input                    clockIn,
   input                    reset,
   output logic             clockOut,
   input [ThrottleMapW-1:0] throttleMap,
   input                    thermalWarning
   );

  logic                     resetSync;
  logic [ThrottleMapW-1:0]  throttleMapSync;
  logic                     thermalWarningSync;

  oclib_synchronizer #(.Width(ThrottleMapW+1), .SyncCycles(SyncCycles))
  uSYNC (.clock(clockIn), .in({~throttleMap, thermalWarning}), .out({throttleMapSync, thermalWarningSync}));

  oclib_reset #(.StartPipeCycles(3), .ResetCycles(0))
  uRESET (.clock(clockIn), .in(reset), .out(resetSync));

  // ThrottleMap feature
  logic throttleOut;
  if (ThrottleMap) begin
    localparam ThrottleMapCounterW = $clog2(ThrottleMapW);
    logic [ThrottleMapCounterW-1:0] throttleCount;
    logic                           throttleCountTC;
    always_ff @(posedge clockIn) begin
      throttleCountTC <= (throttleCount == (ThrottleMapW-2));
      throttleCount <= (resetSync ? '0 : (throttleCountTC ? '0 : (throttleCount+'d1)));
      throttleOut <= throttleMapSync[throttleCount];
    end
  end
  else begin
    assign throttleOut = 1'b1;
  end

  // AutoThrottle feature (throttles clock to half speed for now)
  logic thermalOut;
  if (AutoThrottle) begin
    always_ff @(posedge clockIn) begin
      thermalOut <= (thermalWarningSync ? (thermalOut ^ throttleOut) : throttleOut);
    end
  end
  else begin
    assign thermalOut = throttleOut;
  end

  // Clock Control Primitive

`ifdef OC_LIBRARY_ULTRASCALE_PLUS

  logic clockInBuf;
  BUFG uINBUF (.I(clockIn),
               .O(clockInBuf));

  logic clockGate;
  always_ff @(negedge clockInBuf) clockGate <= thermalOut;

  BUFGCTRL #(.INIT_OUT(1))
  uBUF (.O(clockOut),
        .I0(clockInBuf),
        .S0(1'b1),
        .CE0(clockGate),
        .IGNORE0(1'b0),
        .I1(1'b1),
        .S1(1'b0),
        .CE1(1'b0),
        .IGNORE1(1'b1));

`else
  logic clockGate;
  always_ff @(negedge clockIn) clockGate <= thermalOut;
  assign clockOut = (clockIn & clockGate);
`endif

endmodule // oclib_clock_control
