
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"

module oclib_csr_array
  #(
    parameter integer                      DataW = 32,
    parameter integer                      NumCsr = 8,
    parameter integer                      CsrAlignment = oclib_pkg::DefaultCsrAlignment,
    parameter                              type CsrType = oclib_pkg::csr_32_s,
    parameter                              type CsrFbType = oclib_pkg::csr_32_fb_s,
    parameter                              type CsrProtocol = oclib_pkg::csr_32_s,
    parameter integer                      SyncCycles = 3,
    parameter bit                          ResetSync = oclib_pkg::False,
    parameter integer                      ResetPipeline = 0,

    // These bits allow setting the default for all CSRs, which can be tuned per-CSR below
    parameter bit                          InputAsync = oclib_pkg::False,
    parameter bit                          OutputAsync = oclib_pkg::False,
    parameter integer                      InputFlops = 0,
    parameter integer                      OutputFlops = 0,

    // From here down we are configuring per-CSR operation
    parameter bit [0:NumCsr-1] [DataW-1:0] CsrFixedBits = '0, // set are 1 in csrOut and readData
    parameter bit [0:NumCsr-1] [DataW-1:0] CsrInitBits = '0, // reset to 1 in csrOut (should also be CsrRw or CsrFixed)
    parameter bit [0:NumCsr-1] [DataW-1:0] CsrRwBits = '0, // writable and appear in readData
    parameter bit [0:NumCsr-1] [DataW-1:0] CsrRoBits = '0, // read-only, readData from csrIn
    parameter bit [0:NumCsr-1] [DataW-1:0] CsrWoBits = '0, // write-only, go to csrOut but not readData

    // The following per-CSR config is about synch/pipelining per CSR, defaulting to global setting above
    parameter integer                      CsrStatusInputFlops [0:NumCsr-1] = '{ NumCsr { InputFlops }},
    parameter integer                      CsrConfigOutputFlops [0:NumCsr-1] = '{ NumCsr { OutputFlops }},
    parameter bit [0:NumCsr-1]             CsrStatusInputAsync = { NumCsr { InputAsync }},
    parameter bit [0:NumCsr-1]             CsrConfigOutputAsync = { NumCsr { OutputAsync }} // requires clockAsync
    )
  (
   input                                 clock,
   input                                 reset,
   input                                 csrSelect = 1'b1,
   input                                 CsrType csr,
   output                                CsrFbType csrFb,
   output logic [0:NumCsr-1] [DataW-1:0] csrOut,
   input [0:NumCsr-1] [DataW-1:0]        csrIn,
   output logic [0:NumCsr-1]             csrRead,
   output logic [0:NumCsr-1]             csrWrite,
   input                                 clockCsrConfig = 1'b0
   );

  // synchronize/pipeline reset as needed
  logic          resetSync;
  oclib_module_reset #(.ResetSync(ResetSync), .SyncCycles(SyncCycles), .ResetPipeline(ResetPipeline),
                       .NoShiftRegister(oclib_pkg::True))
  uRESET_SYNC (.clock(clock), .in(reset), .out(resetSync));

  // convert incoming CSR array if necessary
  oclib_pkg::csr_32_s csrNormal;
  oclib_pkg::csr_32_fb_s csrNormalFb;

  if (type(CsrType) != type(oclib_pkg::csr_32_s)) begin

    oclib_csr_adapter #(.CsrInType(CsrType), .CsrInFbType(CsrFbType), .CsrInProtocol(CsrProtocol),
                        .CsrOutType(oclib_pkg::csr_32_s), .CsrOutFbType(oclib_pkg::csr_32_fb_s))
    uCSR_ADAPTER (.clock(clock), .reset(resetSync),
                  .in(csr), .inFb(csrFb),
                  .out(csrNormal), .outFb(csrNormalFb));
  end
  else begin
    assign csrNormal = csr;
    assign csrFb = csrNormalFb;
  end

  localparam integer                     CsrAddressShift = $clog2(CsrAlignment);
  localparam integer                     LocalCsrAddressWidth = $bits(csrNormal.address) - CsrAddressShift;

  // synch then pipe the incoming csrIn, as per CsrStatusInputAsync and CsrStatusInputFlops
  logic [0:NumCsr-1] [DataW-1:0]         csrStatusSync;
  logic [0:NumCsr-1] [DataW-1:0]         csrStatusInternal;

  for (genvar i=0; i<NumCsr; i++) begin : status_pipe

    oclib_synchronizer #(.Width(DataW), .Enable(CsrStatusInputAsync[i]))
    uSYNC (.clock(clock), .in(csrIn[i]), .out(csrStatusSync[i]));

    oclib_pipeline #(.Width(DataW), .Length(CsrStatusInputFlops[i]), .NoShiftRegister(oclib_pkg::True))
    uPIPE (.clock(clock), .in(csrStatusSync[i]), .out(csrStatusInternal[i]));

  end

  // pipe then synch the outgoing csrOut, as per CsrConfigOutputAsync and CsrConfigOutputFlops
  logic [0:NumCsr-1] [DataW-1:0]         csrConfigInternal;
  logic [0:NumCsr-1] [DataW-1:0]         csrConfigPipe;
  for (genvar i=0; i<NumCsr; i++) begin : config_pipe

    oclib_pipeline #(.Width(DataW), .Length(CsrConfigOutputFlops[i]), .NoShiftRegister(oclib_pkg::True))
    uPIPE (.clock(clock), .in(csrConfigInternal[i]), .out(csrConfigPipe[i]));

    oclib_synchronizer #(.Width(DataW), .Enable(CsrConfigOutputAsync[i]))
    uSYNC (.clock(clockCsrConfig), .in(csrConfigPipe[i]), .out(csrOut[i]));

  end

  // These strobes aren't handled very well in async case, in future may want to revisit this
  // so that (for example) logic in another clock domain gets a read strobe on the exact
  // cycle that it's data is captured, so that it can implement a clear-on-read counter.  Right
  // now we just output pulses in main clock domain, if they are needed by async client they
  // can be synchronized but the exact alignment to the input/output data busses will be undefined
  logic [0:NumCsr-1]                     csrWriteInternal;
  logic [0:NumCsr-1]                     csrReadInternal;
  oclib_pipeline #(.Width(2*NumCsr), .Length(OutputFlops), .NoShiftRegister(oclib_pkg::True))
  uOUTPUT_FLOPS (.clock(clock), .in({csrWriteInternal,csrReadInternal}),
                 .out({csrWrite, csrRead}));

  // Compute read values for all CSRs, this logic is unrolled and mostly optimizes away
  logic [0:NumCsr-1] [DataW-1:0]         csrReadValue;
  always_comb begin
    for (int i=0; i<NumCsr; i++) begin
      csrReadValue[i] = ((csrConfigInternal[i] & CsrRwBits[i] & ~CsrWoBits[i] & ~CsrRoBits[i] & ~CsrFixedBits[i]) |
                         (csrStatusInternal[i] & CsrRoBits[i] & ~CsrFixedBits[i]) |
                         (CsrInitBits[i] & CsrFixedBits[i]));
    end
  end

  logic [LocalCsrAddressWidth-1:0]       csrAddress;
  assign csrAddress = csrNormal.address[$bits(csrNormal.address)-1:CsrAddressShift];

  // Implement the CSR flops.  Heavily reliant on synthesis optimizing unused logic (a common theme in OpenChip)
  always_ff @(posedge clock) begin
    csrNormalFb.rdata <= (csrNormal.read && !csrNormalFb.ready) ? csrReadValue[csrAddress] :
                         csrNormal.write ? '0 :
                         csrNormalFb.rdata;
    if (resetSync) begin
      for (int i=0; i<NumCsr; i++) begin
        csrConfigInternal[i] <= CsrInitBits[i];
      end
      csrNormalFb <= '0;
      csrReadInternal <= '0;
      csrWriteInternal <= '0;
    end
    else begin
      csrReadInternal <= '0;
      csrWriteInternal <= '0;
      csrNormalFb.ready <= (csrSelect && (csrNormal.read || csrNormal.write) && !csrNormalFb.ready);
      csrNormalFb.error <= (csrNormalFb.error ? csrSelect :
                            (csrSelect && (csrNormal.read || csrNormal.write) && (csrAddress >= NumCsr)));
      for (int i=0; i<NumCsr; i++) begin
        if (i==csrAddress) begin
          if (csrSelect && csrNormal.write && !csrNormalFb.ready) begin
            csrConfigInternal[i] <= ((CsrFixedBits[i] & CsrInitBits[i]) |
                                     (csrNormal.wdata & (CsrRwBits[i] | CsrWoBits[i]) & ~CsrFixedBits[i]));
            csrWriteInternal[i] <= 1'b1;
          end
          if (csrSelect && csrNormal.read && !csrNormalFb.ready) begin
            csrReadInternal[i] <= 1'b1;
          end
        end // if (i==csrAddress)
      end // for (int i=0; i<NumCsr; i++)
    end // else: !if(resetSync)
  end // always_ff @ (posedge clock)

endmodule // oclib_csr_array
