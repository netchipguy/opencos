
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_dummy_logic
  #(
    parameter integer DatapathCount = 1,
    parameter integer DatapathWidth = 32,
    parameter integer DatapathLogicLevels = 8,
    parameter integer DatapathPipeStages = 8,
    parameter integer DatapathLutInputs = 4,
    parameter integer Seed = 1,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input                                                clock,
   input                                                reset,
   input [DatapathCount-1:0] [DatapathWidth-1:0]        in,
   output logic [DatapathCount-1:0] [DatapathWidth-1:0] out
   );

  logic   resetSync;
  oclib_module_reset #(.SyncCycles(SyncCycles), .ResetSync(ResetSync), .ResetPipeline(ResetPipeline))
  uRESET (.clock(clock), .in(reset), .out(resetSync));

  for (genvar d=0; d<DatapathCount; d++) begin : dp

    oclib_dummy_pipeline #(.DatapathWidth(DatapathWidth),
                           .LogicLevels(DatapathLogicLevels),
                           .PipeStages(DatapathPipeStages),
                           .LutInputs(DatapathLutInputs),
                           .Seed(Seed+(13245*d)) )
    uPIPELINE (.clock(clock), .in(in[d]), .out(out[d]));

  end

endmodule // oclib_dummy_logic

module oclib_dummy_pipeline
  #(
    parameter integer DatapathWidth = 32,
    parameter integer LogicLevels = 8,
    parameter integer PipeStages = 8,
    parameter integer LutInputs = 4,
    parameter integer Seed = 1
    )
  (
   input                            clock,
   input [DatapathWidth-1:0]        in,
   output logic [DatapathWidth-1:0] out
   );

  logic [DatapathWidth-1:0]         pipe_in [PipeStages];
  logic [DatapathWidth-1:0]         pipe_out [PipeStages];

  for (genvar s=0; s<PipeStages; s++) begin : stage

    always_ff @(posedge clock) begin
      pipe_in[s] <= ((s==0) ? in : pipe_out[(s?s:1)-1]);
    end

    oclib_dummy_combo_stage #(.DatapathWidth(DatapathWidth),
                              .LogicLevels(LogicLevels),
                              .LutInputs(LutInputs),
                              .Seed(Seed+(123*s)))
    uCOMBO_STAGE (.in(pipe_in[s]), .out(pipe_out[s]));

  end

  always_ff @(posedge clock) begin
    out <= pipe_out[PipeStages-1];
  end

endmodule // oclib_dummy_pipeline


module oclib_dummy_combo_stage
  #(
    parameter integer DatapathWidth = 32,
    parameter integer LogicLevels = 8,
    parameter integer LutInputs = 4,
    parameter integer Seed = 1
    )
  (
   input [DatapathWidth-1:0] in,
   output logic [DatapathWidth-1:0] out
   );

  logic [DatapathWidth-1:0]         level_in [LogicLevels];
  logic [DatapathWidth-1:0]         level_out [LogicLevels];

  for (genvar l=0; l<LogicLevels; l++) begin : level
    assign level_in[l] = ((l == 0) ? in : level_out[(l?l:1)-1]);
    for (genvar b=0; b<DatapathWidth; b++) begin : lut
      logic [LutInputs-1:0] lut_in;
      for (genvar i=0; i<LutInputs; i++) begin
        // grab Inputs bits from level_in, swizzling them
        assign lut_in[i] = level_in[l][ (b + i + l) % DatapathWidth ];
      end
      oclib_dummy_logic_lut #(.Seed(Seed + l + b),
                              .Inputs(LutInputs) )
      uLUT (.in(lut_in), .out(level_out[l][b]));
    end
  end

  assign out = level_out[LogicLevels-1];

endmodule // oclib_dummy_combo_stage


module oclib_dummy_logic_lut
  #(
    parameter integer Inputs = 4,
    parameter integer Seed = 1
    )
  (
   input [Inputs-1:0] in,
   output logic out
   );

  assign out = (^(in+Seed));

endmodule // oclib_dummy_logic_lut
