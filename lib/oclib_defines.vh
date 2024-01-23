
// SPDX-License-Identifier: MPL-2.0

`ifndef __OCLIB_DEFINES_VH
  `define __OCLIB_DEFINES_VH

// *****************************************************************************************
// ******** UTILITY
// *****************************************************************************************

// convert a token into a string, useful for building macros that quote their arguments
  `define OC_STRINGIFY(x) `"x`"

// concat two tokens, useful for building module/signal/struct names
  `define OC_CONCAT(a,b) a``b
  `define OC_CONCAT3(a,b,c) a``b``c
  `define OC_CONCAT4(a,b,c,d) a``b``c``d

// *****************************************************************************************
// ******** SELF DOCUMENTATION
// *****************************************************************************************

  `define OC_ANNOUNCE_MODULE(m) $display("%m: ANNOUNCE module %-20s", `OC_STRINGIFY(m));
  `define OC_ANNOUNCE_PARAM_INTEGER(p) $display("%m: ANNOUNCE param %-20s = %0d", `OC_STRINGIFY(p), p);
  `define OC_ANNOUNCE_PARAM_BIT(p) $display("%m: ANNOUNCE param %-20s = %x", `OC_STRINGIFY(p), p);
  `define OC_ANNOUNCE_PARAM_REAL(p) $display("%m: ANNOUNCE param %-20s = %.3f", `OC_STRINGIFY(p), p);

// *****************************************************************************************
// ******** ASSERTIONS
// *****************************************************************************************

// an assertion that is executed statically (i.e. outside always, initial, etc) and
// operates for simulation AND synthesis.  Good for checking params.

  `define OC_STATIC_ASSERT(a) \
  `ifdef SIMULATION \
  initial if (!(a)) begin $display("%t %m: (%s) NOT TRUE at %s:%0d", $realtime, `"a`", `__FILE__, `__LINE__); #0; $finish; end \
  `else \
  if (!(a)) $fatal(1, "%m: (%s) NOT TRUE", `"a`"); \
  `endif

  `define OC_STATIC_ASSERT_STR(a,str) \
  `ifdef SIMULATION \
  initial if (!(a)) begin $display("%t %m: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); #0; $finish; end \
  `else \
  if (!(a)) $fatal(1, "%m: %s", str); \
  `endif

// an assertion that is executed within an initial, always, task, function, or final block
// and operates for simulation ONLY

  `define OC_ASSERT(a) \
  `ifdef SIMULATION \
  do if (!(a)) begin $display ("%t %m: (%s) NOT TRUE at %s:%0d", $realtime, `"a`", `__FILE__, `__LINE__); $finish; end while (0) \
  `endif

  `define OC_ASSERT_STR(a,str) \
  `ifdef SIMULATION \
  do if (!(a)) begin $display("%t %m: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); $finish; end while (0) \
  `endif

  `define OC_ASSERT_EXPECTED(v,e) \
  `ifdef SIMULATION \
  do if (v!==e) begin $display ("%t %m: %s was %x when expecting %x at %s:%0d", $realtime, \
                                `"v`", v, e, `__FILE__, `__LINE__); $finish; end while (0) \
  `endif

// an assertion that partially implements an error register (without clock / reset, i.e. within !reset part of always_ff block)

  `define OC_ASSERT_REG(a,ereg) \
  if (!(a)) ereg <= 1'b1; \
  `ifdef SIMULATION \
  do if (!(a)) begin $display("%t %m: (%s) NOT TRUE at %s:%0d", $realtime, `"a`", `__FILE__, `__LINE__); $finish; end while (0) \
  `endif

  `define OC_ASSERT_REG_STR(a,ereg,str) \
  if (!(a)) ereg <= 1'b1; \
  `ifdef SIMULATION \
  do if (!(a)) begin $display("%t %m: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); $finish; end while (0) \
  `endif

// an assertion that brings it's own clock and reset and operates for simulation ONLY

  `define OC_SYNC_ASSERT(clock,reset,a) \
  `ifdef SIMULATION \
  always @(posedge clock) if (!(reset)) begin \
    if (!(a)) begin $display("%t %m: (%s) NOT TRUE at %s:%0d", $realtime, `"a`", `__FILE__, `__LINE__); $finish; end \
  end \
  `endif

  `define OC_SYNC_ASSERT_STR(clock,reset,a,str) \
  `ifdef SIMULATION \
  always @(posedge clock) if (!(reset)) begin \
    if (!(a)) begin $display("%t %m: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); $finish; end \
  end \
  `endif

// an assertion that brings it's own clock and reset and fully implements an error register

  `define OC_SYNC_ASSERT_REG(clock,reset,a,ereg) \
  always_ff @(posedge clock) \
    if (reset) ereg <= 1'b0 \
    else begin \
      if (!(a)) begin \
        ereg <= 1'b1; \
  `ifdef SIMULATION \
        $display("%t %m: (%s) NOT TRUE at %s:%0d", $realtime, `"a`", `__FILE__, `__LINE__); $finish; end \
  `endif \
      end \
    end \
  end

  `define OC_SYNC_ASSERT_REG_STR(clock,reset,a,ereg,str) \
  always_ff @(posedge clock) \
    if (reset) ereg <= 1'b0 \
    else begin \
      if (!(a)) begin \
        ereg <= 1'b1; \
  `ifdef SIMULATION \
        $display("%t %m: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); $finish; end \
  `endif \
      end \
    end \
  end

// *****************************************************************************************
// ******** WARNING / ERROR
// *****************************************************************************************
// These tasks handle:
// - printing file and line number
// - safe in any environment (no wrapping `ifdef SIMULATION etc)
// - try to do the logival thing in all environment (printing all errors at time 0 before
//     stopping simulation, printing a formatted error message in synth, etc)

// ERROR / WARNING - operate within begin/end with other procedural code.
//                 - print immediately to remain near other code that maybe printing.
//                 - removed for elab/synth (ifdef'd out) since they run at a certain "time"

  `define OC_ERROR(str) \
  `ifdef SIMULATION \
  do $display("%t %m: ERROR: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); $finish; while (0) \
  `endif

  `define OC_WARNING(str) \
  `ifdef SIMULATION \
  do $display("%t %m: WARNING: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); while (0) \
  `endif

// STATIC_ERROR / STATIC_WARNING - operate outside begin/end blocks, i.e. "instantiated"
//                               - good for dropping in an "else" clause of a generate that can't handle the inputs
//                                 (this is for "you shouldn't get here", use OC_STATIC_ASSERT for "is this condition true?")
//                               - work in all environments: sim, elab, synth
//                               - errors, in sim, wait 0 time so all errors can be printed, then finish sim
//                               - warnings, in sim, print at beginning and end of sim
//                               - in elab/synth, both print as code is elaborated

  `define OC_STATIC_ERROR(str) \
  `ifdef SIMULATION \
  initial $fatal(1, "%t %m: ERROR: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); \
  `else \
  $fatal(1, "%m: ERROR: %s at %s:%0d", str, `__FILE__, `__LINE__); \
  `endif

  `define OC_STATIC_WARNING(str) \
  `ifdef SIMULATION \
  initial $warning(1, "%t %m: WARNING: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); \
  final $warning(1, "%t %m: WARNING: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); \
  `else \
  $warning(1, "%m: WARNING: %s at %s:%0d", str, `__FILE__, `__LINE__); \
  `endif

// *****************************************************************************************
// ******** HELP SETTING DEFINES
// *****************************************************************************************

  // ideal naming for these defines is that each word after OC_ corresponds to an argument,
  // appearing in order.

  `define OC_IFDEFUNDEF(d) \
  `ifdef d\
    `undef d\
  `endif

  `define OC_IFDEFDEFINE_TO(d,v) \
  `ifdef d\
    `undef d\
    `define d v\
  `endif

  `define OC_IFNDEFDEFINE_TO(d,v) \
  `ifndef d\
    `define d v\
  `endif

  `define OC_IFDEF_DEFINE(i,d) \
  `ifdef i\
    `define d\
  `endif

  `define OC_IFNDEF_DEFINE(i,d) \
  `ifndef i\
    `define d\
  `endif

  `define OC_IFDEF_DEFINE_TO(i,d,v) \
  `ifdef i \
    `define d v\
  `endif

  `define OC_IFNDEF_DEFINE_TO(i,d,v) \
  `ifndef i\
    `define d v\
  `endif

  `define OC_IFDEF_DEFINE_TO_ELSE(i,d,a,b) \
  `ifdef i\
    `define d a\
  `else\
    `define d b\
  `endif

// *****************************************************************************************
// ******** HELP SETTING VALUES FROM DEFINES
// *****************************************************************************************

  `define OC_VAL_ASDEFINED_ELSE(d,e) \
  `ifdef d \
    `d \
  `else \
    e \
  `endif

  `define OC_VAL_IFDEF_THEN_ELSE(d,t,e) \
  `ifdef d \
     t \
  `else \
     e \
  `endif

  `define OC_VAL_IFDEF(d) \
  `ifdef d \
     1'b1 \
  `else \
     1'b0 \
  `endif

// *****************************************************************************************
// ******** CODE ASSISTANCE
// *****************************************************************************************

  `define OC_CREATE_SAFE_WIDTH(m) localparam integer m``Safe = (m ? m : 1)

  `define OC_RAND_PERCENT(p) ((({$random}%100) < p) ? 1'b1 : 1'b0)

`endif //  `ifndef __OCLIB_DEFINES_VH
