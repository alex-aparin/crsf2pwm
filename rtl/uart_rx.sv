`timescale 1ns/1ps
`default_nettype none

// uart_rx
// UART receiver, 8N1. The rx input must already be synchronized to clk.
//
// Idea: wait for a falling edge on rx (start bit), count one and a half
// bit periods, then sample one bit every bit period, LSB first.
// Bit period in clocks: CLK_HZ / BAUD (119 for 50 MHz and 420 kbaud).

module uart_rx #(
  parameter int CLK_HZ = 50_000_000,
  parameter int BAUD   = 420_000
) (
  input  wire        clk,
  input  wire        rx,
  output logic [7:0] data,       // received byte
  output logic       valid,      // one-clock strobe: data is ready
  output logic       frame_err   // stop bit was low
);

  localparam int CLKS_PER_BIT = CLK_HZ / BAUD;

  // TODO

endmodule

`default_nettype wire
