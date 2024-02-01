
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_async_serial_to_ready_valid
  #(
    parameter integer Width = 8,
    parameter integer SyncCycles = 3,
    parameter bit     ResetSync = oclib_pkg::False,
    parameter integer ResetPipeline = 0
    )
  (
   input                    clock,
   input                    reset,
   input [1:0]              inData,
   output logic             inAck,
   output logic [Width-1:0] outData,
   output logic             outValid,
   input                    outReady
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // synchronize the incoming async signals
  logic [1:0]               inDataSync;
  oclib_synchronizer #(.Width(2), .SyncCycles(SyncCycles))
  uIN_SYNC (.clock(clock), .in(inData), .out(inDataSync));

  localparam                CounterWidth = $clog2(Width);
  logic [CounterWidth-1:0]  counter;
  logic [1:0]               inDataQ;

  // detect incoming bits.  remember the protocol... toggling inData[0] means a 0 bit is being sent, and
  // toggling inData[1] means a 1 bit is being sent.  inAck == (^inData) means the inData bits has been
  // consumed.  We delay this ack to hold up the transmitting partner, which is what we do while waiting
  // for outReady
  logic                     inDataBit;
  logic                     inDataBitValid;
  assign inDataBitValid = (inAck != (^inDataSync)); // when our inData doesn't match inAck, inData has changed
  assign inDataBit = (inDataQ[1] ^ inDataSync[1]); // when inData[1] has changed we are getting a 1

  // outValid is really the one state bit for our 2-state machine (not counting the counter...)
  always_ff @(posedge clock) begin
    if (resetSync) begin
      outData <= '0;
      outValid <= 1'b0;
      counter <= '0;
      inAck <= (^inDataSync); // just in case we are reset when upstream isn't, we lock onto his current inData
    end
    else begin
      if (outValid) begin
        // we are showing output data
        if (outReady) begin
          // and it's being accepted
          outValid <= 1'b0;
          inAck <= (^inDataSync); // ack the input bit now that output is byte has been accepted
        end
      end
      else begin
        // we are not showing output data
        if (inDataBitValid) begin
          // we have a new data bit
          outData <= { inDataBit, outData[Width-1:1] };
          if (counter == (Width-1)) begin
            outValid <= 1'b1;
            counter <= '0;
          end
          else begin
            inAck <= (^inDataSync); // ack the input bit since we've loaded it into the output shift reg
            counter <= (counter + 'd1);
          end
        end
      end
    end // else: !if(resetSync)
    inDataQ <= inDataSync; // just pipeline, outside reset
  end // always_ff @ (posedge clock)

endmodule // oclib_async_serial_to_ready_valid
