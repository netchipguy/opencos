
// SPDX-License-Identifier: MPL-2.0

`ifndef __OCLIB_PKG
`define __OCLIB_PKG

package oclib_pkg;

  localparam bit True = 1;
  localparam bit False = 0;

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
  } chip_status_s;

  typedef struct packed {
    logic        interrupt;
    logic        halt;
    logic        error;
  } chip_status_fb_s;

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

  parameter CsrCommandW = 4;
  parameter CsrSpaceW = 4;
  parameter CsrBlockW = 32;
  parameter CsrAddressW = 32;
  parameter CsrDataW = 32;
  parameter CsrStatusW = 8;

  parameter CsrCommandRead = 4'h1;
  parameter CsrCommandWrite = 4'h2;
  parameter CsrCommandStatus = 4'he;
  parameter CsrCommandClear = 4'hf;

  typedef struct packed {
    logic        write;
    logic        read;
    logic [CsrAddressW-1:0] block;
    logic [CsrAddressW-1:0] address;
    logic [CsrDataW-1:0]    wdata;
  } csr_s;

  typedef struct packed {
    logic [CsrDataW-1:0] rdata;
    logic                ready;
    logic                error;
  } csr_fb_s;


endpackage

`endif //__OCLIB_PKG
