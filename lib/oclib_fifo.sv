
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_fifo #(parameter int Width = 32,
                    parameter int Depth = 32,
                    parameter     type DataType = logic [Width-1:0],
                    parameter int AlmostFull = (Depth-8),
                    parameter int AlmostEmpty = 8,
                    parameter bit BlockSimReporting = oclib_pkg::False)
  (
   input        clock,
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
  localparam bit     UsingSrl = ((Depth <= 32) &&
`ifdef OC_LIBRARY_ULTRASCALE_PLUS
  `ifndef OCLIB_FIFO_DISABLE_SRL
                                 1 ||
  `endif
`endif
                                 0);

  localparam bit     UsingXpm = (
`ifdef OC_LIBRARY_ULTRASCALE_PLUS
  `ifndef OCLIB_FIFO_DISABLE_XPM
                                 1 ||
  `endif
`endif
                                 0);

  if (Depth == 0) begin
    assign outData = inData;
    assign outValid = inValid;
    assign inReady = outReady;
  end
  else if (UsingSrl) begin

    // This should map efficiently into SRLs for 32-deep FIFOs
    logic [DataWidth-1:0]    mem [Depth-1:0];
    logic                    write;
    logic                    read;
    logic                    full;
    logic                    empty;
    logic [AddressWidth-1:0] readPointer;
    logic                    readPointerZero;

    assign outData = mem[readPointer];
    assign outValid = ~empty;
    assign inReady = ~full;

    assign readPointerZero = (readPointer == 0);
    assign full = (readPointer == (Depth-1));
    assign write = (inValid && inReady);
    assign read = (outValid && outReady);

    always @(posedge clock) begin
      // specific coding style to infer SRL
      if (write) begin
        for (int i=0; i<(Depth-1); i++) begin
          mem[i+1] <= mem[i];
        end
        mem[0] <= inData;
      end
    end

    always @(posedge clock) begin
      empty <= (reset ? 1'b1 :
                (empty && write) ? 1'b0 :
                (readPointerZero && read && ~write) ? 1'b1 :
                empty);
      readPointer <= (reset ? '0 :
                      (write && ~read && ~full && ~empty) ? (readPointer+1) :
                      (~write && read && ~readPointerZero) ? (readPointer-1) :
                      readPointer);
      almostFull <= (reset ? 1'b0 : (readPointer >= AlmostFull));
      almostEmpty <= (reset ? 1'b1 : (readPointer <= AlmostEmpty));
    end

  end // if (UsingSrl)
  else if (UsingXpm) begin

    // we can't get in here without this being set, but we still need to skip during compilations
`ifdef OC_LIBRARY_ULTRASCALE_PLUS

    logic fullWrite, emptyRead, busyWrite, busyRead;

    xpm_fifo_sync #(
                    .FIFO_MEMORY_TYPE("bram"), // need to make this smarter (LUTRAM, URAM)
                    .READ_DATA_WIDTH(DataWidth),
                    .WRITE_DATA_WIDTH(DataWidth),
                    .FIFO_WRITE_DEPTH(Depth),
                    .READ_MODE("fwft"),
                    .FIFO_READ_LATENCY(0),  // needed given "fwft"
                    .PROG_EMPTY_THRESH(AlmostEmpty),
                    .PROG_FULL_THRESH(AlmostFull),
                    .RD_DATA_COUNT_WIDTH(1),
                    .WR_DATA_COUNT_WIDTH(1),
                    .FULL_RESET_VALUE(0),
                    .WAKEUP_TIME(0),
                    .DOUT_RESET_VALUE("0"),
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
          .empty(empty),
          .full(full),
          .injectdbiterr(1'b0),
          .injectsbiterr(1'b0),
          .overflow(),
          .prog_empty(almostEmpty),
          .prog_full(almostFull),
          .rd_data_count(),
          .rd_en(outReady),
          .rd_rst_busy(busyRead),
          .rst(reset),
          .sbiterr(),
          .sleep(1'b0),
          .underflow(),
          .wr_ack(),
          .wr_clk(clock),
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

    logic write;
    assign write = inValid && inReady;
    logic read;
    assign read = outValid && outReady;

    logic [AddressWidth:0] depth;
    logic [AddressWidth:0] depthNext;
    logic [AddressWidth-1:0] readPointer;
    logic [AddressWidth-1:0] readPointerNext;
    logic [AddressWidth-1:0] writePointer;
    logic [AddressWidth-1:0] writePointerNext;

    logic [DataWidth-1:0]    mem [Depth];

    assign depthNext = (depth + {'0,write} - {'0,read});
    assign writePointerNext = ((writePointer + {'0,write}) % Depth);
    assign readPointerNext = ((readPointer + {'0,read}) % Depth);

    always_ff @(posedge clock) begin
      if (reset) begin
        depth <= '0;
        readPointer <= '0;
        writePointer <= '0;
        inReady <= 1'b0;
        outValid <= 1'b0;
        almostFull <= 0;
        almostEmpty <= 1;
      end
      else begin
        depth <= depthNext;
        readPointer <= readPointerNext;
        writePointer <= writePointerNext;
        inReady <= (depthNext < Depth);
        outValid <= (depthNext > 0);
        almostFull <= (depthNext >= AlmostFull);
        almostEmpty <= (depthNext <= AlmostEmpty);
      end
    end

    always_ff @(posedge clock) begin
      if (write) begin
        mem[writePointer] <= inData;
      end
      outData <= ((write && ((depth==0) || (read && (depth==1)))) ? inData :
                  mem[readPointerNext]);
    end

  end // else: !if(UsingXpm)


`ifdef SIMULATION
  // during sims this will always be here, regardless of implementation above, so testbench/waves can always refer to it
  int simDepth;
  if (Depth == 0) begin
    initial simDepth = 0;
  end
  else begin
    always @(posedge clock) simDepth <= (reset ? '0: (simDepth + (inValid&&inReady) - (outValid&&outReady)));
  end
  `ifdef SIM_FIFO_DEPTH_REPORT
  int simMaxDepth;
  longint simTotalDepth;
  int simTotalSamples;
  always @(posedge clock) begin
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
