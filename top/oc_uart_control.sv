
// SPDX-License-Identifier: MPL-2.0

`include "lib/oclib_defines.vh"
`include "lib/oclib_pkg.sv"
`include "lib/oclib_uart_pkg.sv"

module oc_uart_control
  #(
    parameter integer ClockHz = 100_000_000,
    parameter integer Baud = 115_200,
    parameter         type BcType = oclib_pkg::bc_8b_bidi_s,
    parameter integer ErrorWidth = oclib_uart_pkg::ErrorWidth,
    parameter integer ManagerReset = `OC_VAL_ASDEFINED_ELSE(TARGET_MANAGER_RESET, 1),
    parameter integer ManagerResetByte = `OC_VAL_ASDEFINED_ELSE(TARGET_MANAGER_RESET_BYTE, "!"),
    parameter integer ManagerResetLength = `OC_VAL_ASDEFINED_ELSE(TARGET_MANAGER_RESET_LENGTH, 64),
    parameter bit     ResetSync = 1
    )
  (
   input                         clock,
   input                         reset,
   output logic                  resetOut,
   output logic [ErrorWidth-1:0] uartError,
   input                         uartRx,
   output logic                  uartTx,
   output logic                  blink
//   input               BcType bcTx,
//   output              BcType bcRx
   );

  logic                         vioReset;
  logic                         resetQ;

  oclib_synchronizer #(.Enable(ResetSync))
  uRESET_SYNC (.clock(clock), .in(reset || vioReset), .out(resetQ));

  // Philosophy here is to not backpressure the RX channel.  We dont want to block attempts to
  // reset or resync, and you cannot overrun the RX state machine when following the protocol.

  BcType bcRx, bcTx;

  oclib_uart #(.ClockHz(ClockHz), .Baud(Baud), .BcType(BcType))
  uUART (.clock(clock), .reset(resetQ), .error(uartError),
         .rx(uartRx), .tx(uartTx),
         .bcOut(bcRx), .bcIn(bcTx));

  oclib_pkg::bc_8b_bidi_s bcFromUart, bcToUart;

  oclib_bc_bidi_adapter #(.BcTypeA(BcType), .BcTypeB(oclib_pkg::bc_8b_bidi_s))
  uBC_ADAPTER (.clock(clock), .reset(resetQ),
               .aIn(bcRx), .aOut(bcTx),
               .bOut(bcFromUart), .bIn(bcToUart));

  oclib_pulse_stretcher #(.Cycles(ClockHz))
  uSTRETCH(.clock(clock), .reset(resetQ),
           .in(bcToUart.valid), .out(blink));

  // **************************
  // SERIAL ROM
  // **************************

  localparam integer            SerialRomBanner = 0;
  localparam integer            SerialRomPrompt = (SerialRomBanner+13);
  localparam integer            SerialRomCtrlC = (SerialRomPrompt+6);
  localparam integer            SerialRomError = (SerialRomCtrlC+8);

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
      (SerialRomPrompt+ 0) : syntaxRomData = 'h0d;
      (SerialRomPrompt+ 1) : syntaxRomData = 'h0a;
      (SerialRomPrompt+ 2) : syntaxRomData = "O";
      (SerialRomPrompt+ 3) : syntaxRomData = "C";
      (SerialRomPrompt+ 4) : syntaxRomData = ">";
      (SerialRomPrompt+ 5) : syntaxRomData = 'h00;
      (SerialRomCtrlC + 0) : syntaxRomData = "^";
      (SerialRomCtrlC + 1) : syntaxRomData = "C";
      (SerialRomCtrlC + 2) : syntaxRomData = 'h0d;
      (SerialRomCtrlC + 3) : syntaxRomData = 'h0a;
      (SerialRomCtrlC + 4) : syntaxRomData = "O";
      (SerialRomCtrlC + 5) : syntaxRomData = "C";
      (SerialRomCtrlC + 6) : syntaxRomData = ">";
      (SerialRomCtrlC + 7) : syntaxRomData = 'h00;
      (SerialRomError + 0) : syntaxRomData = 'h0d;
      (SerialRomError + 1) : syntaxRomData = 'h0a;
      (SerialRomError + 2) : syntaxRomData = "E";
      (SerialRomError + 3) : syntaxRomData = "R";
      (SerialRomError + 4) : syntaxRomData = "R";
      (SerialRomError + 5) : syntaxRomData = "O";
      (SerialRomError + 6) : syntaxRomData = "R";
      (SerialRomError + 7) : syntaxRomData = 'h0d;
      (SerialRomError + 8) : syntaxRomData = 'h0a;
      (SerialRomError + 9) : syntaxRomData = 'h00;
      default : syntaxRomData = '0;
    endcase // case (counter[5:0])
  end

  // **************************
  // HARDWARE SERIAL CONSOLE
  // **************************

  enum logic [3:0] { StReset = 0, StPrompt = 1,
                     StWaitForEnter = 2, StSyntaxError = 3, StSyntaxError2 = 4,
                     StInfo = 5, StRead = 6, StWrite = 7,
                     StTxRom = 8, StTxHex = 9, StRxHex = 10} state, nextState;

  logic       inComment;

  always @(posedge clock) begin
    bcToUart.ready <= 1'b1; // always true, but tools get buggy when struct fields set in different ways
    if (resetQ) begin
      state <= StReset;
      nextState <= StReset;
      serialCounter <= '0;
      bcToUart.valid <= 1'b0;
      bcToUart.data <= '0;
      inComment <= 1'b0;
    end
    else begin
      if (bcFromUart.ready) begin
        bcToUart.valid <= 1'b0;
      end
      case (state)

        StReset : begin
          serialCounter <= SerialRomBanner;
          state <= StTxRom;
          nextState <= StPrompt;
        end // case: StReset

        StPrompt : begin
          // In this state, we've just had the prompt printed, and we're waiting for a command
          if (bcFromUart.valid) begin
            if (bcFromUart.data == "i") begin
              // info dump, if compiled in, wait for enter to confirm
              state <= StWaitForEnter;
              nextState <= StInfo;
            end
            else if ((bcFromUart.data == 8'h0a) || (bcFromUart.data == 8'h0d)) begin
              // got an enter, ack by sending prompt again
              serialCounter <= SerialRomPrompt;
              state <= StTxRom;
              nextState <= StPrompt;
            end
            else if (bcFromUart.data == 8'h03) begin // Control-C, ack and return to prompt
              serialCounter <= SerialRomCtrlC;
              state <= StTxRom;
              nextState <= StPrompt;
            end
            else begin
              state <= StSyntaxError;
              // didn't understand, go to syntax error state
              serialCounter <= bcFromUart.data;
            end
          end
          inComment <= 1'b0;
        end // case: StPrompt

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
              serialCounter <= bcFromUart.data;
            end
          end
        end // case: StWaitForEnter

        StSyntaxError : begin
          // What we're doing here is waiting to tell user there's an error.  It feels rude to just jump to
          // printing SYNTAX ERROR while they are typing, it's not the way terminals work.  Perhaps one day
          // we'll give the user the ability to correct mistakes :) and it REALLY makes sense to wait for
          // enter.  But for now, once we see something we don't like, we jump to this state and let their
          // local echo show them what they've been typing, without interruption, then when they hit enter
          // we will inform them of the error.
          if (bcFromUart.valid) begin
            if ((bcFromUart.data == 8'h0a) || (bcFromUart.data == 8'h0d)) begin
              serialCounter <= SerialRomError;
              state <= StTxRom;
              nextState <= StSyntaxError2;
            end
          end
        end // case: StSyntaxError

        StSyntaxError2 : begin
          // This state just exists to kick off sending ">" prompt again after the "ERROR"
          serialCounter <= SerialRomPrompt;
          state <= StTxRom;
          nextState <= StPrompt;
        end // case: StSyntaxError2

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

      endcase // case (state)
    end // else: !if(resetQ)
  end // always @ (posedge clock)

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
          resetCount <= ((bcFromUart.data == ManagerResetByte) ? (resetCount + 'd1) : '0);
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

`ifdef OC_UART_CONTROL_INCLUDE_VIO_DEBUG
  `OC_DEBUG_VIO(uVIO, clock, 32, 32,
                { resetQ, blink, inComment, // 3
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
                { resetQ, blink, inComment,
                  resetOut, resetCount,
                  bcFromUart, bcToUart,
                  serialCounter,
                  state, nextState },
                { uartRxSync, uartTxSync,
                  resetOut, resetQ, blink,
                  bcFromUart, state });
`endif


endmodule // oc_uart_control
