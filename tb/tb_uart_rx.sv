`timescale 1ns/1ps
`default_nettype none

// tb_uart_rx
// Standalone test for the UART receiver.

module tb_uart_rx;

  localparam int  CLK_HZ = 50_000_000;
  localparam int  BAUD   = 420_000;
  localparam real BIT_NS = 1e9 / BAUD;

  logic clk = 0;
  always #10 clk = ~clk;

  logic       rx = 1;
  logic [7:0] data;
  logic       valid, frame_err;

  uart_rx #(
    .CLK_HZ (CLK_HZ),
    .BAUD   (BAUD)
  ) dut (
    .clk       (clk),
    .rx        (rx),
    .data      (data),
    .valid     (valid),
    .frame_err (frame_err)
  );

  // TODO: task send_byte
  // TODO: check 0x00, 0xFF, 0x55, 0xAA, back-to-back bytes with no gap,
  //       3 percent baud rate mismatch, false start bit

  initial begin
    $dumpfile("build/tb_uart_rx.vcd");
    $dumpvars(0, tb_uart_rx);

    #100_000;
    $display("tb_uart_rx: done");
    $finish;
  end

endmodule

`default_nettype wire
