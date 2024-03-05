
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_async_fifo #(
                          parameter int     Width = 32,
                          parameter int     Depth = 32,
                          parameter         type DataType = logic [Width-1:0],
                          parameter int     AlmostFull = (Depth-8),
                          parameter int     AlmostEmpty = 8,
                          parameter bit     BlockSimReporting = oclib_pkg::False,
                          parameter integer SyncCycles = 3
)
  (
   input        clockIn,
   input        clockOut,
   input        reset,
   output logic almostFull,
   output logic almostEmpty,
   input        DataType inData,
   input        inValid,
   output logic inReady,
   output       DataType outData,
   output logic outValid,
   input        outReady
   );

  localparam integer DataWidth = $bits(inData);
  localparam integer AddressWidth = $clog2(Depth);



  // wow this is ugly, will find a better way
  localparam bit     UsingXpm = (
`ifdef OC_LIBRARY_ULTRASCALE_PLUS
  `ifndef OCLIB_FIFO_DISABLE_XPM
                                 1 ||
  `endif
`endif
                                 0);

  if (Depth == 0) begin
    `OC_STATIC_ERROR("Cannot implement a zero-depth ASYNC FIFO");
  end
  else if (UsingXpm) begin

    // we can't get in here without this being set, but we still need to skip during compilations
`ifdef OC_LIBRARY_ULTRASCALE_PLUS

    logic fullWrite, emptyRead, busyWrite, busyRead;

    xpm_fifo_async #(.CDC_SYNC_STAGES(SyncCycles),
                     .FIFO_MEMORY_TYPE("bram"), // need to make this smarter (LUTRAM, URAM)
                     .READ_DATA_WIDTH(DataWidth),
                     .WRITE_DATA_WIDTH(DataWidth),
                     .FIFO_WRITE_DEPTH(Depth),
                     .READ_MODE("fwft"),
                     .FIFO_READ_LATENCY(0), // needed given "fwft"
                     .PROG_EMPTY_THRESH(AlmostEmpty),
                     .PROG_FULL_THRESH(AlmostFull),
                     .RD_DATA_COUNT_WIDTH(1),
                     .WR_DATA_COUNT_WIDTH(1),
                     .FULL_RESET_VALUE(0),
                     .DOUT_RESET_VALUE("0"),
                     .WAKEUP_TIME(0),
                     .USE_ADV_FEATURES("0202"),
                     .ECC_MODE("no_ecc")
                     )
    uXPM (
          .almost_empty(), // these only give one entry notice
          .almost_full(),
          .data_valid(),
          .dbiterr(),
          .din(inData),
          .dout(outData),
          .empty(emptyRead),
          .full(fullWrite),
          .injectdbiterr(1'b0),
          .injectsbiterr(1'b0),
          .overflow(),
          .prog_empty(almostEmpty),
          .prog_full(almostFull),
          .rd_clk(clockOut),
          .rd_data_count(),
          .rd_en(outReady),
          .rd_rst_busy(busyRead),
          .rst(reset),
          .sbiterr(),
          .sleep(1'b0),
          .underflow(),
          .wr_ack(),
          .wr_clk(clockIn),
          .wr_data_count(),
          .wr_en(inValid),
          .wr_rst_busy(busyWrite)
          );

    assign inReady = !(fullWrite || busyWrite);
    assign outValid = !(emptyRead || busyRead);

    /*
      USE_ADV_FEATURES
     // write side
     0 : overflow
     1 : prog_full
     2 : wr_data_count
     3 : almost_full
     4 : wr_ack
     // read side
     8 : underflow
     9 : prog_empty
     10 : rd_data_count
     11 : almost_empty
     12 : data_valid
     */

`endif // OC_LIBRARY_ULTRASCALE_PLUS

  end // if (UsingXpm)
  else begin
    // This is a basic RTL implementation, for sim (or unsupported library situations, but this is intended for simplicity
    // and for now isn't really optimized for timing, power, etc).  Even latency isn't ideal.

    // RESETS

    oclib_module_reset #(.SyncCycles(SyncCycles))
    uREAD_RESET (.clock(clockOut), .in(reset), .out(resetRead));

    oclib_module_reset #(.SyncCycles(SyncCycles))
    uWRITE_RESET (.clock(clockIn), .in(reset), .out(resetWrite));

    localparam int PointerWidth = (AddressWidth + 1);

    // CLOCK CROSSING SIGNALS

    logic [PointerWidth-1:0] readPointerGray;
    logic [PointerWidth-1:0] writePointerGray;

    // READ CONTROL PATH

    logic                    read;
    logic [PointerWidth-1:0] readPointer;
    logic [PointerWidth-1:0] readPointerNext;
    logic [PointerWidth-1:0] readPointerGrayNext;
    logic [PointerWidth-1:0] writePointerGrayInRead;
    logic [PointerWidth-1:0] writePointerInRead;
    logic [PointerWidth-1:0] readDepthNext;
    logic                    readLsbsMatchNext;
    logic                    readMsbsMatchNext;

    oclib_bin_to_gray #(.Width(PointerWidth))
    uREAD_BIN2GRAY (.bin(readPointerNext), .gray(readPointerGrayNext));

    oclib_synchronizer #(.Width(PointerWidth), .SyncCycles(SyncCycles) )
    uREAD_GRAY_SYNC (.clock(clockOut), .in(writePointerGray), .out(writePointerGrayInRead));

    oclib_gray_to_bin #(.Width(PointerWidth))
    uREAD_GRAY2BIN (.gray(writePointerGrayInRead), .bin(writePointerInRead));

    assign read = outValid && outReady;
    assign readPointerNext = (readPointer + {{PointerWidth-1{1'b0}},read});
    assign readLsbsMatchNext = (readPointerNext[PointerWidth-2:0] == writePointerInRead[PointerWidth-2:0]);
    assign readMsbsMatchNext = (readPointerNext[PointerWidth-1] == writePointerInRead[PointerWidth-1]);
    assign readDepthNext = (readLsbsMatchNext ? (readMsbsMatchNext ? '0 : Depth) :
                            (({1'b1, writePointerInRead[PointerWidth-2:0]} - {1'b0, readPointerNext[PointerWidth-2:0]}) &
                             {1'b0, {AddressWidth{1'b1}}}));

    always_ff @(posedge clockOut) begin
      if (resetRead) begin
        readPointer <= 0;
        readPointerGray <= 0;
        outValid <= 0;
        almostEmpty <= 1;
      end
      else begin
        readPointer <= readPointerNext;
        readPointerGray <= readPointerGrayNext;
        outValid <= (readDepthNext > 0);
        almostEmpty <= (readDepthNext <= AlmostEmpty);
      end
    end

    // WRITE CONTROL PATH

    logic                    write;
    logic [PointerWidth-1:0] writePointer;
    logic [PointerWidth-1:0] writePointerNext;
    logic [PointerWidth-1:0] writePointerGrayNext;
    logic [PointerWidth-1:0] readPointerGrayInWrite;
    logic [PointerWidth-1:0] readPointerInWrite;
    logic [PointerWidth-1:0] writeDepthNext;
    logic                    writeLsbsMatchNext;
    logic                    writeMsbsMatchNext;

    oclib_bin_to_gray #(.Width(PointerWidth))
    uWRITE_BIN2GRAY (.bin(writePointerNext), .gray(writePointerGrayNext));

    oclib_synchronizer #(.Width(PointerWidth), .SyncCycles(SyncCycles) )
    uWRITE_GRAY_SYNC (.clock(clockIn), .in(readPointerGray), .out(readPointerGrayInWrite));

    oclib_gray_to_bin #(.Width(PointerWidth))
    uWRITE_GRAY2BIN (.gray(readPointerGrayInWrite), .bin(readPointerInWrite));

    assign write = (inValid && inReady);
    assign writePointerNext = (writePointer + {{PointerWidth-1{1'b0}},write});
    assign writeLsbsMatchNext = (writePointerNext[PointerWidth-2:0] == readPointerInWrite[PointerWidth-2:0]);
    assign writeMsbsMatchNext = (writePointerNext[PointerWidth-1] == readPointerInWrite[PointerWidth-1]);
    assign writeDepthNext = (writeLsbsMatchNext ? (writeMsbsMatchNext ? '0 : Depth) :
                             (({1'b1, writePointerNext[PointerWidth-2:0]} - {1'b0, readPointerInWrite[PointerWidth-2:0]}) &
                              {1'b0, {AddressWidth{1'b1}}}));

    always_ff @(posedge clockIn) begin
      if (resetWrite) begin
        writePointer <= 0;
        writePointerGray <= 0;
        inReady <= 0;
        almostFull <= 0;
      end
      else begin
        writePointer <= writePointerNext;
        writePointerGray <= writePointerGrayNext;
        inReady <= (writeDepthNext < Depth);
        almostFull <= (writeDepthNext >= AlmostFull);;
      end
    end

    // DATAPATH

    logic [DataWidth-1:0]          mem [Depth-1:0];

    always_ff @(posedge clockOut) begin
      outData <=  mem[readPointerNext[AddressWidth-1:0]];
    end

    always_ff @(posedge clockIn) begin
`ifdef OC_ASYNC_FIFO_PARALLEL
      for (int i=0; i < Depth; i++) begin
        if (write && (i == writePointer[AddressWidth-1:0])) begin
          mem[i] <= inData;
        end
      end
`else
      if (write) begin
        mem[writePointer[AddressWidth-1:0]] <= inData;
      end
`endif
    end

  end // else: !if(UsingXpm)


`ifdef SIMULATION
  // during sims this will always be here, regardless of implementation above, so testbench/waves can always refer to it
  int simDepth;
  if (Depth == 0) begin
    initial simDepth = 0;
  end
  else begin
    always @(posedge clockOut) simDepth = (reset ? '0: (simDepth + (outValid&&outReady)));
    always @(posedge clockIn) simDepth = (reset ? '0: (simDepth + (inValid&&inReady)));
  end
  `ifdef SIM_FIFO_DEPTH_REPORT
  int simMaxDepth;
  longint simTotalDepth;
  int simTotalSamples;
  always @(posedge clockWrite) begin
    if (reset) begin
      simMaxDepth <= 0;
      simTotalDepth <= 0;
      simTotalSamples <= 0;
    end
    else begin
      simMaxDepth <= ((simDepth > simMaxDepth) ? simDepth : simMaxDepth);
      simTotalDepth <= (simTotalDepth + simDepth);
      simTotalSamples <= (simTotalSamples + 1);
    end
  end
  always begin
    #( `OC_FROM_DEFINE_ELSE(SIM_REPORT_INTERVAL_NS, 5000) * 1ns);
    if (!BlockSimReporting) begin
      $display("%t %m: Depth=%4d/%4d (Max=%4d, Avg=%6.1f)", $realtime, simDepth, Depth, simMaxDepth,
               (real'(simTotalDepth) / real'(simTotalSamples)));
    end
  end
  `endif // ifdef SIM_FIFO_DEPTH_REPORT
`endif // ifdef SIMULATION

endmodule // oclib_fifo
