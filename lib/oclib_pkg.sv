
`ifndef __OCLIB_PKG
  `define __OCLIB_PKG

package oclib_pkg;

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
  // BYTE CHANNEL protocol
  // ***********************************************************************************************

  // This protocol encapsulates the task of sending a byte stream.

  // Master puts DATA on bus, asserts REQ
  // Slave raises ACK (doesn't sample data yet!)
  // Master sees ACK, de-asserts REQ
  // Slave sees REQ de-assert, samples data, de-asserts ACK
  // Master sees ACK de-assert, and knows (a) slave got the data, (b) it can start a new transaction

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



endpackage

`endif //__OCLIB_PKG
