`timescale 1ns/1ps
`default_nettype none

// pwm_out
// One complete servo output: a timebase of its own plus one channel.
// 20 ms period, 988..2012 us pulse width for value 172..1811, and any
// 0..2047 gives 880..2159 us. See docs/servo_pwm.md for what the servo and
// the ESC expect, pwm_timebase.sv for the tick and pwm_chan.sv for the
// pulse itself.
//
// This is the module tb_pwm_out tests and the one to use for a single
// output. crsf2pwm_top does not instantiate it: its two outputs share one
// pwm_timebase and use pwm_chan directly, which saves about 40 LEs on the
// EPM240.

module pwm_out #(
  parameter int CLK_HZ = 50_000_000
) (
  input  wire         clk,
  input  wire  [10:0] value,    // CRSF channel value
  input  wire         enable,   // 0: no pulses from the next period on
  output logic        pwm
);

  logic tick, start, head;

  pwm_timebase #(
    .CLK_HZ (CLK_HZ)
  ) u_timebase (
    .clk   (clk),
    .tick  (tick),
    .start (start),
    .head  (head)
  );

  pwm_chan u_chan (
    .clk    (clk),
    .tick   (tick),
    .start  (start),
    .head   (head),
    .value  (value),
    .enable (enable),
    .pwm    (pwm)
  );

endmodule

`default_nettype wire
