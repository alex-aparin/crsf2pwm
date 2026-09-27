`timescale 1ns/1ps
`default_nettype none

// tb_top
// End-to-end test: CRSF bytes on rx, pulse widths on the outputs.

module tb_top;

  localparam int  CLK_HZ = 50_000_000;
  localparam int  BAUD   = 420_000;
  localparam real BIT_NS = 1e9 / BAUD;   // 2380.95 ns

  logic clk = 0;
  always #10 clk = ~clk;                 // 50 MHz

  logic rx = 1;                          // UART idle
  logic steer, throttle;

  crsf2pwm_top #(
    .CLK_HZ (CLK_HZ),
    .BAUD   (BAUD)
  ) dut (
    .clk      (clk),
    .rx       (rx),
    .steer    (steer),
    .throttle (throttle)
  );

  // TODO: task send_byte   - start bit, 8 data bits LSB first, stop bit, BIT_NS each
  // TODO: task send_frame  - address, length, type, 22 payload bytes, CRC8
  // TODO: task measure     - pulse width from $realtime between edges
  // TODO: scenarios: extreme values, corrupted CRC, foreign frame type, failsafe

  initial begin
    $dumpfile("build/tb_top.vcd");
    $dumpvars(0, tb_top);

    #1_000_000;                          // 1 ms
    $display("tb_top: done");
    $finish;
  end

endmodule

`default_nettype wire
