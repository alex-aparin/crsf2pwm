`timescale 1ns/1ps
`default_nettype none

// tb_crsf_parser
// Bytes go in at the clock level, as uart_rx would deliver them: byte_valid
// for one clock, then a gap. Two parsers see the same stream, one with the
// default channels 0 and 1, one with channels 3 and 15, so the bit map is
// exercised across byte boundaries and at the end of the payload.
//
// Contract checked here:
//   frame_valid  exactly one clock per good RC frame, never otherwise
//   ch_a, ch_b   the frame's channels, updated in the strobe clock only
//   recovery     bad CRC, other frame types, garbage, bogus lengths and a
//                frame that stops short must not lose the next good frame

module tb_crsf_parser;

  `include "crsf_tb.svh"

  localparam int CLK_HZ    = 50_000_000;
  localparam int GAP_US    = 100;
  localparam int GAP_CLKS  = CLK_HZ / 1_000_000 * GAP_US;   // 5000, the parser's timeout
  localparam int BYTE_CLKS = CLK_HZ / 420_000 * 10;         // 1190, one byte on the wire
  localparam int FAST      = 20;                            // clocks between bytes, keeps the run short

  logic clk = 0;
  always #10 clk = ~clk;

  logic [7:0]  byte_in    = '0;
  logic        byte_valid = 1'b0;
  logic [10:0] a1, b1, a2, b2;
  logic        fv1, fv2;

  crsf_parser #(
    .CH_A   (0),
    .CH_B   (1),
    .CLK_HZ (CLK_HZ),
    .GAP_US (GAP_US)
  ) dut1 (
    .clk         (clk),
    .byte_in     (byte_in),
    .byte_valid  (byte_valid),
    .ch_a        (a1),
    .ch_b        (b1),
    .frame_valid (fv1)
  );

  crsf_parser #(
    .CH_A   (3),
    .CH_B   (15),
    .CLK_HZ (CLK_HZ),
    .GAP_US (GAP_US)
  ) dut2 (
    .clk         (clk),
    .byte_in     (byte_in),
    .byte_valid  (byte_valid),
    .ch_a        (a2),
    .ch_b        (b2),
    .frame_valid (fv2)
  );

  int errors = 0;

  // Monitors: strobe counts and the one-clock rule.
  int   strobes1 = 0, strobes2 = 0;
  logic fv1_q = 0, fv2_q = 0;
  always @(posedge clk) begin
    if (fv1) strobes1++;
    if (fv2) strobes2++;
    if (fv1 && fv1_q) begin errors++; $display("%t FAIL dut1 frame_valid longer than one clock", $time); end
    if (fv2 && fv2_q) begin errors++; $display("%t FAIL dut2 frame_valid longer than one clock", $time); end
    fv1_q <= fv1;
    fv2_q <= fv2;
  end

  // Outputs may change only in a strobe clock.
  logic [10:0] a1_q, b1_q;
  always @(posedge clk) begin
    if ((a1 !== a1_q || b1 !== b1_q) && !fv1 && $time > 100) begin
      errors++;
      $display("%t FAIL dut1 channels changed without frame_valid", $time);
    end
    a1_q <= a1;
    b1_q <= b1;
  end

  // ---------------------------------------------------------------------
  // Drivers
  // ---------------------------------------------------------------------
  task automatic push(input logic [7:0] b, input int gap);
    @(negedge clk); byte_in = b; byte_valid = 1'b1;
    @(negedge clk); byte_valid = 1'b0;
    repeat (gap) @(negedge clk);
  endtask

  // Byte i of the 26-byte RC frame for payload p: 0 address, 1 length,
  // 2 type, 3..24 payload, 25 CRC (xor-ed with crc_xor to spoil it).
  function automatic logic [7:0] frame_byte(input logic [175:0] p, input logic [7:0] crc_xor, input int i);
    if (i == 0)  return CRSF_ADDR_FC;
    if (i == 1)  return CRSF_LEN_RC;
    if (i == 2)  return CRSF_TYPE_RC;
    if (i == 25) return rc_frame_crc(p) ^ crc_xor;
    return p[8 * (i - 3) +: 8];
  endfunction

  // Bytes first .. last-1 of an RC frame: the whole frame is (0, 26), a
  // frame cut after ten bytes is (0, 10), a frame without its address
  // byte is (1, 26).
  task automatic send_rc(input logic [175:0] p, input logic [7:0] crc_xor, input int gap,
                         input int first, input int last);
    for (int i = first; i < last; i++) push(frame_byte(p, crc_xor, i), gap);
  endtask

  // Link statistics frame, type 0x14, 10 payload bytes, good CRC.
  task automatic send_link_stats(input int gap);
    logic [7:0] c, b;
    c = crc8_step(8'h00, CRSF_TYPE_LINK);
    push(CRSF_ADDR_FC, gap);
    push(CRSF_LEN_LINK, gap);
    push(CRSF_TYPE_LINK, gap);
    for (int i = 0; i < 10; i++) begin
      b = 8'h10 + i[7:0];
      push(b, gap);
      c = crc8_step(c, b);
    end
    push(c, gap);
  endtask

  // Type 0x16 but length 25: a valid frame that is not an RC frame.
  task automatic send_rc_wrong_length(input int gap);
    logic [7:0] c, b;
    c = crc8_step(8'h00, CRSF_TYPE_RC);
    push(CRSF_ADDR_FC, gap);
    push(8'h19, gap);
    push(CRSF_TYPE_RC, gap);
    for (int i = 0; i < 23; i++) begin
      b = 8'hA0 + i[7:0];
      push(b, gap);
      c = crc8_step(c, b);
    end
    push(c, gap);
  endtask

  task automatic silence(input int clks);
    repeat (clks) @(negedge clk);
  endtask

  // ---------------------------------------------------------------------
  // Checker: strobes since the last check and current channel values.
  // ---------------------------------------------------------------------
  int base1 = 0, base2 = 0;

  task automatic expect_result(input string what,
                               input int n1, input logic [10:0] ea1, input logic [10:0] eb1,
                               input int n2, input logic [10:0] ea2, input logic [10:0] eb2);
    bit ok = 1;
    repeat (3) @(negedge clk);
    if (strobes1 - base1 != n1) begin
      ok = 0; $display("%t FAIL %s: dut1 %0d strobes, expected %0d", $time, what, strobes1 - base1, n1);
    end
    if (a1 !== ea1 || b1 !== eb1) begin
      ok = 0; $display("%t FAIL %s: dut1 ch %0d/%0d, expected %0d/%0d", $time, what, a1, b1, ea1, eb1);
    end
    if (strobes2 - base2 != n2) begin
      ok = 0; $display("%t FAIL %s: dut2 %0d strobes, expected %0d", $time, what, strobes2 - base2, n2);
    end
    if (a2 !== ea2 || b2 !== eb2) begin
      ok = 0; $display("%t FAIL %s: dut2 ch %0d/%0d, expected %0d/%0d", $time, what, a2, b2, ea2, eb2);
    end
    if (ok) $display("%t ok   %s", $time, what);
    else    errors++;
    base1 = strobes1;
    base2 = strobes2;
  endtask

  // ---------------------------------------------------------------------
  // Scenario
  // ---------------------------------------------------------------------
  logic [175:0] p1, p2, p0, pmax;

  initial begin
    $dumpfile("build/tb_crsf_parser.vcd");
    $dumpvars(0, byte_in, byte_valid, a1, b1, fv1, a2, b2, fv2,
              dut1.state, dut1.remaining, dut1.is_rc, dut1.crc, dut1.sh_a, dut1.sh_b);

    // p1: car-like frame, a few distinct channels. p2: every channel different.
    p1 = all_channels(11'd992);
    p1 = set_channel(p1, 0, 11'd172);
    p1 = set_channel(p1, 1, 11'd1811);
    p1 = set_channel(p1, 3, 11'd400);
    p1 = set_channel(p1, 15, 11'd1600);
    p2 = all_channels(11'd0);
    for (int k = 0; k < 16; k++) begin
      logic [10:0] v;
      v  = 100 + 100 * k;
      p2 = set_channel(p2, k, v);
    end
    p0   = all_channels(11'd0);
    pmax = all_channels(11'd2047);

    silence(50);

    // 1. good frames
    send_rc(p1, 8'h00, FAST, 0, 26);
    expect_result("good frame p1", 1, 172, 1811, 1, 400, 1600);
    send_rc(p2, 8'h00, FAST, 0, 26);
    expect_result("good frame p2, all channels distinct", 1, 100, 200, 1, 400, 1600);

    // 2. extremes
    send_rc(p0, 8'h00, FAST, 0, 26);
    expect_result("all channels 0", 1, 0, 0, 1, 0, 0);
    send_rc(pmax, 8'h00, FAST, 0, 26);
    expect_result("all channels 2047", 1, 2047, 2047, 1, 2047, 2047);

    // 3. bad CRC: nothing changes
    send_rc(p1, 8'hFF, FAST, 0, 26);
    expect_result("bad CRC ignored", 0, 2047, 2047, 0, 2047, 2047);

    // 4. other frame types are skipped, the next RC frame is caught
    send_link_stats(FAST);
    expect_result("link statistics frame ignored", 0, 2047, 2047, 0, 2047, 2047);
    send_rc_wrong_length(FAST);
    expect_result("type 0x16 with length 25 ignored", 0, 2047, 2047, 0, 2047, 2047);
    send_rc(p2, 8'h00, FAST, 0, 26);
    expect_result("RC frame after foreign frames", 1, 100, 200, 1, 400, 1600);

    // 5. garbage before a frame
    push(8'h00, FAST); push(8'hFF, FAST); push(8'h55, FAST); push(8'h18, FAST); push(8'h16, FAST);
    send_rc(p1, 8'h00, FAST, 0, 26);
    expect_result("garbage without 0xC8, then frame", 1, 172, 1811, 1, 400, 1600);

    push(CRSF_ADDR_FC, FAST); push(8'h7F, FAST);                // length too long
    send_rc(p2, 8'h00, FAST, 0, 26);
    expect_result("0xC8 with length 127, then frame", 1, 100, 200, 1, 400, 1600);

    push(CRSF_ADDR_FC, FAST); push(8'h01, FAST);                // length too short
    send_rc(p1, 8'h00, FAST, 0, 26);
    expect_result("0xC8 with length 1, then frame", 1, 172, 1811, 1, 400, 1600);

    push(CRSF_ADDR_FC, FAST);                                   // sync byte twice
    send_rc(p2, 8'h00, FAST, 0, 26);
    expect_result("doubled sync byte", 1, 100, 200, 1, 400, 1600);

    // 6. a frame that stops: header only, then silence, then a good frame
    push(CRSF_ADDR_FC, FAST); push(CRSF_LEN_RC, FAST);
    silence(GAP_CLKS + 200);
    send_rc(p1, 8'h00, FAST, 0, 26);
    expect_result("header then silence, then frame", 1, 172, 1811, 1, 400, 1600);

    // 7. a frame cut at byte 10, silence, then a good frame with other values
    send_rc(pmax, 8'h00, FAST, 0, 10);
    silence(GAP_CLKS + 200);
    send_rc(p2, 8'h00, FAST, 0, 26);
    expect_result("truncated frame, then frame", 1, 100, 200, 1, 400, 1600);

    // 8. a frame cut at byte 10 with no silence: the next frame is lost to
    //    the CRC check, the one after it is caught. This is the price of
    //    not having a gap; the silence timeout is what saves case 7.
    send_rc(pmax, 8'h00, FAST, 0, 10);
    send_rc(p1, 8'h00, FAST, 0, 26);
    send_rc(p2, 8'h00, FAST, 0, 26);
    expect_result("truncated frame glued to the next", 1, 100, 200, 1, 400, 1600);

    // 9. frames back to back, no gap at all
    send_rc(p1, 8'h00, 0, 0, 26);
    send_rc(p2, 8'h00, 0, 0, 26);
    send_rc(p1, 8'h00, 0, 0, 26);
    expect_result("three frames back to back", 3, 172, 1811, 3, 400, 1600);

    // 10. real spacing, 1190 clocks per byte: no false timeout
    send_rc(p2, 8'h00, BYTE_CLKS, 0, 26);
    expect_result("wire-speed spacing", 1, 100, 200, 1, 400, 1600);

    // 11. a frame to another address is not ours: 0xEE then the rest
    push(8'hEE, FAST);
    send_rc(p1, 8'h00, FAST, 1, 26);
    silence(GAP_CLKS + 200);
    send_rc(p2, 8'h00, FAST, 0, 26);
    expect_result("frame for address 0xEE ignored", 1, 100, 200, 1, 400, 1600);

    if (errors == 0) begin
      $display("tb_crsf_parser: PASS");
      $finish;
    end else begin
      $display("tb_crsf_parser: FAIL, %0d errors", errors);
      $stop;
    end
  end

  initial begin
    #20_000_000;                                    // 20 ms
    $display("tb_crsf_parser: TIMEOUT");
    $stop;
  end

endmodule

`default_nettype wire
