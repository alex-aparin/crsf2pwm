`timescale 1ns/1ps
`default_nettype none

// tb_uart_rx
// Standalone test for the UART receiver, 8N1, 420 kbaud.
//
// The driver side is time based: send_byte toggles rx in nanoseconds, the
// way a real receiver would, knowing nothing about clk. The checking side
// is clock based: everything the testbench reads it reads on negedge clk,
// in the middle of the cycle, after the DUT's registers have settled.
//
// Contract checked here:
//   valid      one-clock strobe, data holds the byte in that clock
//   frame_err  one-clock strobe when the stop bit was low, no valid for
//              that byte, and one error per break however long it is

module tb_uart_rx;

  localparam int  CLK_HZ       = 50_000_000;
  localparam int  BAUD         = 420_000;
  localparam real BIT_NS       = 1e9 / BAUD;         // 2380.95 ns
  localparam int  CLKS_PER_BIT = CLK_HZ / BAUD;      // 119

  logic clk = 0;
  always #10 clk = ~clk;                             // 50 MHz

  logic       rx = 1;                                // UART idle is high
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

  int errors  = 0;
  int sent    = 0;      // bytes the DUT is expected to report
  int strobes = 0;      // valid strobes actually seen
  int ferrs   = 0;      // frame_err strobes actually seen

  // ---------------------------------------------------------------------
  // Passive monitor: counts strobes for the whole run and catches a valid
  // that lasts more than one clock, wherever in the test it happens.
  // ---------------------------------------------------------------------
  logic valid_q = 0;
  always @(posedge clk) begin
    if (valid)     strobes++;
    if (frame_err) ferrs++;
    if (valid && valid_q) begin
      errors++;
      $display("%t FAIL valid longer than one clock", $time);
    end
    valid_q <= valid;
  end

  // ---------------------------------------------------------------------
  // Drivers, time based.
  // ---------------------------------------------------------------------

  // One 8N1 byte: start, 8 data bits LSB first, stop. A bit_ns other than
  // BIT_NS models a baud rate mismatch between sender and receiver.
  task automatic send_byte(input logic [7:0] d, input real bit_ns);
    rx = 1'b0;                                       // start bit
    #(bit_ns);
    for (int i = 0; i < 8; i++) begin
      rx = d[i];
      #(bit_ns);
    end
    rx = 1'b1;                                       // stop bit
    #(bit_ns);
  endtask

  // A byte whose stop bit is low, then two bit times of idle.
  task automatic send_broken_byte(input logic [7:0] d);
    rx = 1'b0;
    #(BIT_NS);
    for (int i = 0; i < 8; i++) begin
      rx = d[i];
      #(BIT_NS);
    end
    rx = 1'b0;                                       // bad stop bit
    #(BIT_NS);
    rx = 1'b1;
    #(2 * BIT_NS);
  endtask

  // Line held low for `bits` bit times, then idle.
  task automatic send_break(input int bits);
    rx = 1'b0;
    #(bits * BIT_NS);
    rx = 1'b1;
    #(2 * BIT_NS);
  endtask

  // Short low pulse that is not a start bit.
  task automatic glitch(input real low_ns);
    rx = 1'b0;
    #(low_ns);
    rx = 1'b1;
  endtask

  // ---------------------------------------------------------------------
  // Checkers, clock based.
  // ---------------------------------------------------------------------

  // Wait up to max_cycles for valid, compare data, step past the strobe.
  task automatic expect_byte(input string what, input logic [7:0] exp, input int max_cycles);
    int n = 0;
    @(negedge clk);
    while (!valid && n < max_cycles) begin
      @(negedge clk);
      n++;
    end
    if (!valid) begin
      errors++;
      $display("%t FAIL %s: no valid within %0d cycles", $time, what, max_cycles);
    end else if (data !== exp) begin
      errors++;
      $display("%t FAIL %s: data %02h, expected %02h", $time, what, data, exp);
    end else begin
      $display("%t ok   %s: %02h", $time, what, data);
    end
    @(negedge clk);
  endtask

  // Send one byte and check it, in parallel: the strobe may come before
  // send_byte returns, so the checker has to be waiting already.
  task automatic send_and_expect(input string what, input logic [7:0] d, input real bit_ns);
    fork
      send_byte(d, bit_ns);
      expect_byte(what, d, 12 * CLKS_PER_BIT);
    join
    sent++;
  endtask

  // ---------------------------------------------------------------------
  // Scenario.
  // ---------------------------------------------------------------------
  initial begin
    int strobes_before, ferrs_before;

    $dumpfile("build/tb_uart_rx.vcd");
    $dumpvars(0, tb_uart_rx);

    #(3 * BIT_NS);                                   // idle line first

    // 1. single bytes with idle between them
    send_and_expect("single 0x00", 8'h00, BIT_NS);
    send_and_expect("single 0xFF", 8'hFF, BIT_NS);
    send_and_expect("single 0x55", 8'h55, BIT_NS);
    send_and_expect("single 0xAA", 8'hAA, BIT_NS);

    // 2. four bytes back to back, next start right after the stop bit
    fork
      begin
        for (int i = 0; i < 4; i++) send_byte(8'h10 + i[7:0], BIT_NS);
      end
      begin
        for (int i = 0; i < 4; i++)
          expect_byte($sformatf("back-to-back %0d", i), 8'h10 + i[7:0], 12 * CLKS_PER_BIT);
      end
    join
    sent += 4;

    // 3. baud rate mismatch, 3 percent either way
    send_and_expect("sender 3% slow", 8'h5A, BIT_NS * 1.03);
    send_and_expect("sender 3% fast", 8'hA5, BIT_NS * 0.97);

    // 4. false start bit: a quarter-bit glitch must not produce a byte
    strobes_before = strobes;
    glitch(BIT_NS / 4);
    #(12 * BIT_NS);
    if (strobes != strobes_before) begin
      errors++;
      $display("%t FAIL glitch produced a valid", $time);
    end else begin
      $display("%t ok   glitch ignored", $time);
    end

    // 5. framing error: frame_err strobes, valid does not, next byte is fine
    strobes_before = strobes;
    ferrs_before   = ferrs;
    send_broken_byte(8'h3C);
    if (ferrs != ferrs_before + 1) begin
      errors++;
      $display("%t FAIL frame_err strobes: %0d, expected 1", $time, ferrs - ferrs_before);
    end else if (strobes != strobes_before) begin
      errors++;
      $display("%t FAIL valid on a byte with a bad stop bit", $time);
    end else begin
      $display("%t ok   framing error reported", $time);
    end
    send_and_expect("after framing error", 8'hC3, BIT_NS);

    // 6. break: 30 bit times low is one error, not a stream of bytes
    strobes_before = strobes;
    ferrs_before   = ferrs;
    send_break(30);
    if (ferrs != ferrs_before + 1 || strobes != strobes_before) begin
      errors++;
      $display("%t FAIL break gave %0d frame_err and %0d valid, expected 1 and 0",
               $time, ferrs - ferrs_before, strobes - strobes_before);
    end else begin
      $display("%t ok   break handled", $time);
    end
    send_and_expect("after break", 8'h96, BIT_NS);

    // 7. totals
    #(2 * BIT_NS);
    if (strobes != sent) begin
      errors++;
      $display("%t FAIL %0d valid strobes for %0d bytes", $time, strobes, sent);
    end

    if (errors == 0) begin
      $display("tb_uart_rx: PASS");
      $finish;
    end else begin
      $display("tb_uart_rx: FAIL, %0d errors", errors);
      $stop;
    end
  end

  // Watchdog: whatever hangs above, the simulation ends.
  initial begin
    #2_000_000;                                      // 2 ms
    $display("tb_uart_rx: TIMEOUT");
    $stop;
  end

endmodule

`default_nettype wire
