
// SPDX-License-Identifier: MPL-2.0

`ifndef __OCLIB_PKG
  `define __OCLIB_PKG

`include "lib/oclib_defines.vh"

package oclib_pkg;

  localparam bit True = 1;
  localparam bit False = 0;

  localparam byte ResetChar = "~";
  localparam byte SyncChar = "|";

  localparam integer DefaultCsrAlignment = 4;

  function logic [7:0] HexToAsciiNibble (input [3:0] hex);
    if (hex > 'd9) return "a" + (hex - 'd10);
    else return "0" + hex;
  endfunction

  function logic [3:0] AsciiToHexNibble (input [7:0] ascii);
    if ((ascii >= "0") && (ascii <= "9")) return (ascii - "0");
    if ((ascii >= "a") && (ascii <= "f")) return (ascii - "a" + 10);
    if ((ascii >= "A") && (ascii <= "F")) return (ascii - "A" + 10);
    `OC_ERROR($sformatf("Cannot convert ASCII 0x%02x to hex nibble", ascii));
  endfunction


  // ***********************************************************************************************
  // TOP INFO bus
  // ***********************************************************************************************

  typedef struct packed {
    logic        tick1us; // currently pulses for 5 clockTop but maybe should be stretched or toggle?
    logic        tick1ms;
    logic        tick1s;
    logic        halt;
    logic        error;
    logic        clear;
    logic [7:0]  unlocked; // support for unlocking 8 separate functions
    logic        thermalError;
    logic        thermalWarning;
  } chip_status_s;

  typedef struct packed {
    logic        interrupt;
    logic        halt;
    logic        error;
  } chip_status_fb_s;

  typedef struct packed {
    logic        error;
    logic        done;
  } user_status_s;

  // ***********************************************************************************************
  // BYTE CHANNEL protocols
  // ***********************************************************************************************

  // This protocol encapsulates the task of sending a byte stream.

  // 8-bit synchronous byte channel with ready/valid semantics
  // this is generally the default that is assumed, esp interfacing with other blocks.  The async
  // versions are really for transport of the byte stream between blocks, chips, etc.

  typedef struct packed {
    logic [7:0]  data;
    logic        valid;
    logic        ready;
  } bc_8b_bidi_s;

  typedef struct packed {
    logic [7:0]  data;
    logic        valid;
  } bc_8b_s;

  typedef struct packed {
    logic        ready;
  } bc_8b_fb_s;

  // 8-bit asynchronous byte channel with req/ack semantics

  // Source puts DATA on bus, asserts REQ
  // Sink raises ACK (doesn't sample data yet!)
  // Source sees ACK, de-asserts REQ
  // Sink sees REQ de-assert, samples data, de-asserts ACK
  // Source sees ACK de-assert, and knows (a) slave got the data, (b) it can start a new transaction

  typedef struct packed {
    logic [7:0]  data;
    logic        req;
    logic        ack;
  } bc_async_8b_bidi_s;

  typedef struct packed {
    logic [7:0]  data;
    logic        req;
  } bc_async_8b_s;

  typedef struct packed {
    logic        ack;
  } bc_async_8b_fb_s;

  // Serial asynchronous byte channel

  // Source toggles data0 or data1 to indicate a bit being transferred
  // Sink acks with XOR of data0 and data1, so it will flip polarity when either is transmitted,
  // and doesn't require state (i.e. if ack == (data0^data1) then we are ready to send data).

  typedef struct packed {
    logic [1:0]  data;
    logic        ack;
  } bc_async_1b_bidi_s;

  typedef struct packed {
    logic [1:0]  data;
  } bc_async_1b_s;

  typedef struct packed {
    logic        ack;
  } bc_async_1b_fb_s;

  // ***********************************************************************************************
  // CSR protocols
  // ***********************************************************************************************

  localparam [15:0] CsrIdPll = 'd1;
  localparam [15:0] CsrIdChipmon = 'd2;
  localparam [15:0] CsrIdProtect = 'd3;
  localparam [15:0] CsrIdHbm = 'd4;
  localparam [15:0] CsrIdIic = 'd5;
  localparam [15:0] CsrIdLed = 'd6;
  localparam [15:0] CsrIdGpio = 'd7;
  localparam [15:0] CsrIdFan = 'd8;
  localparam [15:0] CsrIdCmac = 'd9;
  localparam [15:0] CsrIdPcie = 'd10;

  localparam [31:0] BcBlockIdAny = 32'hffff_ffff;
  localparam [31:0] BcBlockIdUser = 32'h8000_0000;

  localparam [3:0] BcSpaceIdAny = 4'hf;

  // SIMPLE PARALLEL CSR PROTOCOL

  typedef struct   packed {
    logic [31:0] toblock;
    logic [31:0] fromblock;
    logic [5:0]  reserved;
    logic        write;
    logic        read;
    logic [3:0]  space;
    logic [3:0]  id;
    logic [31:0] address;
    logic [31:0] wdata;
  } csr_32_noc_s;

  typedef struct packed {
    logic [31:0] toblock;
    logic [31:0] fromblock;
    logic [5:0]  reserved;
    logic        error;
    logic        ready;
    logic [31:0] rdata;
  } csr_32_noc_fb_s;

  typedef struct   packed {
    logic [31:0] toblock;
    logic [5:0]  reserved;
    logic        write;
    logic        read;
    logic [3:0]  space;
    logic [3:0]  id;
    logic [31:0] address;
    logic [31:0] wdata;
  } csr_32_tree_s;

  typedef struct packed {
    logic [5:0]  reserved;
    logic        error;
    logic        ready;
    logic [31:0] rdata;
  } csr_32_tree_fb_s;

 typedef struct packed {
    logic [5:0]  reserved;
    logic        write;
    logic        read;
    logic [3:0]  space;
    logic [3:0]  id;
    logic [31:0] address;
    logic [31:0] wdata;
  } csr_32_s;

  typedef struct packed {
    logic [5:0]  reserved;
    logic        error;
    logic        ready;
    logic [31:0] rdata;
  } csr_32_fb_s;

  typedef struct packed {
    logic [5:0]  reserved;
    logic        write;
    logic        read;
    logic [3:0]  space;
    logic [3:0]  id;
    logic [63:0] address;
    logic [63:0] wdata;
  } csr_64_s;

  typedef struct packed {
    logic [5:0]  reserved;
    logic        error;
    logic        ready;
    logic [63:0] rdata;
  } csr_64_fb_s;

  // DRP PROTOCOL (XILINX IP)

  typedef struct packed {
    logic        enable;
    logic [15:0] address;
    logic        write;
    logic [15:0] wdata;
  } drp_s;

  typedef struct packed {
    logic [15:0] rdata;
    logic        ready;
  } drp_fb_s;

  // APB PROTOCOL (AXI PERIPHERAL BUS)

  typedef struct packed {
    logic        select;
    logic        enable;
    logic [31:0] address;
    logic        write;
    logic [31:0] wdata;
  } apb_s;

 typedef struct packed {
    logic [31:0] rdata;
    logic        ready;
    logic        error;
  } apb_fb_s;

  // AXI-LITE 32-BIT PROTOCOL

  typedef struct packed {
    logic [31:0] awaddr;
    logic        awvalid;
    logic [31:0] araddr;
    logic        arvalid;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        rready;
    logic        bready;
  } axil_32_s;

  typedef struct packed {
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        awready;
    logic        arready;
    logic        wready;
  } axil_32_fb_s;

  // ***********************************************************************************************
  // AXI3 PROTOCOL (currently used for HBM interfaces, which need to migrate to AXI4 below...)
  // ***********************************************************************************************

  localparam Axi3IdWidth = 6;
  localparam Axi3AddressWidth = 33;
  localparam Axi3DataWidth = 256;
  localparam Axi3DataBytes = (Axi3DataWidth/8);

  typedef struct packed {
    logic [Axi3AddressWidth-1:0] addr;
    logic [Axi3IdWidth-1:0]      id;
    logic [1:0]                  burst;
    logic [2:0]                  size;
    logic [3:0]                  len;
  } axi3_a_s;

  typedef struct packed {
    logic [Axi3DataBytes-1:0] [7:0] data;
    logic [Axi3DataBytes-1:0]       strb;
    logic                           last;
  } axi3_w_s;

  typedef struct packed {
    logic [Axi3IdWidth-1:0]         id;
    logic [Axi3DataBytes-1:0] [7:0] data;
    logic [1:0]                     resp;
    logic                           last;
  } axi3_r_s;

  typedef struct packed {
    logic [Axi3IdWidth-1:0] id;
    logic [1:0]             resp;
  } axi3_b_s;

  typedef struct packed {
    axi3_a_s aw;
    logic    awvalid;
    axi3_a_s ar;
    logic    arvalid;
    axi3_w_s w;
    logic    wvalid;
    logic    rready;
    logic    bready;
  } axi3_s;

  typedef struct packed {
    axi3_r_s r;
    logic    rvalid;
    axi3_b_s b;
    logic    bvalid;
    logic    awready;
    logic    arready;
    logic    wready;
  } axi3_fb_s;

  // ***********************************************************************************************
  // AXI4-MEMORY MAPPED PROTOCOL (typically used for Memory Interfaces)
  // ***********************************************************************************************

