
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"
`include "lib/oclib_uart_pkg.sv"

module oc_uart_control
  #(
    parameter integer            ClockHz = 100_000_000,
    parameter integer            Baud = 115_200,
    parameter                    type UartControlBcType = oclib_pkg::bc_8b_bidi_s,
    parameter                    type UartControlProtocol = oclib_pkg::csr_32_s,
    parameter                    type UartBcType = oclib_pkg::bc_8b_bidi_s, // if uart is physically far from rest of this block
    parameter logic [0:1] [7:0]  BlockTopCount = '0,
    parameter logic [0:1] [7:0]  BlockUserCount = '0,
    parameter bit                ResetSync = oclib_pkg::False,
    parameter integer            ErrorWidth = oclib_uart_pkg::ErrorWidth,
    parameter bit                ManagerReset = `OC_VAL_ASDEFINED_ELSE(TARGET_MANAGER_RESET, 1),
    parameter integer            ManagerResetLength = `OC_VAL_ASDEFINED_ELSE(TARGET_MANAGER_RESET_LENGTH, 64),
    parameter bit                UptimeCounters = `OC_VAL_ASDEFINED_ELSE(TARGET_UPTIME_COUNTERS, 1),
    parameter logic [0:2] [7:0]  BuilderID = `OC_VAL_ASDEFINED_ELSE(TARGET_BUILDER_ID, 24'hffffff),
    parameter logic [0:3] [7:0]  BitstreamID = `OC_VAL_ASDEFINED_ELSE(TARGET_BITSTREAM_ID, 32'h12345678),
    parameter logic [0:3] [7:0]  BuildDate = `OC_VAL_ASDEFINED_ELSE(OC_BUILD_DATE, 32'h20210925),
    parameter logic [0:1] [7:0]  BuildTime = `OC_VAL_ASDEFINED_ELSE(OC_BUILD_TIME, 16'h1200),
    parameter logic [0:3] [7:0]  BuildUuid0 = `OC_VAL_ASDEFINED_ELSE(OC_BUILD_UUID0, 32'd0),
    parameter logic [0:3] [7:0]  BuildUuid1 = `OC_VAL_ASDEFINED_ELSE(OC_BUILD_UUID1, 32'd0),
    parameter logic [0:3] [7:0]  BuildUuid2 = `OC_VAL_ASDEFINED_ELSE(OC_BUILD_UUID2, 32'd0),
    parameter logic [0:3] [7:0]  BuildUuid3 = `OC_VAL_ASDEFINED_ELSE(OC_BUILD_UUID3, 32'd0),
    parameter logic [0:15] [7:0] BuildUuid = `OC_VAL_ASDEFINED_ELSE(OC_BUILD_UUID, {BuildUuid0,BuildUuid1,BuildUuid2,BuildUuid3}),
    parameter logic [0:1] [7:0]  TargetVendor = `OC_VAL_ASDEFINED_ELSE(OC_VENDOR, 16'hffff),
    parameter logic [0:1] [7:0]  TargetBoard = `OC_VAL_ASDEFINED_ELSE(OC_BOARD, 16'hffff),
    parameter logic [0:1] [7:0]  TargetLibrary = `OC_VAL_ASDEFINED_ELSE(OC_LIBRARY, 16'hffff),
    parameter logic [7:0]        BlockProtocol = $bits(oclib_pkg::csr_32_s),
    parameter logic [0:15] [7:0] UserSpace = `OC_VAL_ASDEFINED_ELSE(USER_APP_STRING, "none            ")
    )
  (
   input                         clock,
   input                         reset,
   output logic                  resetOut,
   output logic [ErrorWidth-1:0] uartError,
   input                         uartRx,
   output logic                  uartTx,
   input                         UartControlBcType bcIn,
   output                        UartControlBcType bcOut
   );

  logic                         vioReset;
  logic                         resetQ;

  oclib_synchronizer #(.Enable(ResetSync))
  uRESET_SYNC (.clock(clock), .in(reset || vioReset), .out(resetQ));

  // Philosophy here is to not backpressure the RX channel.  We dont want to block attempts to
  // reset or resync, and you cannot overrun the RX state machine when following the protocol.

  UartBcType bcRx, bcTx;

  oclib_uart #(.ClockHz(ClockHz), .Baud(Baud), .BcType(UartBcType))
  uUART (.clock(clock), .reset(resetQ), .error(uartError),
         .rx(uartRx), .tx(uartTx),
         .bcOut(bcRx), .bcIn(bcTx));


  // internally we assume sync 8-bit, so convert if necessary

  oclib_pkg::bc_8b_bidi_s bcFromUart, bcToUart;

  oclib_bc_bidi_adapter #(.BcAType(UartBcType), .BcBType(oclib_pkg::bc_8b_bidi_s))
  uUART_BC_ADAPTER (.clock(clock), .reset(resetQ),
               .aIn(bcRx), .aOut(bcTx),
               .bOut(bcFromUart), .bIn(bcToUart));

  // **************************
  // SERIAL ROM
  // **************************

  localparam integer            SerialRomBanner = 0;
  localparam integer            SerialRomPrompt = (SerialRomBanner+14);
  localparam integer            SerialRomCtrlC = (SerialRomPrompt+6);
  localparam integer            SerialRomError = (SerialRomCtrlC+3);

  logic [7:0]                   serialCounter;
  logic [7:0]                   syntaxRomData;

  // This will get efficiently implemented as 8 LUTs, up to depth 64
  // try to get this down to 32 by squeezing banner
  always_comb begin
    case (serialCounter[5:0])

      (SerialRomBanner+ 0) : syntaxRomData = 'h0d;
      (SerialRomBanner+ 1) : syntaxRomData = 'h0a;
      (SerialRomBanner+ 2) : syntaxRomData = "*";
      (SerialRomBanner+ 3) : syntaxRomData = " ";
      (SerialRomBanner+ 4) : syntaxRomData = "O";
      (SerialRomBanner+ 5) : syntaxRomData = "P";
      (SerialRomBanner+ 6) : syntaxRomData = "E";
      (SerialRomBanner+ 7) : syntaxRomData = "N";
      (SerialRomBanner+ 8) : syntaxRomData = "C";
      (SerialRomBanner+ 9) : syntaxRomData = "O";
      (SerialRomBanner+10) : syntaxRomData = "S";
      (SerialRomBanner+11) : syntaxRomData = " ";
      (SerialRomBanner+12) : syntaxRomData = "*";
      (SerialRomBanner+13) : syntaxRomData = 'h00;

      (SerialRomPrompt+ 0) : syntaxRomData = 'h0d;
      (SerialRomPrompt+ 1) : syntaxRomData = 'h0a;
      (SerialRomPrompt+ 2) : syntaxRomData = "O";
      (SerialRomPrompt+ 3) : syntaxRomData = "C";
      (SerialRomPrompt+ 4) : syntaxRomData = ">";
      (SerialRomPrompt+ 5) : syntaxRomData = 'h00;

      (SerialRomCtrlC + 0) : syntaxRomData = "^";
      (SerialRomCtrlC + 1) : syntaxRomData = "C";
      (SerialRomCtrlC + 2) : syntaxRomData = 'h00;

      (SerialRomError + 0) : syntaxRomData = 'h0d;
      (SerialRomError + 1) : syntaxRomData = 'h0a;
      (SerialRomError + 2) : syntaxRomData = "E";
      (SerialRomError + 3) : syntaxRomData = "R";
      (SerialRomError + 4) : syntaxRomData = "R";
      (SerialRomError + 5) : syntaxRomData = "O";
      (SerialRomError + 6) : syntaxRomData = "R";
      (SerialRomError + 7) : syntaxRomData = 'h00;

      default : syntaxRomData = '0;
    endcase // case (counter[5:0])
  end

  logic [7:0]                   infoRomData;
  always_comb begin
    case (serialCounter[5:0])
      6'h00   : infoRomData = 8'h01; // Info dump version
      6'h01   : infoRomData = BuilderID[0];
      6'h02   : infoRomData = BuilderID[1];
      6'h03   : infoRomData = BuilderID[2];
      6'h04   : infoRomData = BitstreamID[0];
      6'h05   : infoRomData = BitstreamID[1];
      6'h06   : infoRomData = BitstreamID[2];
      6'h07   : infoRomData = BitstreamID[3];
      6'h08   : infoRomData = BuildDate[0];
      6'h09   : infoRomData = BuildDate[1];
      6'h0a   : infoRomData = BuildDate[2];
      6'h0b   : infoRomData = BuildDate[3];
      6'h0c   : infoRomData = BuildTime[0];
      6'h0d   : infoRomData = BuildTime[1];
      6'h0e   : infoRomData = TargetVendor[0];
      6'h0f   : infoRomData = TargetVendor[1];
      6'h10   : infoRomData = TargetLibrary[0];
      6'h11   : infoRomData = TargetLibrary[1];
      6'h12   : infoRomData = TargetBoard[0];
      6'h13   : infoRomData = TargetBoard[1];
      6'h14   : infoRomData = BlockTopCount[0];
      6'h15   : infoRomData = BlockTopCount[1];
      6'h16   : infoRomData = BlockUserCount[0];
      6'h17   : infoRomData = BlockUserCount[1];
      6'h18   : infoRomData = BlockProtocol;
      6'h20   : infoRomData = UserSpace[0];
      6'h21   : infoRomData = UserSpace[1];
      6'h22   : infoRomData = UserSpace[2];
      6'h23   : infoRomData = UserSpace[3];
      6'h24   : infoRomData = UserSpace[4];
      6'h25   : infoRomData = UserSpace[5];
      6'h26   : infoRomData = UserSpace[6];
      6'h27   : infoRomData = UserSpace[7];
      6'h28   : infoRomData = UserSpace[8];
      6'h29   : infoRomData = UserSpace[9];
      6'h2a   : infoRomData = UserSpace[10];
      6'h2b   : infoRomData = UserSpace[11];
      6'h2c   : infoRomData = UserSpace[12];
      6'h2d   : infoRomData = UserSpace[13];
      6'h2e   : infoRomData = UserSpace[14];
      6'h2f   : infoRomData = UserSpace[15];
      6'h30   : infoRomData = BuildUuid[0];
      6'h31   : infoRomData = BuildUuid[1];
      6'h32   : infoRomData = BuildUuid[2];
      6'h33   : infoRomData = BuildUuid[3];
      6'h34   : infoRomData = BuildUuid[4];
      6'h35   : infoRomData = BuildUuid[5];
      6'h36   : infoRomData = BuildUuid[6];
      6'h37   : infoRomData = BuildUuid[7];
      6'h38   : infoRomData = BuildUuid[8];
      6'h39   : infoRomData = BuildUuid[9];
      6'h3a   : infoRomData = BuildUuid[10];
      6'h3b   : infoRomData = BuildUuid[11];
      6'h3c   : infoRomData = BuildUuid[12];
      6'h3d   : infoRomData = BuildUuid[13];
      6'h3e   : infoRomData = BuildUuid[14];
      6'h3f   : infoRomData = BuildUuid[15];
      default : infoRomData = '0;
    endcase // case (counter[5:0])
  end // always_comb

  // **************************
  // OPTIONAL SELF-RESET LOGIC
  // **************************

  localparam ManagerResetCounterW = $clog2(ManagerResetLength+1);
  logic [ManagerResetCounterW-1:0] resetCount;

  if (ManagerReset) begin
    always @(posedge clock) begin
      if (resetQ) begin
        resetCount <= '0;
        resetOut <= 1'b0;
      end
      else begin
        if (bcFromUart.valid) begin
          resetCount <= ((bcFromUart.data == oclib_pkg::ResetChar) ? (resetCount + 'd1) : '0);
        end
        if (resetCount >= ManagerResetLength) begin
          resetOut <= 1'b1; // when the reset comes, it will clear us out of this state, all hail the reset
        end
      end
    end
  end
  else begin
    assign resetCount = '0;
    assign resetOut = '0;
  end

  // **************************
  // OPTIONAL UPTIME TIMERS
  // **************************

  // readback to main state machine
  logic                        readTimers; // controlled by main SM
  logic [7:0]                  timerByte; // read data back to the main SM

  if (UptimeCounters) begin

    // first we detect the reload event, essentially generating a "power on reset"
    logic [7:0]                reloadStable = 8'h0;
    logic                      reloadDetect;
    always_ff @(posedge clock) begin
      reloadStable <= { reloadStable[6:0], 1'b1 };
      reloadDetect <= !reloadStable[7];
    end

    // count time since reload
    localparam integer         PrescaleBits = $clog2(ClockHz);
    logic                      reloadUptimePulse;
    logic [PrescaleBits-1:0]   reloadUptimePrescale;
    logic [31:0]               reloadUptimeSeconds;

    // also count cycles design has been held in reset, for debugging reset issues (is it long enough from source XXX,
    // did something stop because of a reset, etc). Needs to be cleared on reload because it has no other reset.
    logic [31:0]              cyclesUnderReset;
    always_ff @(posedge clock) begin
      if (reloadDetect) begin
        reloadUptimePulse <= 1'b0;
        reloadUptimePrescale <= '0;
        reloadUptimeSeconds <= '0;
        cyclesUnderReset <= '0;
      end
      else begin
        reloadUptimePulse <= (reloadUptimePrescale == (ClockHz-2));
        reloadUptimePrescale <= (reloadUptimePulse ? '0 : (reloadUptimePrescale + 'd1));
        reloadUptimeSeconds <= (reloadUptimeSeconds + {'0, reloadUptimePulse});
        cyclesUnderReset <= (cyclesUnderReset + {'0, resetQ});
      end
    end

    logic                                             resetUptimePulse;
    logic [PrescaleBits-1:0]                          resetUptimePrescale;
    logic [31:0]                                      resetUptimeSeconds;
    logic [31:0]                                      cyclesSinceReset;

    always_ff @(posedge clock) begin
      if (resetQ) begin
        resetUptimePulse <= 1'b0;
        resetUptimePrescale <= '0;
        resetUptimeSeconds <= '0;
        cyclesSinceReset <= '0;
      end
      else begin
        resetUptimePulse <= (resetUptimePrescale == (ClockHz-2));
        resetUptimePrescale <= (resetUptimePulse ? '0 : (resetUptimePrescale + 'd1));
        resetUptimeSeconds <= (resetUptimeSeconds + {'0, resetUptimePulse});
        cyclesSinceReset <= (cyclesSinceReset + 'd1);
      end
    end

    logic [0:15] [7:0] timerCache;
    always_ff @(posedge clock) begin
      if (readTimers) begin
        timerCache <= { reloadUptimeSeconds,
                        resetUptimeSeconds,
                        cyclesSinceReset,
                        cyclesUnderReset };
      end
      timerByte <= timerCache[serialCounter[3:0]];
    end
  end // if (UptimeCounters)
  else begin
    assign timerByte = 8'hFF;
  end // else: !if(UptimeCounters)

  // **************************
  // ON-CHIP BC INTERFACE
  // **************************

  oclib_pkg::bc_8b_bidi_s bcIntIn, bcIntOut;
  oclib_bc_bidi_adapter #(.BcAType(UartControlBcType), .BcBType(oclib_pkg::bc_8b_bidi_s))
  uINT_BC_ADAPTER (.clock(clock), .reset(resetQ),
                   .aIn(bcIn), .aOut(bcOut),
                   .bOut(bcIntIn), .bIn(bcIntOut));

  // **************************
  // HARDWARE SERIAL CONSOLE
  // **************************

  enum logic [3:0] { StBanner = 0, StPrompt = 1, StInput = 2,
                     StWaitForEnter = 3, StSyntaxError = 4,
                     StTxRom = 5, StTxHex = 6, StEnterThenTxHex = 7, StRxHex = 8,
                     StInfo = 9, StTimers = 10,
                     StBcMsg = 11, StBcMsgCopy = 12, StBcMsgCopy2 = 13,
                     StBcMsgReceive = 14, StBcMsgAbort = 15 } state, nextState;

  logic       inComment;
  logic       binaryMode;
  logic       messageMode;
  logic       nibble;
  logic [7:0] tempData;

  always @(posedge clock) begin
    bcToUart.ready <= 1'b1; // always true, but tools get buggy when struct fields set in different ways
    if (resetQ) begin
      state <= StBanner;
      nextState <= StBanner;
      serialCounter <= '0;
      bcToUart.valid <= 1'b0;
      bcToUart.data <= '0;
      inComment <= 1'b0;
      binaryMode <= 1'b0;
      messageMode <= 1'b0;
      nibble <= 1'b0;
      tempData <= '0;
      readTimers <= 1'b0;
      bcIntOut <= '0;
    end
    else begin

      readTimers <= 1'b0;
      bcIntOut <= '0;

      case (state)

        StBanner : begin
          serialCounter <= SerialRomBanner;
          state <= StTxRom;
          nextState <= StPrompt;
        end // case: StBanner

        StPrompt : begin
          serialCounter <= SerialRomPrompt;
          state <= StTxRom;
          nextState <= StInput;
        end // StPrompt

        StInput : begin
          // In this state, we've just had the prompt printed, and we're waiting for a command
          serialCounter <= '0;
          binaryMode <= 1'b0;
          messageMode <= 1'b0;
          nibble <= 1'b0;
          if (bcFromUart.valid) begin
            // "I" means info in binary, "i" means info in ASCII
            if ((bcFromUart.data | 'h20) == "i") begin // that 'h20 will convert capital to lowercase
              // info dump, if compiled in, wait for enter to confirm
              binaryMode <= !(bcFromUart.data[5]); // this detects the capital without different gates each time
              state <= StWaitForEnter;
              nextState <= StInfo;
            end
            else if ((bcFromUart.data | 'h20) == "t") begin
              // timer dump, if compiled in, wait for enter to confirm
              binaryMode <= !(bcFromUart.data[5]);
              readTimers <= 1'b1;
              state <= StWaitForEnter;
              nextState <= StTimers;
            end
            else if ((bcFromUart.data | 'h20) == "b") begin
              // timer dump, if compiled in, wait for enter to confirm
              binaryMode <= !(bcFromUart.data[5]);
              state <= StRxHex; // collect the message length
              nextState <= StBcMsg;
            end
            else if ((bcFromUart.data == 8'h0a) || (bcFromUart.data == 8'h0d)) begin
              // got an enter, ack by sending prompt again
              state <= StPrompt;
            end
            else if (bcFromUart.data == 8'h03) begin // Control-C, ack and return to prompt
              serialCounter <= SerialRomCtrlC;
              state <= StTxRom;
              nextState <= StPrompt;
            end
            else if ((bcFromUart.data == oclib_pkg::ResetChar) ||
                     (bcFromUart.data == oclib_pkg::SyncChar)) begin
            end
            else begin
              state <= StSyntaxError;
              // didn't understand, go to syntax error state
              serialCounter <= bcFromUart.data;
            end
          end
          inComment <= 1'b0;
        end // case: StInput

        StWaitForEnter : begin
          // we've received everything needed for a command.  We may get more whitespace or comments, but
          // anything else is considered a syntax error.  Due to local-echo we imagine an interactive user
          // checking what they've typed before they hit enter (or control-C to cleanly bail)
          if (bcFromUart.valid) begin
            if ((bcFromUart.data == 8'h0a) || (bcFromUart.data == 8'h0d)) begin
              // We got enter, execute whatever command we were waiting on
              state <= nextState;
            end
            else if (bcFromUart.data == 8'h03) begin // Control-C, ack and return to prompt
              serialCounter <= SerialRomCtrlC;
              state <= StTxRom;
              nextState <= StPrompt;
            end
            else if (bcFromUart.data == "#") begin // Start of a comment, from now on we only care about CR/LF
              inComment <= 1'b1;
            end
            else if ((bcFromUart.data == " ") || (bcFromUart.data == 8'h09)) begin // Whitespace is always ignored
            end
            else if (!inComment) begin
              state <= StSyntaxError;
            end
          end
        end // case: StWaitForEnter

        StRxHex : begin
          if (bcFromUart.valid) begin
            if (binaryMode) begin
              tempData <= bcFromUart.data;
              state <= nextState;
            end
            else if ((bcFromUart.data == " ") || (bcFromUart.data == 8'h09)) begin // Whitespace is always ignored
            end
            else if ((bcFromUart.data >= "0") && (bcFromUart.data <= "9")) begin
              tempData <= ((nibble ? {tempData[3:0],4'd0} : 8'h00) | (bcFromUart.data - "0"));
              nibble <= 1'b1;
              if (nibble) state <= nextState;
            end
            else if ((bcFromUart.data >= "a") && (bcFromUart.data <= "f")) begin
              tempData <= ((nibble ? {tempData[3:0],4'd0} : 8'h00) | (bcFromUart.data - "a" + 10));
              nibble <= 1'b1;
              if (nibble) state <= nextState;
            end
            else if ((bcFromUart.data >= "A") && (bcFromUart.data <= "F")) begin
              tempData <= ((nibble ? {tempData[3:0],4'd0} : 8'h00) | (bcFromUart.data - "A" + 10));
              nibble <= 1'b1;
              if (nibble) state <= nextState;
            end
            else if (bcFromUart.data == 8'h03) begin // Control-C, ack and return to prompt
              state <= StBcMsgAbort;
              serialCounter <= (messageMode ? (serialCounter + 'd8) : '0);
              nibble <= 1'b1;
            end
            else begin
              state <= StBcMsgAbort;
              serialCounter <= (messageMode ? (serialCounter + 'd8) : '0);
              nibble <= 1'b0;
            end
          end
        end // StRxHex

        StSyntaxError : begin
          // What we're doing here is waiting to tell user there's an error.  It feels rude to just jump to
          // printing SYNTAX ERROR while they are typing, it's not the way terminals work.  Perhaps one day
          // we'll give the user the ability to correct mistakes :) and then it'll be required to wait for
          // enter.  But for now, once we see something we don't like, we jump to this state and let their
          // local echo show them what they've been typing, without interruption, then when they hit enter
          // we will inform them of the error.
          if (bcFromUart.valid) begin
            if ((bcFromUart.data == 8'h0a) || (bcFromUart.data == 8'h0d)) begin
              serialCounter <= SerialRomError;
              state <= StTxRom;
              nextState <= StPrompt;
            end
            else if (bcFromUart.data == 8'h03) begin // Control-C, ack and return to prompt
              serialCounter <= SerialRomCtrlC;
              state <= StTxRom;
              nextState <= StPrompt;
            end
          end
        end // case: StSyntaxError

        StTxRom : begin
          // This state prints a message from the serial ROM.  Coming in we expect "serialCounter" to hold the
          // starting address of the message.  Ssince it's 0-cycle combo logic, the syntaxRomData[7:0] net has
          // thevalue of the ROM.  Each byte is pushed out to the UART untill an <ROM> (a zero value in the
          // ROM) is seen.  EOM is not transmitted.
          if (bcToUart.valid) begin
            // we are already requesting something
            if (bcFromUart.ready) begin
              // and it's being consumed
              serialCounter <= (serialCounter + 'd1);
              bcToUart.valid <= 1'b0;
            end
          end
          else begin
            // we are not requesting something
            if (syntaxRomData == 8'h00) begin
              // and syntaxRomData[serialCounter] == <EOM>, so we are done
              state <= nextState;
            end
            else begin
              // and we have data to send
              bcToUart.data <= syntaxRomData;
              bcToUart.valid <= 1'b1;
            end // else: !if(syntaxRomData == '0)
          end // else: !if(bcToUart.valid)
        end // case: StTxRom

        StTxHex : begin
          if (!bcToUart.valid) begin
            // we first enter here
            bcToUart.valid <= 1'b1;
            nibble <= 1'b0;
            bcToUart.data <= (binaryMode ? tempData : oclib_pkg::HexToAsciiNibble(tempData[7:4]));
          end
          else begin
            // bcToUart.valid is set, this is not our first cycle in this state
            if (bcFromUart.ready) begin
              // first time here, nibble=0, we've just sent either top nibble (ascii) or whole byte (binary)
              // second time, nibble=1, we must be in ascii mode, so we send the lower nibble
              nibble <= 1'b1;
              bcToUart.valid <= !(binaryMode || nibble); // second req only if not (binary mode || second req already done)
              state <= ((binaryMode || nibble) ? nextState : StTxHex);
              bcToUart.data <= oclib_pkg::HexToAsciiNibble(tempData[3:0]);
            end
          end
        end // StTxHex

        StEnterThenTxHex : begin
          if (!bcToUart.valid) begin
            // we first enter here
            bcToUart.valid <= 1'b1;
            nibble <= 1'b0;
            bcToUart.data <= 8'h0d;
          end
          else begin
            // bcToUart.valid is set, this is not our first cycle in this state
            if (bcFromUart.ready) begin
              // first time here, nibble=0, we've just sent 'h0d (CR)
              // second time, nibble=1, we've just sent 'h0a (LF), and we need to leave
              nibble <= 1'b1;
              bcToUart.valid <= !nibble;
              bcToUart.data <= 8'h0a;
              state <= (nibble ? StTxHex : StEnterThenTxHex);
            end
          end
        end // StEnterThenTxHex

        StInfo : begin
          if (serialCounter >= 64) begin
            // and we are done sending
            state <= StPrompt;
          end
          else begin
            serialCounter <= (serialCounter + 'd1);
            tempData <= infoRomData;
            state <= (((serialCounter[1:0] == 'd0) && !binaryMode) ? StEnterThenTxHex : StTxHex);
            nextState <= StInfo;
          end // else: !if(serialCounter >= 16)
        end // StInfo

        StTimers : begin
          if (serialCounter >= 16) begin
            // and we are done sending
            state <= StPrompt;
          end
          else begin
            serialCounter <= (serialCounter + 'd1);
            tempData <= timerByte;
            state <= (((serialCounter[1:0] == 'd0) && !binaryMode) ? StEnterThenTxHex : StTxHex);
            nextState <= StTimers;
          end // else: !if(serialCounter >= 16)
        end // StTimers

        StBcMsg : begin
          // arriving in here, we have gotten a length, it's in tempData, serialCounter is zero
          serialCounter <= tempData;
          state <= StBcMsgCopy2; // start by sending length byte, which is included in the length count
          messageMode <= 1'b1;
        end // StBcMsg

        StBcMsgCopy : begin
          // arriving in here, serial counter tells us how many more bytes to copy to channel
          if (serialCounter == 'd0) begin
            // no more, switch to receive mode
            state <= StBcMsgReceive;
          end
          else begin
            // go fetch a byte, and when we have it, go to StBcMsgCopy2
            state <= StRxHex;
            nextState <= StBcMsgCopy2;
          end
        end // StBcMsgCopy

        StBcMsgCopy2 : begin
          // arriving in here, we've just received a byte in tempData
          if (!bcIntOut.valid) begin
            // we haven't sent it to the outbound byte channel yet
            bcIntOut.valid <= 1'b1;
            bcIntOut.data <= tempData;
          end
          else begin
            // we have sent it
            if (bcIntIn.ready) begin
              // and it's being received
              serialCounter <= (serialCounter - 'd1);
              state <= StBcMsgCopy;
            end
            else begin
              // keep requesting it, these outputs are forced hard to zero above
              bcIntOut.valid <= 1'b1;
              bcIntOut.data <= bcIntOut.data;
            end
          end
        end // StBcMsgCopy2

        StBcMsgReceive : begin
          // arriving in here, we stream data back from channel under user breaks connection
          messageMode <= 1'b0; // we no longer need to abort outbound messages
          if (bcIntIn.valid) begin
            // got a byte from the channel, send to UART
            bcIntOut.ready <= 1'b1;
            state <= StTxHex;
            tempData <= bcIntIn.data;
            nextState <= StBcMsgReceive;
          end
          else if (bcFromUart.valid) begin
            // ok we've gotten something from user
            if ((bcFromUart.data == 8'h0a) || (bcFromUart.data == 8'h0d)) begin
              // got an enter, ack by sending prompt again
              state <= StPrompt;
            end
            else if (bcFromUart.data == 8'h03) begin // Control-C, ack and return to prompt
              serialCounter <= SerialRomCtrlC;
              state <= StTxRom;
              nextState <= StPrompt;
            end
            else begin
              state <= StSyntaxError;
            end
          end
        end // StBcMsgReceive

        StBcMsgAbort : begin
          // before jumping into this state, serialCounter needs to be set to something LONGER than the
          // valid remaining length of the serial message, to properly resync the receiver
          if (serialCounter == 'd0) begin
            // we are done, nibble was set coming in to tell us there was a control-C
            if (nibble) begin
              serialCounter <= SerialRomCtrlC;
              state <= StTxRom;
              nextState <= StPrompt;
            end
            else begin
              state <= StSyntaxError;
            end
          end
          else begin
            // we have to clear out the message
            if (bcToUart.valid) begin
              if (bcFromUart.ready) begin
                serialCounter <= serialCounter - 'd1;
                bcToUart.valid <= 1'b0;
              end
            end
            else begin
              bcToUart.valid <= 1'b1;
            end
          end
          bcToUart.data <= oclib_pkg::SyncChar;
        end // StBcMsgAbort

      endcase // case (state)
    end // else: !if(resetQ)
  end // always @ (posedge clock)



  // **************************
  // DEBUG LOGIC
  // **************************

`ifdef OC_UART_CONTROL_INCLUDE_VIO_DEBUG
  `OC_DEBUG_VIO(uVIO, clock, 32, 32,
                { resetQ, inComment,        // 2
                  bcFromUart, bcToUart,     // 16
                  serialCounter,            // 8
                  state },                  // 4
                { vioReset });         // 1
`else
  assign vioReset = '0;
`endif


`ifdef OC_UART_CONTROL_INCLUDE_ILA_DEBUG
  logic uartRxSync, uartTxSync;
  oclib_synchronizer uILA_RX_SYNC (.clock(clock), .in(uartRx), .out(uartRxSync));
  oclib_synchronizer uILA_TX_SYNC (.clock(clock), .in(uartTx), .out(uartTxSync));
  `OC_DEBUG_ILA(uILA, clock, 8192, 128, 32,
                { uartError,
                  resetQ, inComment,
                  resetOut, resetCount,
                  bcFromUart, bcToUart,
                  serialCounter,
                  state, nextState },
                { (|uartError),
                  uartRxSync, uartTxSync,
                  resetOut, resetQ, blink,
                  bcFromUart, state });
`endif


endmodule // oc_uart_control
