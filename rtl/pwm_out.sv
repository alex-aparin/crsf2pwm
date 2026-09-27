`timescale 1ns/1ps
`default_nettype none

// pwm_out
// Servo pulse: 20 ms period, 988..2012 us pulse width.
//
// Mapping from CRSF: us = (value - 992) * 5 / 8 + 1500.
// A convenient way to avoid a multiplier: use a 0.625 us tick (1.6 MHz),
// then width in ticks = value + 1408 and the period is 32000 ticks.
// 1.6 MHz from 50 MHz: accumulator modulo 250 with step 8.
//
// Apply a new value only at the start of a period.
// With enable = 0 no pulses are produced (failsafe).

module pwm_out #(
  parameter int CLK_HZ = 50_000_000
) (
  input  wire         clk,
  input  wire  [10:0] value,    // 172..1811
  input  wire         enable,
  output logic        pwm
);

  // TODO

endmodule

`default_nettype wire
