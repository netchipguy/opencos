
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

  for (genvar p=0; p<PipeStages; p++) begin : pipe

    always_ff @(posedge clock) begin
      pipe_in[p] <= ((p==0) ? in : pipe_out[(p?p:1)-1]);
    end

    oclib_dummy_combo_stage #(.DatapathWidth(DatapathWidth),
                              .LogicLevels(LogicLevels),
                              .LutInputs(LutInputs),
                              .Seed(Seed+(123*p)))
    uCOMBO_STAGE (.in(pipe_in[p]), .out(pipe_out[p]));

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

  for (genvar level=0; level<LogicLevels; level++) begin : level
    assign level_in[level] = ((level == 0) ? in : level_out[(level?level:1)-1]);
    for (genvar b=0; b<DatapathWidth; b++) begin : lut
      logic [LutInputs-1:0] lut_in;
      for (genvar i=0; i<LutInputs; i++) begin
        // grab Inputs bits from level_in, swizzling them
        assign lut_in[i] = level_in[level][ (b + i + level) % DatapathWidth ];

        // level 1 bits 0 and 16, seed=1
        // bit 0:
        // lut_in[ 0] = level_in[1][ 0 + (0)]
        // lut_in[ 1] = level_in[1][ 0 + (1*2)]
        // bit 16:
        // lut_in[ 0] = level_in[1][ 16 + (0*2)]
        // lut_in[ 1] = level_in[1][ 16 + (1*2)]
      end
      oclib_dummy_logic_lut #(.Seed(Seed + level + b),
                              .Inputs(LutInputs) )
      uLUT (.in(lut_in), .out(level_out[level][b]));
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
