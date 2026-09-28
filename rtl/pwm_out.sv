`timescale 1ns/1ps
`default_nettype none

// pwm_out
// Servo pulse: 20 ms period, 988..2012 us pulse width for value 172..1811.
// See docs/servo_pwm.md for what the servo and the ESC expect.
//
// Mapping from CRSF: us = (value - 992) * 5 / 8 + 1500.
// One CRSF unit is 5/8 us = 0.625 us, so the module counts time in 0.625 us
// ticks (1.6 MHz). Then width in ticks = value + 1408 and the period is
// 32000 ticks: one adder and one comparator, no multiplier.
//
// The 1.6 MHz tick is not a clock. Everything runs on clk; tick is a
// one-clock enable from a fractional divider (accumulator). At 50 MHz one
// tick is 31.25 clocks, so ticks come 32, 31, 31, 31 clocks apart and the
// average is exact. Width jitter is one clk, 20 ns.
//
// value and enable are sampled once per period, in the clock the counter
// wraps. The comparator only ever sees the latched copies, so a pulse is
// never cut short or retriggered when a new CRSF frame arrives mid-period.
// With enable = 0 the output stays low from the next period on.
//
// No reset. Registers start from their declared initial values, which is
// also the MAX II power-up state (all zeros, width is loaded before use).
//
// Constants are declared with the width of the register they are used
// with, so no expression mixes widths and nothing is truncated on
// assignment: Quartus and Verilator report both as warnings.

module pwm_out #(
  parameter int CLK_HZ = 50_000_000
) (
  input  wire         clk,
  input  wire  [10:0] value,    // CRSF channel, 172..1811 nominal, any 0..2047 works
  input  wire         enable,
  output logic        pwm
);

  // Tick generator: f_tick = CLK_HZ * ACC_STEP / ACC_MOD = 1.6 MHz.
  // 1.6 MHz = 8 * 200 kHz, so ACC_MOD = CLK_HZ / 200 kHz: 250 at 50 MHz,
  // 240 at 48 MHz. CLK_HZ has to be a multiple of 200 kHz.
  localparam int ACC_STEP = 8;
  localparam int ACC_MOD  = CLK_HZ / 200_000;
  localparam int ACC_W    = $clog2(ACC_MOD);

  // Period and the value-to-ticks offset. 1500 us is 2400 ticks and
  // belongs to value 992, so width = value + (2400 - 992).
  // Largest width: 2047 + 1408 = 3455, needs 12 bits.
  localparam int PERIOD_TICKS = 32_000;
  localparam int CNT_W        = $clog2(PERIOD_TICKS);
  localparam int WIDTH_OFFSET = 2400 - 992;
  localparam int WIDTH_W      = $clog2(2047 + WIDTH_OFFSET + 1);

  // The same constants sized to their registers.
  localparam logic [ACC_W-1:0]   ACC_STEP_V     = ACC_STEP;
  localparam logic [ACC_W-1:0]   ACC_LAST       = ACC_MOD - ACC_STEP;
  localparam logic [CNT_W-1:0]   CNT_ONE        = 1;
  localparam logic [CNT_W-1:0]   PERIOD_LAST    = PERIOD_TICKS - 1;
  localparam logic [WIDTH_W-1:0] WIDTH_OFFSET_V = WIDTH_OFFSET;
  localparam logic [WIDTH_W-1:0] WIDTH_NEUTRAL  = 992 + WIDTH_OFFSET;

  logic [ACC_W-1:0]   acc   = '0;
  logic               tick  = 1'b0;
  logic [CNT_W-1:0]   cnt   = '0;
  logic [WIDTH_W-1:0] width = WIDTH_NEUTRAL;   // until the first latch
  logic               en_q  = 1'b0;
  logic               pwm_q = 1'b0;

  // 1. Fractional divider. acc holds the fractional part of a tick in
  //    units of 1/ACC_MOD; every clock adds ACC_STEP, every wrap is a tick.
  //    Compare before adding: acc + ACC_STEP would not fit into ACC_W bits.
  always_ff @(posedge clk) begin
    if (acc >= ACC_LAST) begin
      acc  <= acc - ACC_LAST;          // same as acc + ACC_STEP - ACC_MOD
      tick <= 1'b1;
    end else begin
      acc  <= acc + ACC_STEP_V;
      tick <= 1'b0;
    end
  end

  // 2. Period counter, one step per tick, 0 .. PERIOD_LAST.
  always_ff @(posedge clk) begin
    if (tick) begin
      if (cnt == PERIOD_LAST) cnt <= '0;
      else                    cnt <= cnt + CNT_ONE;
    end
  end

  // 3. Shadow registers, loaded in the clock the counter wraps to 0.
  //    From the next clock on the comparator works with the new width.
  always_ff @(posedge clk) begin
    if (tick && cnt == PERIOD_LAST) begin
      width <= {{(WIDTH_W - 11){1'b0}}, value} + WIDTH_OFFSET_V;
      en_q  <= enable;
    end
  end

  // 4. Comparator with a registered output: high for cnt = 0 .. width-1,
  //    exactly width ticks. The register keeps glitches off the pin.
  always_ff @(posedge clk) begin
    pwm_q <= en_q && (cnt < {{(CNT_W - WIDTH_W){1'b0}}, width});
  end

  assign pwm = pwm_q;

endmodule

`default_nettype wire
