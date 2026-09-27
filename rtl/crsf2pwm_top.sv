`timescale 1ns/1ps
`default_nettype none

// crsf2pwm_top
// Top level: CRSF over UART in, two servo PWM signals out.
//
// Planned structure:
//   rx -> synchronizer (2 flip-flops) -> uart_rx -> crsf_parser -> pwm_out x2
//   plus a failsafe watchdog: no valid frame for ~0.5 s
//   drops enable on both pwm_out instances.

module crsf2pwm_top #(
  parameter int CLK_HZ      = 50_000_000,  // board oscillator
  parameter int BAUD        = 420_000,     // CRSF default
  parameter int STEER_CH    = 0,           // CRSF channel for steering
  parameter int THROTTLE_CH = 1            // CRSF channel for throttle
) (
  input  wire  clk,       // 50 MHz
  input  wire  rx,        // CRSF from the receiver, 3.3 V, idle high
  output logic steer,     // PWM to the steering servo
  output logic throttle   // PWM to the motor ESC
);

  // TODO: rx synchronizer

  // TODO: uart_rx

  // TODO: crsf_parser

  // TODO: failsafe

  // TODO: pwm_out for steer and throttle

endmodule

`default_nettype wire
