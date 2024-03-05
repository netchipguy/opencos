
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

  `define OC_ANNOUNCE_MODULE(m) $display("%t %m: ANNOUNCE module %-20s", $realtime, `OC_STRINGIFY(m));
  `define OC_ANNOUNCE_PARAM_INTEGER(p) $display("%t %m: ANNOUNCE param %-20s = %0d", $realtime, `OC_STRINGIFY(p), p);
  `define OC_ANNOUNCE_PARAM_BIT(p) $display("%t %m: ANNOUNCE param %-20s = %x", $realtime, `OC_STRINGIFY(p), p);
  `define OC_ANNOUNCE_PARAM_REAL(p) $display("%t %m: ANNOUNCE param %-20s = %.3f", $realtime, `OC_STRINGIFY(p), p);
  `define OC_ANNOUNCE_PARAM_REALTIME(p) $display("%t %m: ANNOUNCE param %-20s = %.3fns", $realtime, `OC_STRINGIFY(p), p/1ns);
  `define OC_ANNOUNCE_PARAM_MISC(p) $display("%t %m: ANNOUNCE param %-20s = %p", $realtime, `OC_STRINGIFY(p), p);

// *****************************************************************************************
// ******** ASSERTIONS
// *****************************************************************************************

// an assertion that is executed statically (i.e. outside always, initial, etc) and
// operates for simulation AND synthesis.  Good for checking params.

  `define OC_STATIC_ASSERT(a) \
  `ifdef SIMULATION \
  initial if (!(a)) begin $display("%t %m: (%s) NOT TRUE at %s:%0d", $realtime, `"a`", `__FILE__, `__LINE__); $finish; end \
  `else \
  if (!(a)) $fatal(1, "%m: (%s) NOT TRUE", `"a`"); \
  `endif

  `define OC_STATIC_ASSERT_STR(a,str) \
  `ifdef SIMULATION \
  initial if (!(a)) begin $display("%t %m: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); $finish; end \
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

  `define OC_ASSERT_EQUAL(a,b) \
  `ifdef SIMULATION \
  do if (!((a)===(b))) begin $display ("%t %m: MISMATCH %s (%x) !== %s (%x) at %s:%0d", $realtime, \
                                       `"a`", a, `"b`", b, `__FILE__, `__LINE__); $finish; end while (0) \
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
  do begin $display("%t %m: ERROR: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); $finish; end while (0) \
  `endif

  `define OC_WARNING(str) \
  `ifdef SIMULATION \
  do begin $display("%t %m: WARNING: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); end while (0) \
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
  $fatal(1, "%m: ERROR: %s", str); \
  `endif

  `define OC_STATIC_WARNING(str) \
  `ifdef SIMULATION \
  initial $warning("%t %m: WARNING: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); \
  final $warning("%t %m: WARNING: %s at %s:%0d", $realtime, str, `__FILE__, `__LINE__); \
  `else \
  $warning("%m: WARNING: %s", str); \
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
// ******** LOGIC WHEN SETTING DEFINES
// *****************************************************************************************

  `define OC_IFDEF_ANDIFDEF_DEFINE(a,b,o) \
  `ifdef a\
  `ifdef b\
    `define o\
  `endif\
  `endif

  `define OC_IFDEF_ORIFDEF_DEFINE(a,b,o) \
  `ifdef a\
    `define o\
  `endif\
  `ifdef b\
    `define o\
  `endif

  `define OC_IFDEF_ANDIFNDEF_DEFINE(a,b,o) \
  `ifdef a\
  `ifndef b\
    `define o\
  `endif\
  `endif

  `define OC_IFDEF_ORIFNDEF_DEFINE(a,b,o) \
  `ifdef a\
    `define o\
  `endif\
  `ifndef b\
    `define o\
  `endif

  `define OC_IFNDEF_ANDIFNDEF_DEFINE(a,b,o) \
  `ifndef a\
  `ifndef b\
    `define o\
  `endif\
  `endif

  `define OC_IFNDEF_ORIFNDEF_DEFINE(a,b,o) \
  `ifndef a\
    `define o\
  `endif\
  `ifndef b\
    `define o\
  `endif

  `define OC_IFDEF_ANDIFDEF_UNDEF(a,b,o) \
  `ifdef a\
  `ifdef b\
    `undef o\
  `endif\
  `endif

  `define OC_IFDEF_ORIFDEF_UNDEF(a,b,o) \
  `ifdef a\
    `undef o\
  `endif\
  `ifdef b\
    `undef o\
  `endif

// *****************************************************************************************
// ******** HELP GETTING VALUES FROM DEFINES
// *****************************************************************************************

  `define OC_VAL_ASDEFINED_ELSE(d,e) \
  `ifdef d\
    `d\
  `else\
    e\
  `endif

  `define OC_VAL_IFDEF_THEN_ELSE(d,t,e) \
  `ifdef d\
     t\
  `else\
     e\
  `endif

  `define OC_VAL_IFDEF(d) \
  `ifdef d\
     1'b1\
  `else\
     1'b0\
  `endif

// idea here is to return "true" (i.e. 1) if "d" is defined as nothing, or defined as 1. Basically
// if user does say +define+AXIM_MEM_TEST_ENABLE=0 then we don't want that to ENABLE something with that
  `define OC_VAL_ISTRUE(d) \
  `ifdef d\
  ((1```d == 1) || (1```d == 11)) \
  `else\
     1'b0\
  `endif

// *****************************************************************************************
// ******** HELP GETTING VALUES FROM TYPES
// *****************************************************************************************

// we use a macro to assist with this.  The right way is comparing via type() but at least
// Vivado prior to 2022.2 would not handle this correctly in synth when overridden, so we
// fall back to comparing $bits, but it's not robust (watch out comparing things with
// same amounts of bits!!!)
`ifdef OC_TOOL_BROKEN_TYPE_COMPARISON
  `define OC_TYPES_EQUAL(t1,t2) ($bits(t1)==$bits(t2))
  `define OC_TYPES_NOTEQUAL(t1,t2) ($bits(t1)!=$bits(t2))
`else
  `define OC_TYPES_EQUAL(t1,t2) (type(t1)==type(t2))
//  `define OC_TYPES_EQUAL(t1,t2) (t1==t2)
  `define OC_TYPES_NOTEQUAL(t1,t2) (type(t1)!=type(t2))
`endif

// *****************************************************************************************
// ******** CODE ASSISTANCE
// *****************************************************************************************

  `define OC_LOCALPARAM_SAFE(m) localparam integer m``Safe = (m ? m : 1)

  `define OC_CONCAT(a,b) a``b

  `define OC_CONCAT3(a,b,c) a``b``c

  `define OC_IFDEF_INCLUDE(d, i) \
  `ifdef d\
     i\
  `endif

// *****************************************************************************************
// ******** VENDOR RELATED
// *****************************************************************************************

// We really don't want to put too much in here, it's messy, but in some cases a library
// just doesn't work.  The first example is VIO (Xilinx debug IP) which has special hooks
// in the flow that grab signal names from the connected ports.  If we wrap this in an
// "oclib_debug_vio" wrapper (like we'd do for a RAM or synchronizer) then we'll just see
// the names of the nets inside "oclib_debug_vio" on our nice debug GUI.  So we could just
// embed Xilinx-specific code everywhere, or put it here in one place.

// That being said this should be moved into a "vendor defines" file.

  `define OC_DEBUG_VIO(inst, clock, i_width, o_width, i_signals, o_signals) \
  `ifdef OC_LIBRARY_ULTRASCALE_PLUS \
    `ifndef OC_LIBRARY_XILINX \
      `define OC_LIBRARY_XILINX \
    `endif \
  `endif \
  `undef OC_DEBUG_VIO_DONE_``inst \
  `ifdef OC_LIBRARY_XILINX \
    `ifndef SIMULATION \
       logic [i_width-1 : $bits({ i_signals }) ] inst``_dummy_i = '0; \
       logic [o_width-1 : $bits({ o_signals }) ] inst``_dummy_o; \
       xip_vio_i``i_width``_o``o_width`` inst (\
          .clk( clock ),\
          .probe_in0 ( { inst``_dummy_i , i_signals } ),\
          .probe_out0( { inst``_dummy_o , o_signals } ) );\
      `define OC_DEBUG_VIO_DONE_``inst \
    `endif \
  `endif \
  `ifndef OC_DEBUG_VIO_DONE_``inst \
       assign o_signals = '0; \
  `endif

  `define OC_DEBUG_ILA(inst, clock, depth, i_width, t_width, i_signals, t_signals) \
  `ifdef OC_LIBRARY_ULTRASCALE_PLUS \
    `ifndef OC_LIBRARY_XILINX \
      `define OC_LIBRARY_XILINX \
    `endif \
  `endif \
  `ifdef OC_LIBRARY_XILINX \
    `ifndef SIMULATION \
       logic [i_width-1 : $bits({ i_signals }) ] inst``_dummy_i = '0; \
       logic [t_width-1 : $bits({ t_signals }) ] inst``_dummy_t = '0; \
       xip_ila_d``depth``_i``i_width``_t``t_width inst (\
          .clk( clock ),\
          .probe0( { inst``_dummy_i , i_signals } ),\
          .probe1( { inst``_dummy_t , t_signals } ) );\
    `endif \
  `endif

`endif //  `ifndef __OCLIB_DEFINES_VH
