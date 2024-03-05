
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"

module oc_dummy
  #(
    parameter integer DatapathCount = 1,
    parameter integer DatapathWidth = 32,
    parameter integer DatapathLogicLevels = 8,
    parameter integer DatapathPipeStages = 8,
    parameter integer DatapathLutInputs = 4,
    parameter bit     UseClockDummy = oclib_pkg::False,
    parameter         type CsrType = oclib_pkg::csr_32_s,
    parameter         type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter         type CsrProtocol = oclib_pkg::csr_32_s,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input  clock,
   input  reset,
   input  clockDummy,
   input  resetDummy,
   input  CsrType csr,
   output CsrFbType csrFb
   );

  logic   resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  // Implement address space 0
  localparam integer NumCsr = 6 + DatapathCount; // 0 id, 1 control, 2-3 param, 4 chunk, 5 testChunks, 6-(DatapathCount+5) results
  localparam logic [31:0] CsrId = { oclib_pkg::CsrIdDummy,
                                    8'd0, 8'(DatapathCount) };
  logic [0:NumCsr-1] [31:0] csrOut;
  logic [0:NumCsr-1] [31:0] csrIn;

  oclib_csr_array
    #(.CsrType(CsrType), .CsrFbType(CsrFbType), .CsrProtocol(CsrProtocol),
      .NumCsr(NumCsr),
      .InputAsync(UseClockDummy), .OutputAsync(UseClockDummy),
      .CsrRwBits   ({ 32'h00000000, 32'h00000001, {3{32'h00000000}}, 32'hffffffff, {DatapathCount{32'h00000000}}  }),
      .CsrRoBits   ({ 32'h00000000, 32'h80000000, {3{32'hffffffff}}, 32'h00000000, {DatapathCount{32'hffffffff}}  }),
      .CsrFixedBits({ 32'hffffffff, 32'h00000000, {3{32'h00000000}}, 32'h00000000, {DatapathCount{32'h00000000}}  }),
      .CsrInitBits ({        CsrId, 32'h00000000, {3{32'h00000000}}, 32'h00000000, {DatapathCount{32'h00000000}}  }))
  uCSR (.clock(clock), .reset(resetSync), .clockCsrConfig(clockDummy),
        .csr(csr), .csrFb(csrFb),
        .csrRead(), .csrWrite(),
        .csrOut(csrOut), .csrIn(csrIn));

  logic                            go;
  assign go = csrOut[1][0];

  logic [31:0]                     testChunks;
  assign testChunks = csrOut[5];

  logic                            done;
  assign csrIn[1][31] = done;
  assign csrIn[2][31:16] = DatapathWidth;
  assign csrIn[2][15: 0] = DatapathPipeStages;
  assign csrIn[3][31:24] = DatapathLogicLevels;
  assign csrIn[3][23:20] = DatapathLutInputs;
  assign csrIn[3][19: 0] = '0;


  // Dummy clock domain


  // muxing to deal with sync and async cases together from here down

  logic                            clockMuxed;
  logic                            resetMuxed;
  if (UseClockDummy) begin
    assign clockMuxed = clockDummy;
    assign resetMuxed = resetDummy;
  end
  else begin
    assign clockMuxed = clock;
    assign resetMuxed = resetSync;
  end

  // the actual dummy logic

  logic [DatapathCount-1:0] [31:0] dummyIn;
  logic [DatapathCount-1:0] [31:0] dummyOut;
  oclib_dummy_logic #(.DatapathCount(DatapathCount),
                      .DatapathWidth(DatapathWidth),
                      .DatapathLogicLevels(DatapathLogicLevels),
                      .DatapathPipeStages(DatapathPipeStages),
                      .DatapathLutInputs(DatapathLutInputs),
                      .Seed(1) )
  uDUMMY (.clock(clockMuxed), .reset(resetMuxed),
          .in(dummyIn), .out(dummyOut));

  // a bank of counters, in dummy clock domain, timing the operation so it's repeatable
  // (i.e. without synchro uncertainty).  from here we send single bit signals through
  // generous number of pipeline stages to move to where the (potentially very large)
  // chunks of dummy logic spread to.

  logic [15:0]                     prescale;
  logic                            prescaleTC;
  logic [31:0]                     chunk;
  logic                            chunkTC;

  always_ff @(posedge clockMuxed) begin
    if (resetMuxed) begin
      prescale <= '0;
      prescaleTC <= 1'b0;
      chunk <= '0;
      chunkTC <= 1'b0;
      done <= 1'b0;
    end
    else begin
      prescale <= ((go && !done) ? (prescale + 'd1) : '0);
      prescaleTC <= (&prescale);
      chunk <= (go ? (chunk + prescaleTC) : '0);
      chunkTC <= (chunk == testChunks);
      done <= (done ? go : (chunkTC && prescaleTC));
    end
  end

  // pipelines going out to each of the DatapathCount pipelines

  logic [DatapathCount-1:0]        running;
  logic [DatapathCount-1:0]        summing;
  logic [DatapathCount-1:0]        holding;
  logic [DatapathCount-1:0] [31:0] dummySum;

  for (genvar i=0; i<DatapathCount; i++) begin

    // give run some pipeline to span large chunks of dummy logic.  we aim to pipeline a few
    // bits and then let the others move to where needed or have relaxed timing constraints
    oclib_pipeline #(.Width(1), .Length(5),
                     .DontTouch(oclib_pkg::True), .NoShiftRegister(oclib_pkg::True))
    uRUN_PIPE (.clock(clockMuxed), .in(go && !done), .out(running[i]));

    oclib_pipeline #(.Width(2), .Length(DatapathPipeStages),
                     .DontTouch(oclib_pkg::True), .NoShiftRegister(oclib_pkg::True))
    uSUM_PIPE (.clock(clockMuxed), .in({go, running[i]}), .out({holding[i], summing[i]}));

    // generate inputs for each pipline, sum outputs.  this logic should drift over to where
    // it's needed.  single bits going back and forth are pipelined.  dummySum needs to be
    // run back to the main registers, where it can be declared async to absolve timing concern
    always_ff @(posedge clockMuxed) begin
      dummyIn[i] <= (running[i] ? (dummyIn[i] + 'd1) : i);
      dummySum[i] <= (summing[i] ? (dummySum[i] + dummyOut[i]) :
                      holding[i] ? dummySum[i] :
                      '0);
    end

  end // for (genvar i=0; i<DatapathCount; i++)

  // horrible clock crossing violation.  every rule is made to be broken I guess. here's what to remember.
  // if you read it twice and get the same thing, it's fine.  otherwise, you can't trust much.  you CAN
  // however do some things -- i.e. polling and looking at one bit, say reporting progress in 1K chunks via
  // looking at 10th bit

  assign csrIn[4][31: 0] = chunk;

  // horrible clock crossing violation, this is non-trivial to sync,  we shouldn't look at it until
  // it's stable.

  for (genvar i=0; i<DatapathCount; i++) begin
    assign csrIn[6+i] = dummySum[i];
  end


endmodule // oc_dummy