`define OC_LOCAL_AXI4MM_UNROLL(width) \
 \
  localparam Axi4M``width``IdWidth = 6; /* i.e. Axi4M256IdWidth */ \
  localparam Axi4M``width``AddressWidth = 64; /* i.e. Axi4M256AddressWidth */ \
  localparam Axi4M``width``DataBytes = (width / 8); /* i.e. Axi4M256DataBytes */ \
 \
  typedef struct packed { \
    logic [Axi4M``width``AddressWidth-1:0]    addr; \
    logic [Axi4M``width``IdWidth-1:0]         id; \
    logic [1:0]                               burst; \
    logic [2:0]                               prot; \
    logic [2:0]                               size; \
    logic [7:0]                               len; \
    logic                                     lock; \
    logic [3:0]                               cache; \
  } axi4m_``width``_a_s; \
 \
  typedef struct packed { \
    logic [Axi4M``width``DataBytes-1:0] [7:0] data; \
    logic [Axi4M``width``DataBytes-1:0]       strb; \
    logic                                     last; \
  } axi4m_``width``_w_s; \
 \
  typedef struct packed { \
    logic [Axi4M``width``IdWidth-1:0]         id; \
    logic [Axi4M``width``DataBytes-1:0] [7:0] data; \
    logic [1:0]                               resp; \
    logic                                     last; \
  } axi4m_``width``_r_s; \
 \
  typedef struct packed { \
    logic [Axi4M``width``IdWidth-1:0]         id; \
    logic [1:0]                               resp; \
  } axi4m_``width``_b_s; \
 \
  typedef struct packed { \
    axi4m_``width``_a_s                       aw; \
    logic                                     awvalid; \
    axi4m_``width``_a_s                       ar; \
    logic                                     arvalid; \
    axi4m_``width``_w_s                       w; \
    logic                                     wvalid; \
    logic                                     rready; \
    logic                                     bready; \
  } axi4m_``width``_s; \
 \
  typedef struct packed { \
    axi4m_``width``_r_s                       r; \
    logic                                     rvalid; \
    axi4m_``width``_b_s                       b; \
    logic                                     bvalid; \
    logic                                     awready; \
    logic                                     arready; \
    logic                                     wready; \
  } axi4m_``width``_fb_s;

  `OC_LOCAL_AXI4MM_UNROLL(32)
  `OC_LOCAL_AXI4MM_UNROLL(64)
  `OC_LOCAL_AXI4MM_UNROLL(128)
  `OC_LOCAL_AXI4MM_UNROLL(256)
  `OC_LOCAL_AXI4MM_UNROLL(512)
  `undef OC_LOCAL_AXI4MM_UNROLL


  // ***********************************************************************************************
  // AXI4-STREAM PROTOCOL (Ethernet MAC, etc)
  // ***********************************************************************************************

  // the "reset" signals could use some explanation.  Since AXI4ST is often used for MACs, which like
  // to signal reset when the link is down, we carry this in the AXI bus.  RX side will drive the
  // reset in parallel with the data, TX side will drive reset "backwards" to user on the _fb channel.

 `define OC_LOCAL_AXI4ST_UNROLL(width) \
 \
  localparam Axi4St``width``DataBytes = (width / 8); /* i.e. Axi4St512DataBytes */ \
 \
  typedef struct packed { \
    logic                                     tvalid; \
    logic [Axi4M``width``DataBytes-1:0] [7:0] tdata; \
    logic                                     tlast; \
    logic [Axi4M``width``DataBytes-1:0]       tkeep; \
    logic                                     tuser; \
    logic                                     reset; \
   } axi4st_``width``_s; \
\
  typedef struct packed { \
    logic         tready; \
    logic         reset; \
  } axi4st_``width``_fb_s;

  `OC_LOCAL_AXI4ST_UNROLL(32)
  `OC_LOCAL_AXI4ST_UNROLL(64)
  `OC_LOCAL_AXI4ST_UNROLL(128)
  `OC_LOCAL_AXI4ST_UNROLL(256)
  `OC_LOCAL_AXI4ST_UNROLL(512)
  `undef OC_LOCAL_AXI4ST_UNROLL

endpackage // oclib_pkg

`endif //__OCLIB_PKG
