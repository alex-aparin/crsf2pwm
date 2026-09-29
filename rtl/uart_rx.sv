`timescale 1ns/1ps
`default_nettype none

// uart_rx
// UART receiver, 8N1, LSB first. rx must already be synchronised to clk
// (two flip-flops in the top level).
//
// A start bit is detected by level: the first clock with rx low in IDLE.
// The receiver then waits half a bit and checks that rx is still low; a
// shorter pulse is noise, not a start bit. From there it samples once per
// full bit period, which lands every sample in the middle of its bit. The
// stop bit is sampled the same way: high gives valid, low gives frame_err,
// and after an error the receiver waits for the line to return high so
// that a break condition produces one error instead of a stream of bytes.
//
// data is the shift register itself. It holds the byte in the valid clock
// and stays put until the first data bit of the next byte is shifted in,
// 1.5 bit periods after the next start bit. Consumers sample it on valid.
// A separate output register would cost eight more LEs.
//
// Tolerance: samples sit at 0.5, 1.5 .. 9.5 bit periods after the start
// edge, so a baud rate mismatch moves the last sample by 9.5 * error.
// +-3 % is 0.29 bit, well inside the +-0.5 bit window.

module uart_rx #(
  parameter int CLK_HZ = 50_000_000,
  parameter int BAUD   = 420_000
) (
  input  wire        clk,
  input  wire        rx,
  output logic [7:0] data,       // received byte, see above
  output logic       valid,      // one-clock strobe: data is a good byte
  output logic       frame_err   // one-clock strobe: stop bit was low, no valid
);

  localparam int CLKS_PER_BIT = CLK_HZ / BAUD;           // 119 at 50 MHz, 420 kbaud
  localparam int CNT_W        = $clog2(CLKS_PER_BIT);

  localparam logic [CNT_W-1:0] CNT_ONE   = 1;
  localparam logic [CNT_W-1:0] BIT_LAST  = CLKS_PER_BIT - 1;      // one bit period
  localparam logic [CNT_W-1:0] HALF_LAST = CLKS_PER_BIT / 2 - 1;  // half a bit period

  typedef enum logic [2:0] {S_IDLE, S_START, S_DATA, S_STOP, S_WAIT} state_t;

  state_t           state   = S_IDLE;
  logic [CNT_W-1:0] cnt     = '0;
  logic [2:0]       bit_idx = '0;
  logic [7:0]       shreg   = '0;
  logic             valid_q = 1'b0;
  logic             ferr_q  = 1'b0;

  assign data      = shreg;
  assign valid     = valid_q;
  assign frame_err = ferr_q;

  always_ff @(posedge clk) begin
    valid_q <= 1'b0;
    ferr_q  <= 1'b0;

    case (state)
      S_IDLE: begin
        if (!rx) begin
          state <= S_START;
          cnt   <= '0;
        end
      end

      // Half a bit after the falling edge. Still low: a real start bit.
      S_START: begin
        if (cnt == HALF_LAST) begin
          cnt <= '0;
          if (!rx) begin
            state   <= S_DATA;
            bit_idx <= '0;
          end else begin
            state <= S_IDLE;
          end
        end else begin
          cnt <= cnt + CNT_ONE;
        end
      end

      // One full bit later: middle of data bit 0, then 1, .. 7.
      S_DATA: begin
        if (cnt == BIT_LAST) begin
          cnt   <= '0;
          shreg <= {rx, shreg[7:1]};        // LSB arrives first, enters from the top
          if (bit_idx == 3'd7) state   <= S_STOP;
          else                 bit_idx <= bit_idx + 3'd1;
        end else begin
          cnt <= cnt + CNT_ONE;
        end
      end

      // Middle of the stop bit.
      S_STOP: begin
        if (cnt == BIT_LAST) begin
          if (rx) begin
            valid_q <= 1'b1;
            state   <= S_IDLE;
          end else begin
            ferr_q  <= 1'b1;
            state   <= S_WAIT;
          end
        end else begin
          cnt <= cnt + CNT_ONE;
        end
      end

      // After a bad stop bit: wait for the line to go idle.
      S_WAIT: begin
        if (rx) state <= S_IDLE;
      end

      default: state <= S_IDLE;
    endcase
  end

endmodule

`default_nettype wire
