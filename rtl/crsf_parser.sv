`timescale 1ns/1ps
`default_nettype none

// crsf_parser
// Parses the CRSF byte stream and extracts two channels from the
// RC channels frame (type 0x16).
//
// Frame: [0xC8] [len] [type] [payload] [CRC8], len = bytes after the
// length field. RC frame: len 0x18, type 0x16, 22 payload bytes holding
// 16 channels of 11 bits back to back, LSB first. CRC over type + payload.
//
// ch_a and ch_b update together, in the clock of the frame_valid strobe,
// and only if the CRC matched. While a frame is being received the bits
// go into shadow registers, so a bad frame never shows on the outputs.
// Frames of other types, other lengths and other addresses are consumed
// and ignored.
//
// Recovery. A frame that stops short (receiver reset, cable glitch) would
// otherwise swallow the next frame as its payload and only fail at the
// CRC. So any silence of GAP_US inside a frame aborts it; bytes inside a
// frame come back to back from the receiver's UART, frames are at least
// 1.4 ms apart. A length outside 2..62 is not a frame either. In both cases
// the parser goes back to waiting for 0xC8.
//
// Channel extraction costs no shifting logic: which payload byte and bit
// carries which channel bit is fixed by the CH_A / CH_B parameters, so
// each shadow bit has a constant byte number to wait for. Payload byte b
// arrives when the down counter `remaining` equals 23 - b.

module crsf_parser #(
  parameter int CH_A   = 0,           // CRSF channel 0..15 for ch_a
  parameter int CH_B   = 1,           // CRSF channel 0..15 for ch_b
  parameter int CLK_HZ = 50_000_000,
  parameter int GAP_US = 100          // silence inside a frame that aborts it
) (
  input  wire         clk,
  input  wire  [7:0]  byte_in,
  input  wire         byte_valid,
  output logic [10:0] ch_a,
  output logic [10:0] ch_b,
  output logic        frame_valid   // one-clock strobe
);

  localparam logic [7:0] ADDR_FC = 8'hC8;
  localparam logic [7:0] TYPE_RC = 8'h16;
  localparam logic [5:0] LEN_RC  = 6'd24;
  localparam logic [7:0] LEN_MIN = 8'd2;    // type + CRC, nothing else
  localparam logic [7:0] LEN_MAX = 8'd62;

  localparam int GAP_CLKS = CLK_HZ / 1_000_000 * GAP_US;
  localparam int GAP_W    = $clog2(GAP_CLKS);
  localparam logic [GAP_W-1:0] GAP_ONE  = GAP_W'(1);
  localparam logic [GAP_W-1:0] GAP_LAST = GAP_W'(GAP_CLKS - 1);

  typedef enum logic [1:0] {S_SYNC, S_LEN, S_TYPE, S_BODY} state_t;

  state_t           state     = S_SYNC;
  logic [5:0]       remaining = '0;      // bytes of the frame still to come, this one included
  logic             is_rc     = 1'b0;    // current frame is an RC frame of the right length
  logic [GAP_W-1:0] gap       = '0;
  logic [10:0]      sh_a      = '0;      // shadows, filled while receiving
  logic [10:0]      sh_b      = '0;
  logic [10:0]      ch_a_q    = 11'd992;
  logic [10:0]      ch_b_q    = 11'd992;
  logic             fv_q      = 1'b0;
  logic [7:0]       crc;

  logic len_ok, last_byte, timeout;

  assign ch_a        = ch_a_q;
  assign ch_b        = ch_b_q;
  assign frame_valid = fv_q;

  assign len_ok    = (byte_in >= LEN_MIN) && (byte_in <= LEN_MAX);
  assign last_byte = (remaining == 6'd1);
  assign timeout   = (gap == GAP_LAST);

  // CRC over type and payload: cleared by the length byte, fed every byte
  // up to and excluding the CRC byte, compared against the CRC byte.
  crc8 u_crc (
    .clk   (clk),
    .clear (byte_valid && state == S_LEN && len_ok),
    .data  (byte_in),
    .valid (byte_valid && (state == S_TYPE || (state == S_BODY && !last_byte))),
    .crc   (crc)
  );

  // Silence counter, only runs inside a frame.
  always_ff @(posedge clk) begin
    if (byte_valid || state == S_SYNC) gap <= '0;
    else if (!timeout)                 gap <= gap + GAP_ONE;
  end

  // Frame state machine.
  always_ff @(posedge clk) begin
    fv_q <= 1'b0;

    if (timeout) begin
      state <= S_SYNC;
    end else if (byte_valid) begin
      case (state)
        S_SYNC: begin
          if (byte_in == ADDR_FC) state <= S_LEN;
        end

        S_LEN: begin
          if (len_ok) begin
            remaining <= byte_in[5:0];
            state     <= S_TYPE;
          end else if (byte_in != ADDR_FC) begin
            state <= S_SYNC;              // 0xC8 again: treat it as the sync byte
          end
        end

        S_TYPE: begin
          is_rc     <= (byte_in == TYPE_RC) && (remaining == LEN_RC);
          remaining <= remaining - 6'd1;
          state     <= S_BODY;
        end

        S_BODY: begin
          if (last_byte) begin
            if (is_rc && crc == byte_in) begin
              ch_a_q <= sh_a;
              ch_b_q <= sh_b;
              fv_q   <= 1'b1;
            end
            state <= S_SYNC;
          end else begin
            remaining <= remaining - 6'd1;
          end
        end

        default: state <= S_SYNC;
      endcase
    end
  end

  // Channel bit map. Channel c is payload bits 11c .. 11c+10, payload bit p
  // is bit p % 8 of payload byte p / 8, and payload byte b is on byte_in
  // when remaining == 23 - b. hit_x[j] says "byte_in carries shadow bit j
  // right now", src_x[j] is that bit.
  logic [10:0] src_a, hit_a, src_b, hit_b;
  genvar j;                        // Quartus wants it declared outside the loop

  generate
    for (j = 0; j < 11; j++) begin : g_map
      localparam int PA = 11 * CH_A + j;
      localparam int PB = 11 * CH_B + j;
      localparam logic [5:0] RA = 6'(23 - PA / 8);
      localparam logic [5:0] RB = 6'(23 - PB / 8);
      assign src_a[j] = byte_in[PA % 8];
      assign hit_a[j] = (remaining == RA);
      assign src_b[j] = byte_in[PB % 8];
      assign hit_b[j] = (remaining == RB);
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (byte_valid && state == S_BODY && is_rc) begin
      sh_a <= (sh_a & ~hit_a) | (src_a & hit_a);
      sh_b <= (sh_b & ~hit_b) | (src_b & hit_b);
    end
  end

endmodule

`default_nettype wire
