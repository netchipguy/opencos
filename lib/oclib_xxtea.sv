
// SPDX-License-Identifier: MPL-2.0

module oclib_xxtea #(localparam integer      Words = 2 ) // hardcoded, only supports 64-bit input (2 words) so 32 rounds
  (
   input                           clock,
   input                           go,
   input [Words-1:0] [31:0]        in,
   input [3:0] [31:0]              key,
   output logic                    done,
   output logic [Words-1:0] [31:0] out
   );

  localparam logic [31:0]          Delta = 'h9e3779b9;
  localparam integer               Rounds = (6 + 52/Words);
  localparam logic [31:0]          InitialDecryptionSum = (Rounds * Delta);

  logic [4:0]                      round;
  logic                            phase;
  logic [31:0]                     sum;
  logic [1:0]                      e, p;

  assign e = sum[3:2];
  assign p = {1'b0,~phase}; // the for-loop, during decryption of 2-word block, only has one iteration with p=1

  always_ff @(posedge clock) begin
    if (go) begin
      if (!done) begin
        if (phase == 0) begin
          out[1] <= out[1] - ((((out[0]>>5)^(out[0]<<2)) + ((out[0]>>3)^(out[0]<<4))) ^ ((sum^out[0]) + (key[p^e] ^ out[0])));
        end else begin
          out[0] <= out[0] - ((((out[1]>>5)^(out[1]<<2)) + ((out[1]>>3)^(out[1]<<4))) ^ ((sum^out[1]) + (key[p^e] ^ out[1])));
          sum <= (sum - Delta);
        end
        done <= (round == (Rounds-1)) && phase;
        phase <= !phase;
        round <= (round + phase);
      end
    end
    else begin
      round <= '0;
      phase <= 1'b0;
      sum <= InitialDecryptionSum;
      done <= 1'b0;
      out <= in;
    end
  end

  /*
  // from https://en.wikipedia.org/wiki/XXTEA

  #include <stdint.h>
  #define DELTA 0x9e3779b9
  #define MX (((z>>5^y<<2) + (y>>3^z<<4)) ^ ((sum^y) + (key[(p&3)^e] ^ z)))

   void btea(uint32_t *v, int n, uint32_t const key[4]) {
    uint32_t y, z, sum;
    unsigned p, rounds, e;
    if (n > 1) {          // Coding Part
      rounds = 6 + 52/n;
      sum = 0;
      z = v[n-1];
      do {
        sum += DELTA;
        e = (sum >> 2) & 3;
        for (p=0; p<n-1; p++) {
          y = v[p+1];
          z = v[p] += MX;
        }
        y = v[0];
        z = v[n-1] += MX;
      } while (--rounds);
    } else if (n < -1) {  // Decoding Part
      n = -n;
      rounds = 6 + 52/n;
      sum = rounds*DELTA;
      y = v[0];
      do {
        e = (sum >> 2) & 3;
        for (p=n-1; p>0; p--) {
          z = v[p-1];
          y = v[p] -= MX;
        }
        z = v[n-1];
        y = v[0] -= MX;
        sum -= DELTA;
      } while (--rounds);
    }
  }
  */

endmodule // xxtea
