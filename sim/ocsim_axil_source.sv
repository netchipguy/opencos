
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"
`include "sim/ocsim_pkg.sv"

module ocsim_axil_source #(
                           parameter     type AxilType = oclib_pkg::axil_32_s,
                           parameter     type AxilFbType = oclib_pkg::axil_32_fb_s,
                           parameter int Debug = 0,
                           parameter int Stress = `OC_VAL_ASDEFINED_ELSE(SIM_STRESS, 0)
                           )
  (
   input  clock,
   input  reset,
   output AxilType axil,
   input  AxilFbType axilFb
   );

  localparam AddressWidth = $bits(axil.awaddr);
  localparam DataWidth = $bits(axil.wdata);

  logic   stress = Stress;
  int     debug = Debug;

  always @(posedge clock) begin
    if (reset) axil <= 0;
  end

  task CsrWrite (input [AddressWidth-1:0] address,
                 input [DataWidth-1:0] data);
    logic                   running;
    if (debug) $display("%t %m: %x -> [%x] (starting)", $realtime, data, address);
    running = 1;
    @(posedge clock);
    fork
      begin
        while (running) begin
          axil.bready <= (stress ? ocsim_pkg::RandPercent(20) : 1'b1);
          @(posedge clock);
        end
      end
      begin
        fork
          begin
            if (stress) while (ocsim_pkg::RandPercent(80)) @(posedge clock);
            axil.awvalid <= 1;
            axil.awaddr <= address;
            @(posedge clock);
            while (axilFb.awready == 0) @(posedge clock);
            axil.awvalid <= 0;
          end
          begin
            if (stress)  while (ocsim_pkg::RandPercent(80)) @(posedge clock);
            axil.wvalid <= 1;
            axil.wdata <= data;
            @(posedge clock);
            while (axilFb.wready == 0) @(posedge clock);
            axil.wvalid <= 0;
          end
        join
        while ((axilFb.bvalid && axil.bready) == 0) @(posedge clock);
        running = 0;
      end
    join
    axil.bready <= 0;
    @(posedge clock);
    if (debug) $display("%t %m: %x -> [%x]", $realtime, data, address);
  endtask // CsrWrite

  task CsrRead (input [AddressWidth-1:0]     address,
                output logic [DataWidth-1:0] data,
                input                        check = 0);
    if (debug) $display("%t %m%0s:          <- [%08x] (start)", $realtime,  check ? "Check" : "", address);
    if (stress)  while (ocsim_pkg::RandPercent(50)) @(posedge clock);
    @(posedge clock);
    axil.araddr  <= address;
    axil.arvalid <= 1;
    axil.rready <= (stress ? ocsim_pkg::RandPercent(20) : 1'b1);
    @(posedge clock);
    while (axilFb.arready == 0) begin
      axil.rready <= (stress ? ocsim_pkg::RandPercent(20) : 1'b1);
      @(posedge clock);
    end
    axil.arvalid <= 0;
    while ((axilFb.rvalid && axil.rready) == 0) begin
      axil.rready <= (stress ? ocsim_pkg::RandPercent(20) : 1'b1);
      @(posedge clock);
    end
    axil.rready <= 0;
    data = axilFb.rdata;
    @(posedge clock);
    if (debug) $display("%t %m%0s: %08x <- [%08x] (done)", $realtime,  check ? "Check" : "", data, address);
  endtask // CsrRead

  task CsrReadCheck (input [AddressWidth-1:0]  address,
                     input [DataWidth-1:0]  data,
                     input [DataWidth-1:0]  mask = {DataWidth{1'b1}});
    logic [DataWidth-1:0]                   readData;
    CsrRead(address, readData, 1);
    if (readData !== data) begin
      // read data mismatch
      $display("%t %m ERROR: readData (%08x) !== expected (%08x)", $realtime, readData, data);
      $finish;
    end
  endtask // CsrReadCheck

endmodule // ocsim_axil_source
