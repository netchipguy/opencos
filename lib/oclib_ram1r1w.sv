
// SPDX-License-Identifier: MPL-2.0

`include "oclib_defines.vh"

module oclib_ram1r1w #(
                       parameter int    Width = 32,
                       parameter        type DataType = logic [Width - 1:0],
                       parameter int    Depth = 32,
                       localparam int   AddressWidth = $clog2(Depth),
                       parameter int    Latency = 1,
                       localparam int   Bits = ($bits(DataType) * Depth),
                       parameter        Macro = "auto" // can be "auto", "flops", "distributed", "block", "ultra"
                       )
  (
   input                    clock,
   input                    write,
   input [AddressWidth-1:0] writeAddress,
   input                    DataType writeData,
   input                    read,
   input [AddressWidth-1:0] readAddress,
   output                   DataType readData
   );

  localparam bit            UsingXpm = (
`ifdef OC_LIBRARY_ULTRASCALE_PLUS
  `ifndef OCLIB_RAM_DISABLE_XPM
                                        1 ||
  `endif
`endif
                                        0);

  localparam bit            UsingFlops = (!UsingXpm) || (Macro == "flops");

  if (UsingXpm) begin : impl
`ifdef OC_LIBRARY_ULTRASCALE_PLUS
    xpm_memory_sdpram #(
                        .CLOCKING_MODE("common_clock"),
                        .ADDR_WIDTH_A(AddressWidth),
                        .ADDR_WIDTH_B(AddressWidth),
                        .BYTE_WRITE_WIDTH_A(Width),
                        .MEMORY_OPTIMIZATION("false"),
                        .MEMORY_PRIMITIVE(Macro),
                        .MEMORY_SIZE(Bits),
                        .READ_DATA_WIDTH_B(Width),
                        .READ_LATENCY_B(Latency),
                        .WRITE_DATA_WIDTH_A(Width),
                        .WRITE_MODE_B("read_first")
                        )
    uRAM (
          .clka(clock),
          .clkb(clock),
          .ena(write),
          .enb(read),
          .wea(1'b1),
          .addra(writeAddress),
          .dina(writeData),
          .addrb(readAddress),
          .doutb(readData),
          .rstb(1'b0),
          .regceb(1'b1),
          .injectsbiterra(1'b0),
          .injectdbiterra(1'b0),
          .sbiterrb(),
          .dbiterrb(),
          .sleep(1'b0)
          );
`endif //  `ifdef OC_LIBRARY_ULTRASCALE_PLUS


  `ifdef SIMULATION
    task RamWrite ( input [AddressWidth-1:0] _address, input DataType _data );
      uRAM.xpm_memory_base_inst.mem[_address] = _data;
    endtask // RamWrite
    task RamRead ( input [AddressWidth-1:0] _address, output DataType _data );
      _data = uRAM.xpm_memory_base_inst.mem[_address];
    endtask // RamRead
  `endif // SIMULATION

  end // block: impl
  else if (UsingFlops) begin : impl

    DataType                  mem [Depth-1:0];
    logic [AddressWidth-1:0]  writeAddress_q;
    DataType                  writeData_q;
    logic                     write_q;

    // We register the write side inputs, and perform the write on the following negedge.
    // This ensures any read to the same address goes through first.  This is the most compatible
    // mode for the vendor memories
    // TODO: add hazard checking

    always @(posedge clock) begin
      write_q <= write;
      writeAddress_q <= writeAddress;
      writeData_q <= writeData;
    end

    always @(negedge clock) begin
      if (write_q) mem[writeAddress_q] <= writeData_q;
    end

    if (Latency==0) begin
      assign readData = mem[readAddress];
    end // Latency == 0
    else begin
      DataType readData_pipe [Latency-1:0];
      always @(posedge clock) begin
        if (read) begin
          readData_pipe[0] <= mem[readAddress];
        end
      end
      for (genvar i=1; i<Latency; i=i+1) begin
        always @(posedge clock) begin
          readData_pipe[i] <= readData_pipe[i-1];
        end
      end
      assign readData = readData_pipe[Latency-1];
    end

`ifdef SIMULATION
    task RamWrite ( input [AddressWidth-1:0] _address, input DataType _data );
      mem[_address] = _data;
    endtask // RamWrite
    task RamRead ( input [AddressWidth-1:0] _address, output DataType _data );
      _data = mem[_address];
    endtask // RamRead
`endif // SIMULATION

  end //  if (UsingFlops)

  else begin : impl
  `OC_STATIC_ERROR("Didn't come up with a valid implementation");
  `ifdef SIMULATION
  // dummy tasks because we need something under impl
    task RamWrite ( input [AddressWidth-1:0] _address, input DataType _data );
    endtask // RamWrite
    task RamRead ( input [AddressWidth-1:0] _address, output DataType _data );
    endtask // RamRead
  `endif // SIMULATION
  end // block: impl

  // these are the tasks that external processes will call, they will then call the
  // implementation specific version above.  This avoids exposing the internals...

`ifdef SIMULATION
  task RamWrite ( input [AddressWidth-1:0] address, input DataType data );
    impl.RamWrite(address, data);
  endtask // RamWrite
  task RamRead ( input [AddressWidth-1:0] address, output DataType data );
    impl.RamRead(address, data);
  endtask // RamRead
`endif // SIMULATION

endmodule // oclib_ram1r1w
