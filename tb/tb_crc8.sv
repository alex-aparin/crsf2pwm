`timescale 1ns/1ps
`default_nettype none

// tb_crc8
// Known answers first, then a thousand messages from tb/vectors/crc8.hex,
// which tb/model/gen_vectors.py produced with the Python reference model.
// Regenerate the file with `make vectors` from sim/.

module tb_crc8;

  `include "crsf_tb.svh"

  logic clk = 0;
  always #10 clk = ~clk;

  logic       clear = 1'b0;
  logic       valid = 1'b0;
  logic [7:0] data  = '0;
  logic [7:0] crc;

  crc8 dut (
    .clk   (clk),
    .clear (clear),
    .data  (data),
    .valid (valid),
    .crc   (crc)
  );

  int errors = 0;
  int passed = 0;

  task automatic do_clear;
    @(negedge clk); clear = 1'b1;
    @(negedge clk); clear = 1'b0;
  endtask

  // One byte with valid for one clock, then `gap` idle clocks with garbage
  // on data: the module must look at data only while valid is high.
  task automatic feed(input logic [7:0] d, input int gap);
    @(negedge clk); data = d;  valid = 1'b1;
    @(negedge clk); data = ~d; valid = 1'b0;
    repeat (gap) @(negedge clk);
  endtask

  // Two bytes on consecutive clocks, valid held high.
  task automatic feed_pair(input logic [7:0] d0, input logic [7:0] d1);
    @(negedge clk); data = d0; valid = 1'b1;
    @(negedge clk); data = d1;
    @(negedge clk); valid = 1'b0;
  endtask

  task automatic feed_string(input string s, input int gap);
    for (int i = 0; i < s.len(); i++) feed(s[i], gap);
  endtask

  task automatic check(input string what, input logic [7:0] exp);
    @(negedge clk);
    if (crc !== exp) begin
      errors++;
      $display("%t FAIL %s: crc %02h, expected %02h", $time, what, crc, exp);
    end else begin
      passed++;
    end
  endtask

  // Array sized to the file, so $readmemh fills it exactly.
  `include "../tb/vectors/crc8_size.svh"
  logic [7:0] vec [0:CRC8_VEC_TOKENS-1];

  initial begin
    int         idx, n_msgs, len;
    logic [7:0] exp;

    $dumpfile("build/tb_crc8.vcd");
    $dumpvars(0, clk, clear, data, valid, crc);

    // 1. known answers
    do_clear();
    check("after clear", 8'h00);
    feed(8'h01, 0);
    check("0x01 is the polynomial", 8'hD5);
    do_clear();
    feed_string("123456789", 0);
    check("123456789", 8'hBC);

    // 2. clear in the middle of a stream
    feed(8'hAA, 0);
    feed(8'h55, 0);
    do_clear();
    feed_string("123456789", 0);
    check("clear mid-stream", 8'hBC);

    // 3. gaps between bytes with garbage on data while valid is low
    do_clear();
    feed_string("123456789", 3);
    check("gaps between bytes", 8'hBC);

    // 4. bytes on consecutive clocks
    do_clear();
    feed_pair(8'h31, 8'h32);
    feed_pair(8'h33, 8'h34);
    feed_pair(8'h35, 8'h36);
    feed_pair(8'h37, 8'h38);
    feed(8'h39, 0);
    check("consecutive clocks", 8'hBC);

    // 5. vectors from the Python model
    $readmemh("../tb/vectors/crc8.hex", vec);
    n_msgs = {vec[1], vec[0]};
    if (vec[0] === 8'bx || n_msgs != CRC8_VEC_MESSAGES) begin
      errors++;
      $display("FAIL tb/vectors/crc8.hex missing or out of step with crc8_size.svh, run make vectors");
    end else begin
      idx = 2;
      for (int m = 0; m < n_msgs; m++) begin
        len = vec[idx];
        idx++;
        do_clear();
        for (int i = 0; i < len; i++) begin
          feed(vec[idx], 0);
          idx++;
        end
        exp = vec[idx];
        idx++;
        check($sformatf("vector %0d, %0d bytes", m, len), exp);
      end
      $display("%0d file vectors checked", n_msgs);
    end

    if (errors == 0) begin
      $display("tb_crc8: PASS, %0d checks", passed);
      $finish;
    end else begin
      $display("tb_crc8: FAIL, %0d errors", errors);
      $stop;
    end
  end

  initial begin
    #50_000_000;
    $display("tb_crc8: TIMEOUT");
    $stop;
  end

endmodule

`default_nettype wire
