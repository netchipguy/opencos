
// SPDX-License-Identifier: MPL-2.0

`include "sim/ocsim_pkg.sv"
`include "sim/ocsim_defines.vh"
`include "lib/oclib_pkg.sv"
`include "lib/oclib_defines.vh"

module ocsim_axim_source
  #(
    parameter type AxiType = oclib_pkg::axi4m_64_s,
    parameter type AxiFbType = oclib_pkg::axi4m_64_fb_s
    )
  (
   input  clock,
   input  reset,
   output AxiType axi,
   input  AxiFbType axiFb
   );

  localparam int AddressWidth = $bits(axi.aw.addr);
  localparam int DataWidth = $bits(axi.w.data);

  always @(posedge clock) begin
    if (reset) axi <= '0;
  end

  task Write32 (input [AddressWidth-1:0] address, input [3:0] [7:0] data);
    int dataOffset, id;
    dataOffset = ((DataWidth == 64) ? (address & 4) : 0);
    id = ocsim_pkg::RandInt(0,7);
    fork
      begin
        repeat (ocsim_pkg::RandInt(1,10)) @(posedge clock);
        axi.awvalid <= 1'b1;
        axi.aw <= '0;
        axi.aw.addr <= address;
        axi.aw.cache <= 3;
        axi.aw.lock <= 0;
        axi.aw.len <= 0;
        axi.aw.size <= 2;
        axi.aw.prot <= 2;
        axi.aw.burst <= 1;
        axi.aw.id <= id;
        while (!(axi.awvalid && axiFb.awready)) @(posedge clock);
        axi.awvalid <= 1'b0;
        axi.aw <= 'X;
      end
      begin
        repeat (ocsim_pkg::RandInt(1,10)) @(posedge clock);
        axi.wvalid <= 1'b1;
        axi.w <= '0;
        axi.w.data[dataOffset+0] <= data[0];
        axi.w.data[dataOffset+1] <= data[1];
        axi.w.data[dataOffset+2] <= data[2];
        axi.w.data[dataOffset+3] <= data[3];
        axi.w.strb[dataOffset+0] <= 1;
        axi.w.strb[dataOffset+1] <= 1;
        axi.w.strb[dataOffset+2] <= 1;
        axi.w.strb[dataOffset+3] <= 1;
        axi.w.last <= 1;
        while (!(axi.wvalid && axiFb.wready)) @(posedge clock);
        axi.wvalid <= 1'b0;
        axi.w <= 'X;
      end
      begin
        repeat (ocsim_pkg::RandInt(1,10)) @(posedge clock);
        axi.bready <= 1'b1;
        while (!(axiFb.bvalid && axi.bready)) @(posedge clock);
        axi.bready <= 1'b0;
        `OC_ASSERT(axiFb.b.resp == 0);
        `OC_ASSERT(axiFb.b.id == id);
      end
    join
    $display("%t %m: %08x => [%08x]", $realtime, data, address);
  endtask // Write32

  task ReadCheck32 (input [AddressWidth-1:0] address, input [3:0] [7:0] expectedData);
    logic [3:0] [7:0] readData;
    Read32(address, readData);
    `OC_ASSERT_EQUAL(readData, expectedData);
  endtask // ReadCheck32

  task Read32 (input [AddressWidth-1:0] address, output logic [3:0] [7:0] data);
    int dataOffset, id;
    dataOffset = ((DataWidth == 64) ? (address & 4) : 0);
    id = ocsim_pkg::RandInt(0,7);
    fork
      begin
        repeat (ocsim_pkg::RandInt(1,10)) @(posedge clock);
        axi.arvalid <= 1'b1;
        axi.ar <= '0;
        axi.ar.addr <= address;
        axi.ar.cache <= 3;
        axi.ar.lock <= 0;
        axi.ar.len <= 0;
        axi.ar.size <= 2;
        axi.ar.prot <= 2;
        axi.ar.burst <= 1;
        axi.ar.id <= id;
        while (!(axi.arvalid && axiFb.arready)) @(posedge clock);
        axi.arvalid <= 1'b0;
        axi.ar <= 'X;
      end
      begin
        repeat (ocsim_pkg::RandInt(1,10)) @(posedge clock);
        axi.rready <= 1'b1;
        while (!(axiFb.rvalid && axi.rready)) @(posedge clock);
        axi.rready <= 1'b0;
        data[0] = axiFb.r.data[dataOffset+0];
        data[1] = axiFb.r.data[dataOffset+1];
        data[2] = axiFb.r.data[dataOffset+2];
        data[3] = axiFb.r.data[dataOffset+3];
        `OC_ASSERT(axiFb.r.resp == 0);
        `OC_ASSERT(axiFb.r.last == 1);
        `OC_ASSERT(axiFb.r.id == id);
      end
    join

    $display("%t %m : %08x <= [%08x]", $realtime, data, address);
  endtask // Read32

endmodule // ocsim_axim_source
