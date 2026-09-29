`timescale 1ns/1ps
`default_nettype none

// pwm_timebase
// Shared time reference for the servo outputs: the 0.625 us tick and the
// 20 ms period counter, plus the two things every channel needs from them.
//
//   tick   one-clock enable, 1.6 MHz on average. One tick is one CRSF unit
//          of pulse width, see docs/servo_pwm.md.
//   start  high in the clock of the tick that wraps the counter, i.e. the
//          last clock of a period. Channels load their registers on it and
//          the top level counts periods with it.
//   head   high while cnt < 1408: the first 880 us of every period, which
//          is part of every pulse whatever the value. Set and cleared on the
//          same tick conditions as start, so the two are aligned.
//
// The tick comes from a fractional divider. At 50 MHz one tick is 31.25
// clocks, which no integer counter can do; an accumulator adds 8 every
// clock modulo 250 and emits a tick on every wrap, 50 MHz * 8 / 250 =
// 1.6 MHz. Ticks are 32, 31, 31, 31 clocks apart and the average is exact
// over every 125 clocks. Width jitter is one clock, 20 ns.
//
// The tick is not a clock. Everything runs on clk; tick is an enable.

module pwm_timebase #(
  parameter int CLK_HZ = 50_000_000
) (
  input  wire  clk,
  output logic tick,
  output logic start,
  output logic head
);

  // 1.6 MHz = 8 * 200 kHz, so ACC_MOD = CLK_HZ / 200 kHz: 250 at 50 MHz,
  // 240 at 48 MHz. CLK_HZ has to be a multiple of 200 kHz.
  localparam int ACC_STEP = 8;
  localparam int ACC_MOD  = CLK_HZ / 200_000;
  localparam int ACC_W    = $clog2(ACC_MOD);

  localparam int PERIOD_TICKS = 32_000;   // 20 ms
  localparam int HEAD_TICKS   = 1408;     // 880 us, the pulse width at value 0
  localparam int CNT_W        = $clog2(PERIOD_TICKS);

  // Constants sized to their registers, so no expression mixes widths.
  localparam logic [ACC_W-1:0] ACC_STEP_V  = ACC_W'(ACC_STEP);
  localparam logic [ACC_W-1:0] ACC_LAST    = ACC_W'(ACC_MOD - ACC_STEP);
  localparam logic [CNT_W-1:0] CNT_ONE     = CNT_W'(1);
  localparam logic [CNT_W-1:0] PERIOD_LAST = CNT_W'(PERIOD_TICKS - 1);
  localparam logic [CNT_W-1:0] HEAD_LAST   = CNT_W'(HEAD_TICKS - 1);

  logic [ACC_W-1:0] acc    = '0;
  logic             tick_q = 1'b0;
  logic [CNT_W-1:0] cnt    = '0;
  logic             head_q = 1'b1;     // cnt starts at 0, inside the head

  assign tick  = tick_q;
  assign start = tick_q && (cnt == PERIOD_LAST);
  assign head  = head_q;

  // Fractional divider. Compare before adding: acc + ACC_STEP would not fit.
  always_ff @(posedge clk) begin
    if (acc >= ACC_LAST) begin
      acc    <= acc - ACC_LAST;        // same as acc + ACC_STEP - ACC_MOD
      tick_q <= 1'b1;
    end else begin
      acc    <= acc + ACC_STEP_V;
      tick_q <= 1'b0;
    end
  end

  // Period counter, one step per tick, 0 .. PERIOD_LAST.
  always_ff @(posedge clk) begin
    if (tick_q) begin
      if (cnt == PERIOD_LAST) cnt <= '0;
      else                    cnt <= cnt + CNT_ONE;
    end
  end

  // Head flag: set with the wrap, cleared 1408 ticks later.
  always_ff @(posedge clk) begin
    if (tick_q && cnt == PERIOD_LAST)    head_q <= 1'b1;
    else if (tick_q && cnt == HEAD_LAST) head_q <= 1'b0;
  end

endmodule

`default_nettype wire
