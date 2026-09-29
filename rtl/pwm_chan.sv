`timescale 1ns/1ps
`default_nettype none

// pwm_chan
// One servo output on the shared pwm_timebase.
//
// A pulse is the head phase, 1408 ticks common to all channels, followed
// by `value` more ticks counted by a private down counter that is loaded
// at the start of the period. Width = 1408 + value ticks of 0.625 us,
// which is (value - 992) * 5 / 8 + 1500 us. No adder and no magnitude
// comparator per channel: a 12-bit width latch plus a 15-bit comparator
// would cost about twice the LEs of this counter.
//
// value and enable are sampled once per period, on start. A new CRSF
// frame in the middle of a period can neither cut the running pulse short
// nor start a second one, and enable = 0 stops the pulses from the next
// period on, never in the middle of one.
//
// Timing: both edges of pwm are two clocks after the tick that causes
// them, so the width is exact to the tick.

module pwm_chan (
  input  wire        clk,
  input  wire        tick,
  input  wire        start,
  input  wire        head,
  input  wire [10:0] value,    // CRSF channel, 172..1811 nominal, any 0..2047 works
  input  wire        enable,
  output logic       pwm
);

  logic [10:0] down  = '0;
  logic        en_q  = 1'b0;
  logic        pwm_q = 1'b0;

  assign pwm = pwm_q;

  always_ff @(posedge clk) begin
    if (start) begin
      down <= value;
      en_q <= enable;
    end else if (tick && !head && down != '0) begin
      down <= down - 11'd1;
    end

    pwm_q <= en_q && (head || down != '0);
  end

endmodule

`default_nettype wire
