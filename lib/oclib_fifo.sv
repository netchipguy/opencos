
// SPDX-License-Identifier: MPL-2.0

module oclib_fifo #(parameter integer Width = 32,
                    parameter integer Depth = 32,
                    parameter integer AlmostFull = (Depth-8),
                    parameter bit BlockSimReporting = 0)
  (
   input                    clock,
   input                    reset,
   output logic             almostFull,
   input [Width-1:0]        inData,
   input                    inValid,
   output logic             inReady,
   output logic [Width-1:0] outData,
   output logic             outValid,
   input                    outReady
   );

  localparam integer AddressWidth = $clog2(Depth);

  if (Depth == 0) begin
    assign outData = inData;
    assign outValid = inValid;
    assign inReady = outReady;
  end
`ifndef OCLIB_FIFO_DISABLE_SRL
  else if (Depth <= 32) begin : impl

    // This should map efficiently into SRLs for 32-deep FIFOs
    logic [Width-1:0]        mem [Depth-1:0];
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
      almostFull <= (reset ? 1'b0 :
                     (readPointer >= AlmostFull));
    end

  end // if (Depth <= 32)
`endif
  else begin
`ifndef OCLIB_FIFO_DISABLE_BRAM

    logic full;
    logic empty;
    assign inReady = ~full;
    assign outValid = ~empty;

    xpm_fifo_sync #(
                    .DOUT_RESET_VALUE("0"),
                    .ECC_MODE("no_ecc"),
                    .FIFO_MEMORY_TYPE("bram"), // need to make this smarter (LUTRAM, URAM)
                    .FIFO_READ_LATENCY(0),  // needed 0 by "fwft" READ_MODE
                    .FIFO_WRITE_DEPTH(Depth),
                    .FULL_RESET_VALUE(0),
                    .PROG_EMPTY_THRESH(10),
                    .PROG_FULL_THRESH(AlmostFull),
                    .RD_DATA_COUNT_WIDTH(1),
                    .READ_DATA_WIDTH(Width),
                    .READ_MODE("fwft"), // first word fall through
                    .USE_ADV_FEATURES("0002"),
                    .WAKEUP_TIME(0),
                    .WR_DATA_COUNT_WIDTH(1),
                    .WRITE_DATA_WIDTH(Width)
                    )
    uXPM (
          .almost_empty(), // these only give one entry notice, we don't use them
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
          .prog_empty(),
          .prog_full(almostFull),
          .rd_data_count(),
          .rd_en(outReady),
          .rd_rst_busy(),
          .rst(reset),
          .sbiterr(),
          .sleep(1'b0),
          .underflow(),
          .wr_ack(),
          .wr_clk(clock),
          .wr_data_count(),
          .wr_en(inValid),
          .wr_rst_busy()
          );

    /*
      DECODER RING FOR USE_ADV_FEATURES PARAMETER (which is a string!?!)

12:  1'b0, // not using data_valid
     1'b0, // not using almost_empty
     1'b0, // not using rd_data_count
9:   1'b0, // using prog_empty
8:   1'b0, // not using underflow
7:   1'b0, // bit 7 : n/a
     1'b0, // bit 6 : n/a
     1'b0, // bit 5 : n/a
     1'b0, // not using wr_ack
     1'b0, // not using almost_full
     1'b0, // not using wr_data_count
1:   1'b1, // using prog_full
0:   1'b0  // not using overflow

     */

`else // !`ifndef OCLIB_FIFO_DISABLE_BRAM
    `OC_STATIC_ERROR("oclib_fifo currently only supports 32 deep!");
`endif // !`ifndef OCLIB_FIFO_DISABLE_BRAM
  end // else: !if(Depth <= 32)

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
  int simTotalDepth;
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
      $display("%t %m: Depth=%4d/%4d (Max=%4d, Avg=%4d)", $realtime, simDepth, Depth, simMaxDepth,
               (simTotalDepth / simTotalSamples));
    end
  end
  `endif // ifdef SIM_FIFO_DEPTH_REPORT
`endif // ifdef SIMULATION

endmodule // oclib_fifo
