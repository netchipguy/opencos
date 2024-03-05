
// SPDX-License-Identifier: MPL-2.0

`include "oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oclib_axim_ram #(
                        parameter        type AximType = oclib_pkg::axi4m_32_s,
                        parameter        type AximFbType = oclib_pkg::axi4m_32_fb_s,
                        parameter int    Bits = 1024*1024,
                        parameter        Macro = "auto", // can be "auto", "flops", "distributed", "block", "ultra"
                        parameter int    SyncCycles = 3,
                        parameter bit    ResetSync = oclib_pkg::False,
                        parameter int    ResetPipeline = 0
                       )
  (
   input  clock,
   input  reset,
   input  AximType axim,
   output AximFbType aximFb
   );

  localparam int Width = $bits(axim.w.data);
  localparam int Depth = (Bits / Width);
  localparam int AddressWidth = $clog2(Depth);
  localparam int Latency = ((Bits >= 4*1024*1024) ? 10 :
                            (Bits >= 2*1024*1024) ? 9 :
                            (Bits >= 1*1024*1024) ? 8 :
                            (Bits >=    512*1024) ? 7 :
                            (Bits >=    256*1024) ? 6 :
                            (Bits >=    128*1024) ? 5 : 4);

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  AximType aximInt;
  AximFbType aximIntFb;

  oclib_fifo #(.Width($bits(axim.aw)), .Depth(32))
  uAW_FIFO (.clock(clock), .reset(resetSync),
            .inValid(axim.awvalid), .inData(axim.aw), .inReady(aximFb.awready),
            .outValid(aximInt.awvalid), .outData(aximInt.aw), .outReady(aximIntFb.awready));

  oclib_fifo #(.Width($bits(axim.w)), .Depth(32))
  uW_FIFO (.clock(clock), .reset(resetSync),
           .inValid(axim.wvalid), .inData(axim.w), .inReady(aximFb.wready),
           .outValid(aximInt.wvalid), .outData(aximInt.w), .outReady(aximIntFb.wready));

  oclib_fifo #(.Width($bits(axim.ar)), .Depth(32))
  uAR_FIFO (.clock(clock), .reset(resetSync),
            .inValid(axim.arvalid), .inData(axim.ar), .inReady(aximFb.arready),
            .outValid(aximInt.arvalid), .outData(aximInt.ar), .outReady(aximIntFb.arready));

  logic          almostFullR;
  logic          almostFullB;

  oclib_fifo #(.Width($bits(aximFb.r)), .Depth(32), .AlmostFull(32-4-Latency))
  uR_FIFO (.clock(clock), .reset(resetSync), .almostFull(almostFullR),
           .inValid(aximIntFb.rvalid), .inData(aximIntFb.r), .inReady(aximInt.rready),
           .outValid(aximFb.rvalid), .outData(aximFb.r), .outReady(axim.rready));

  oclib_fifo #(.Width($bits(aximFb.b)), .Depth(32), .AlmostFull(32-4))
  uB_FIFO (.clock(clock), .reset(resetSync), .almostFull(almostFullB),
           .inValid(aximIntFb.bvalid), .inData(aximIntFb.b), .inReady(aximInt.bready),
           .outValid(aximFb.bvalid), .outData(aximFb.b), .outReady(axim.bready));

  logic                    write;
  logic [AddressWidth-1:0] writeAddress;
  logic [Width-1:0]        writeData;
  logic                    read;
  logic [AddressWidth-1:0] readAddress;
  logic [Width-1:0]        readData;

  assign write = (aximInt.awvalid && aximInt.wvalid && !almostFullB);
  assign aximIntFb.awready = write;
  assign aximIntFb.wready = write;
  assign aximIntFb.bvalid = write;
  assign aximIntFb.b.resp = '0;
  assign aximIntFb.b.id = aximInt.aw.id;

  assign read = (aximInt.arvalid && !almostFullR);
  assign aximIntFb.arready = read;

  oclib_pipeline #(.Width($bits(aximInt.ar.id)+1), .Length(Latency))
  uREAD_PIPE (.clock(clock), .in({aximInt.ar.id,read}), .out({aximIntFb.r.id,aximIntFb.rvalid}));

  assign aximIntFb.r.resp = '0;
  assign aximIntFb.r.last = 1'b1;

  localparam               AddressLsb = $clog2(Width/8);

  oclib_ram1r1w #(.Width(Width), .Depth(Depth), .Latency(Latency), .Macro(Macro))
  uRAM (.clock(clock),
        .write(write), .writeAddress(aximInt.aw.addr[AddressWidth+AddressLsb-1:AddressLsb]), .writeData(aximInt.w.data),
        .read(read), .readAddress(aximInt.ar.addr[AddressWidth+AddressLsb-1:AddressLsb]), .readData(aximIntFb.r.data));

  `ifdef SIMULATION
    task RamWrite ( input [AddressWidth-1:0] _address, input [Width-1:0] _data );
      uRAM.RamWrite(_address, _data);
    endtask // RamWrite
    task RamRead ( input [AddressWidth-1:0] _address, output [Width-1:0] _data );
      uRAM.RamRead(_address, _data);
    endtask // RamRead
  `endif // SIMULATION

endmodule // oclib_axim_ram
