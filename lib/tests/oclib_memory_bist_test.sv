
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_pkg.sv"
`include "sim/ocsim_pkg.sv"

// `define OC_TEST_SHORT

module oclib_memory_bist_test #(
                                parameter int CsrToPortFlops = 2,
                                parameter     type AxilType = oclib_pkg::axil_32_s,
                                parameter     type AxilFbType = oclib_pkg::axil_32_fb_s,
                                parameter int AxilClockFreq = 100000000, // used for the uptime counters
                                parameter     type AximType = oclib_pkg::axi4m_256_s,
                                parameter     type AximFbType = oclib_pkg::axi4m_256_fb_s,
                                parameter int AximPorts = `OC_VAL_ASDEFINED_ELSE(OC_TEST_AXIM_PORTS, 4),
                                parameter int AximPortRetimers = 0, // add retiming stages between port logic and HBM port
                                parameter int ConfigPipeStages = 0,
                                parameter int StatusPipeStages = 0
                              );

  // CLOCK/RESET

  logic clockAxil = 0;
  logic clockAxim = 1;
  logic reset;

  real  AxilPeriodNS = 10; // default 100MHz
  real  AxiPeriodNS = 2; // default 500MHz

  always #(500ps*AxilPeriodNS) clockAxil = ~clockAxil;
  always #(500ps*AxiPeriodNS) clockAxim = ~clockAxim;

  // CSR SOURCE

  AxilType axil;
  AxilFbType axilFb;

  ocsim_axil_source #(.AxilType(AxilType), .AxilFbType(AxilFbType))
  uCSR (.clock(clockAxil), .reset(reset),
        .axil(axil), .axilFb(axilFb));

  // AXI SINK
  AximType [AximPorts-1:0] axim;
  AximFbType [AximPorts-1:0] aximFb;

  ocsim_axim_memory #(.AximType(AximType), .AximFbType(AximFbType),
                      .AximPorts(AximPorts),
                      .SeparateMemorySpaces(`OC_VAL_ASDEFINED_ELSE(OC_TEST_SEPARATE_MEMORY_SPACES,0)))
  uSINK (.clockAxim({AximPorts{clockAxim}}), .resetAxim({AximPorts{reset}}),
         .axim(axim), .aximFb(aximFb));

  // TB PROCS

  logic [31:0] temp32;
  logic [31:0] temp32b;

  task Test();
    $display("%t %m: START TEST ITER", $realtime);
    reset = 1;
    repeat (50) @(posedge clockAxil);
    reset = 0;
    repeat (20) @(posedge clockAxil);

    $display("%t %m: *** sanity read/write", $realtime);
    uCSR.CsrReadCheck('h0000, 'h80000000);
    uCSR.CsrReadCheck('h0034, 'h4d454d54);
    uCSR.CsrWrite('h0034, 'h00000000);
    uCSR.CsrReadCheck('h0034, 'h4d454d54);
    uCSR.CsrWrite('h0000, 'h00ffff00);
    uCSR.CsrReadCheck('h0000, 'h80ffff00);

    $display("%t %m: *** debug counters read/write", $realtime);
    $display("%t %m: reload seconds", $realtime);
    uCSR.CsrRead('h0300, temp32);
    $display("%t %m: reset seconds", $realtime);
    uCSR.CsrRead('h0304, temp32);
    $display("%t %m: AXIL write count", $realtime);
    uCSR.CsrRead('h0308, temp32);
    $display("%t %m: AXIL read count", $realtime);
    uCSR.CsrRead('h030c, temp32);
    $display("%t %m: cycles under reset", $realtime);
    uCSR.CsrRead('h0310, temp32);
    $display("%t %m: cycles since reset", $realtime);
    uCSR.CsrRead('h0314, temp32);
    $display("%t %m: AXI cycles under reset", $realtime);
    uCSR.CsrRead('h0038, temp32);
    $display("%t %m: AXI cycles since reset", $realtime);
    uCSR.CsrRead('h003c, temp32);

    $display("%t %m: *** single write", $realtime);
    for (int i=1; i<=8; i++) begin
      uCSR.CsrWrite('h0100 + ((i-1)*4), {8{i[3:0]}});
      uCSR.CsrReadCheck('h0100 + ((i-1)*4), {8{i[3:0]}});
    end
    $display("%t %m: enable first channel", $realtime);
    uCSR.CsrWrite('h0008, 32'h00000001);
    $display("%t %m: set go, write, no prescale", $realtime);
    uCSR.CsrWrite('h0000, 32'h00000101);
    temp32 = '0;
    $display("%t %m: poll done", $realtime);
    while ((temp32 & 'h80000000) == 0) uCSR.CsrRead('h0000, temp32);
    $display("%t %m: read cycle counter", $realtime);
    uCSR.CsrRead('h0030, temp32);
    $display("%t %m: clear go", $realtime);
    uCSR.CsrWrite('h0000, 32'h00000000);

    $display("%t %m: *** single read", $realtime);
    $display("%t %m: set go, read, no prescale", $realtime);
    uCSR.CsrWrite('h0000, 32'h00010001);
    temp32 = '0;
    $display("%t %m: poll done", $realtime);
    while ((temp32 & 'h80000000) == 0) uCSR.CsrRead('h0000, temp32);
    $display("%t %m: read cycle counter", $realtime);
    uCSR.CsrRead('h0030, temp32);
    $display("%t %m: clear go", $realtime);
    uCSR.CsrWrite('h0000, 32'h00000000);
    $display("%t %m: read back data", $realtime);
    for (int i=1; i<=8; i++) begin
      uCSR.CsrReadCheck('h0200 + ((i-1)*4), {8{i[3:0]}}); // read back data
    end
    $display("%t %m: clear go", $realtime);
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

`ifndef OC_TEST_SHORT

    $display("%t %m: *** burst write, all channels", $realtime);
    uCSR.CsrWrite('h0004, 32'h000000ff); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000020); // address_inc LSB (32 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00000101); // set go, write, no prescale
    PollDone();
    DumpStats();
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst read, all channels", $realtime);
    uCSR.CsrWrite('h0000, 32'h00010001); // set go, read, no prescale
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    for (int i=0; i<AximPorts; i++) begin
      uCSR.CsrWrite('h0008, 1 << i); // enable single channel
      repeat (3*AximPorts) @(posedge clockAxil);
      uCSR.CsrReadCheck('h0028, 'ha22221c8); // check signature
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst write, all channels, wait states", $realtime);
    uCSR.CsrWrite('h0004, 32'h000000ff); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000020); // address_inc LSB (32 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000001); // wait states
    uCSR.CsrWrite('h0044, 32'h00000000); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00000101); // set go, write, no prescale
    PollDone();
    DumpStats();
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst read, all channels, wait states", $realtime);
    uCSR.CsrWrite('h0004, 32'h000000ff); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000020); // address_inc LSB (128 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000001); // wait states
    uCSR.CsrWrite('h0044, 32'h00000000); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00010001); // set go, read, no prescale
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    for (int i=0; i<AximPorts; i++) begin
      uCSR.CsrWrite('h0008, 1 << i); // enable single channel
      repeat (3*AximPorts) @(posedge clockAxil);
      uCSR.CsrReadCheck('h0028, 'ha22221c8); // check signature
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst write, all channels, wait states", $realtime);
    uCSR.CsrWrite('h0004, 32'h000000ff); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000020); // address_inc LSB (32 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h00000000); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00000101); // set go, write, no prescale
    PollDone();
    DumpStats();
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst read, all channels, wait states", $realtime);
    uCSR.CsrWrite('h0004, 32'h000000ff); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000020); // address_inc LSB (128 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h00000000); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00010001); // set go, read, no prescale
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    for (int i=0; i<AximPorts; i++) begin
      uCSR.CsrWrite('h0008, 1 << i); // enable single channel
      repeat (3*AximPorts) @(posedge clockAxil);
      uCSR.CsrReadCheck('h0028, 'ha22221c8); // check signature
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go


    $display("%t %m: *** burst write, all channels, 128B bursts", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (32 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000000); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00000101); // set go, write, no prescale
    PollDone();
    DumpStats();
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst read, all channels, 128B bursts", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 64
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (128 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000000); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00010001); // set go, read, no prescale
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    for (int i=0; i<AximPorts; i++) begin
      uCSR.CsrWrite('h0008, 1 << i); // enable single channel
      repeat (3*AximPorts) @(posedge clockAxil);
      uCSR.CsrReadCheck('h0028, 'ha22221c8); // check signature
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst write, all channels, wait states, 128B bursts", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (32 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000001); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00000101); // set go, write, no prescale
    PollDone();
    DumpStats();
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst read, all channels, wait states, 128B bursts", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 64
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (128 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00010001); // set go, read, no prescale
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    for (int i=0; i<AximPorts; i++) begin
      uCSR.CsrWrite('h0008, 1 << i); // enable single channel
      repeat (3*AximPorts) @(posedge clockAxil);
      uCSR.CsrReadCheck('h0028, 'ha22221c8); // check signature
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst write, all channels, wait states, 128B bursts", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 256
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (32 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00000741); // set go, write, no prescale, 16-bit port address shift
    PollDone();
    DumpStats();
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst read, all channels, wait states, 128B bursts", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 64
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (128 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00010001); // set go, read, no prescale
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    for (int i=0; i<AximPorts; i++) begin
      uCSR.CsrWrite('h0008, 1 << i); // enable single channel
      repeat (3*AximPorts) @(posedge clockAxil);
      uCSR.CsrReadCheck('h0028, 'ha22221c8); // check signature
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

`endif //  `ifndef OC_TEST_SHORT

    $display("%t %m: *** burst write, all channels, wait states, 128B bursts, 64 IDs", $realtime);
    uCSR.CsrWrite('h0004, 32'h00000040); // op_count = 65 -- doing extra op so we can random read
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (32 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00001fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h0048, 32'h00003f3f); // 64 ARID and AWID
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h0000, 32'h00000101); // set go, write, no prescale
    PollDone();
    DumpStats();
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** long read to read out context/latency counters", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000ffff); // op_count = 64K
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (128 Byte) -- dont care
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000000); // address_inc_mask LSB (masked, address is all random)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h0000000f); // burst length
    uCSR.CsrWrite('h0048, 32'h00003f3f); // 64 ARID and AWID
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h004c, 32'h00000fe0); // address_random_mask
    uCSR.CsrWrite('h0000, 32'h00110001); // set go, read, no prescale, random len
    $display("%t %m:   * Reading out live counters", $realtime);
    #20us;
    for (int i=0; i<4; i++) begin
      uCSR.CsrWrite('h0058, (i<<16) + 0); // max/avg contexts
      uCSR.CsrRead('h005c, temp32);
      $display("%t %m:   - Contexts:              %6d max (%6d avg)", $realtime, temp32[31:16], temp32[15:0]);
      uCSR.CsrWrite('h0058, (i<<16) + 1); // latency cycles max/min
      uCSR.CsrRead('h005c, temp32);
      uCSR.CsrWrite('h0058, (i<<16) + 2); // latency cycles avg
      uCSR.CsrRead('h005c, temp32b);
      $display("%t %m:   - Latency:  %6d min - %6d max (%6d avg)", $realtime, temp32[15:0], temp32[31:16], temp32b[15:0]);
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go (rough stop)
    repeat (5000) @(posedge clockAxil); // need to let old data flush through before starting again after rough stop

    $display("%t %m: *** burst read, all channels, wait states, 128B bursts, 64 IDs", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 64
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (128 Byte)
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000fff); // address_inc_mask LSB (4KByte)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h00000003); // burst length
    uCSR.CsrWrite('h0048, 32'h00003f3f); // 64 ARID and AWID
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h004c, 32'h00000000); // address_random_mask
    uCSR.CsrWrite('h0000, 32'h00010001); // set go, read, no prescale
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    for (int i=0; i<AximPorts; i++) begin
      uCSR.CsrWrite('h0008, 1 << i); // enable single channel
      repeat (3*AximPorts) @(posedge clockAxil);
      uCSR.CsrReadCheck('h0028, 'ha22221c8); // check signature
    end
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: *** burst read, all channels, wait states, 32-512B bursts, 64 IDs, random address/length", $realtime);
    uCSR.CsrWrite('h0004, 32'h0000003f); // op_count = 64
    uCSR.CsrWrite('h0008, 32'hffffffff); // enable all channels
    uCSR.CsrWrite('h0010, 32'h00000000); // address LSB
    uCSR.CsrWrite('h0014, 32'h00000000); // address MSB
    uCSR.CsrWrite('h0018, 32'h00000080); // address_inc LSB (128 Byte) -- dont care
    uCSR.CsrWrite('h001c, 32'h00000000); // address_inc MSB
    uCSR.CsrWrite('h0020, 32'h00000000); // address_inc_mask LSB (masked, address is all random)
    uCSR.CsrWrite('h0024, 32'h00000000); // address_inc_mask MSB
    uCSR.CsrWrite('h0040, 32'h00000002); // wait states
    uCSR.CsrWrite('h0044, 32'h0000000f); // burst length
    uCSR.CsrWrite('h0048, 32'h00003f3f); // 64 ARID and AWID
    uCSR.CsrWrite('h004c, 32'h00ff0010); // port shift (all bits, << 16)
    uCSR.CsrWrite('h004c, 32'h00000fe0); // address_random_mask
    uCSR.CsrWrite('h0000, 32'h00110001); // set go, read, no prescale, random len
    PollDone();
    DumpStats();
    $display("%t %m: * check signatures", $realtime);
    uCSR.CsrWrite('h0008, 32'h00000001);
    repeat (3*AximPorts) @(posedge clockAxil);
    uCSR.CsrReadCheck('h0028, 'hba4b17b9);
    uCSR.CsrWrite('h0008, 32'h00000002);
    repeat (3*AximPorts) @(posedge clockAxil);
    uCSR.CsrReadCheck('h0028, 'h773cda0d);
    uCSR.CsrWrite('h0008, 32'h00000004);
    repeat (3*AximPorts) @(posedge clockAxil);
    uCSR.CsrReadCheck('h0028, 'he12d0957);
    uCSR.CsrWrite('h0008, 32'h00000008);
    repeat (3*AximPorts) @(posedge clockAxil);
    uCSR.CsrReadCheck('h0028, 'h558367d6);
    uCSR.CsrWrite('h0000, 32'h00000000); // clear go

    $display("%t %m: PASSED TEST ITER", $realtime);
  endtask // Test

  task PollDone();
    temp32 = '0;
    while ((temp32 & 'h80000000) == 0) uCSR.CsrRead('h0000, temp32); // poll done
  endtask

  task DumpStats();
    uCSR.CsrRead('h0030, temp32); // read cycle counter
    $display("%t %m:   - cycles: %0d", $realtime, temp32);
  endtask

  initial begin
    $display("%t %m: START BIG TEST", $realtime);
`ifdef OLD_RTL
    Test();
`else
    for (int axil_iter=0; axil_iter < 2; axil_iter++) begin
      case (axil_iter)
        0 : AxilPeriodNS = 10.0; // 100MHz
        1 : AxilPeriodNS = 4.0; // 250MHz
      endcase // case (axil_iter)
      for (int axi_iter=0; axi_iter < 2; axi_iter++) begin
        case (axi_iter)
          0 : AxiPeriodNS = 5.9; // 169MHz
          1 : AxiPeriodNS = 1.9; // 525MHz
        endcase // case (axi_iter)
        for (int stress_iter=0; stress_iter < (((axil_iter==0)&&(axi_iter==0))?2:1); stress_iter++) begin
          uCSR.stress = stress_iter;
          $display("%t %m: ***************************************************************", $realtime);
          $display("%t %m: *** TEST ITER: AXIL_CLK=%0d AXI_CLK=%0d STRESS=%0d", $realtime, axil_iter, axi_iter, stress_iter);
          $display("%t %m: ***************************************************************", $realtime);
          Test();
        end
      end
    end
`endif
    $display("%t %m: TEST PASSED", $realtime);
    $finish;
  end


  oclib_memory_bist #(.CsrToPortFlops(CsrToPortFlops),
                      .AxilType(AxilType),
                      .AxilFbType(AxilFbType),
                      .AxilClockFreq(AxilClockFreq),
                      .AximType(AximType),
                      .AximFbType(AximFbType),
                      .AximPorts(AximPorts),
                      .AximPortRetimers(AximPortRetimers),
                      .ConfigPipeStages(ConfigPipeStages),
                      .StatusPipeStages(StatusPipeStages)
                      )
  uDUT (
        .reset(reset), .clockAxil(clockAxil),
        .axil(axil), .axilFb(axilFb),
        .clockAxim(clockAxim),
        .axim(axim), .aximFb(aximFb)
        );

endmodule // oclib_memory_bist_test
