`timescale 1ns/1ps
`default_nettype none

// tb_top
// End-to-end test: CRSF bytes on rx, pulse widths on the outputs.
//
// A background process plays the receiver: while tx_on it sends an RC
// frame every 4 ms with the current tx_steer / tx_thr values, and with
// tx_junk it adds a frame with a bad CRC and a link statistics frame after
// each good one. The scenario changes those knobs and measures the pulses.
//
// FAILSAFE_PERIODS is 3 here (60 ms) instead of the default 25 (0.5 s) to
// keep the run short; the mechanism is the same.

module tb_top;

  `include "crsf_tb.svh"

  localparam int  CLK_HZ           = 50_000_000;
  localparam int  BAUD             = 420_000;
  localparam real BIT_NS           = 1e9 / BAUD;     // 2380.95 ns
  localparam int  FAILSAFE_PERIODS = 3;
  localparam real PERIOD_NS        = 20_000_000.0;
  localparam real TOL_NS           = 1000.0;         // +-1 us on every width

  logic clk = 0;
  always #10 clk = ~clk;                             // 50 MHz

  logic rx = 1;                                      // UART idle
  logic steer, throttle;

  crsf2pwm_top #(
    .CLK_HZ            (CLK_HZ),
    .BAUD              (BAUD),
    .STEER_CH          (0),
    .THROTTLE_CH       (1),
    .FAILSAFE_PERIODS  (FAILSAFE_PERIODS),
    .THROTTLE_FAILSAFE (992)
  ) dut (
    .clk      (clk),
    .rx       (rx),
    .steer    (steer),
    .throttle (throttle)
  );

  int errors = 0;

  // Edge counters: "no pulses in this window" is a difference of two reads.
  int steer_edges = 0;
  int thr_edges   = 0;
  always @(posedge steer)    steer_edges++;
  always @(posedge throttle) thr_edges++;

  // ---------------------------------------------------------------------
  // Receiver model
  // ---------------------------------------------------------------------
  task automatic send_byte(input logic [7:0] d);
    rx = 1'b0;
    #(BIT_NS);
    for (int i = 0; i < 8; i++) begin
      rx = d[i];
      #(BIT_NS);
    end
    rx = 1'b1;
    #(BIT_NS);
  endtask

  task automatic send_rc(input logic [175:0] p, input logic [7:0] crc_xor);
    send_byte(CRSF_ADDR_FC);
    send_byte(CRSF_LEN_RC);
    send_byte(CRSF_TYPE_RC);
    for (int i = 0; i < 22; i++) send_byte(p[8 * i +: 8]);
    send_byte(rc_frame_crc(p) ^ crc_xor);
  endtask

  task automatic send_link_stats;
    logic [7:0] c, b;
    c = crc8_step(8'h00, CRSF_TYPE_LINK);
    send_byte(CRSF_ADDR_FC);
    send_byte(CRSF_LEN_LINK);
    send_byte(CRSF_TYPE_LINK);
    for (int i = 0; i < 10; i++) begin
      b = 8'h10 + i[7:0];
      send_byte(b);
      c = crc8_step(c, b);
    end
    send_byte(c);
  endtask

  function automatic logic [175:0] car_payload(input logic [10:0] s, input logic [10:0] t);
    logic [175:0] p;
    p = all_channels(11'd992);
    p = set_channel(p, 0, s);
    p = set_channel(p, 1, t);
    return p;
  endfunction

  bit          tx_on    = 0;
  bit          tx_junk  = 0;
  logic [10:0] tx_steer = 11'd992;
  logic [10:0] tx_thr   = 11'd992;

  initial begin
    forever begin
      if (tx_on) begin
        send_rc(car_payload(tx_steer, tx_thr), 8'h00);
        if (tx_junk) begin
          send_rc(car_payload(11'd172, 11'd172), 8'hFF);   // bad CRC, other values
          send_link_stats();
        end
        #3_000_000;                                        // ~4 ms frame period
      end else begin
        #100_000;
      end
    end
  end

  // White-box check while junk is being sent: the parser outputs must never
  // show the values from the bad frames.
  int leaks = 0;
  always @(posedge clk) begin
    if (tx_junk && (dut.steer_val !== 11'd992 || dut.thr_val !== 11'd992)) leaks++;
  end

  // ---------------------------------------------------------------------
  // Measurement
  // ---------------------------------------------------------------------
  task automatic check(input string what, input real got_ns, input real exp_ns);
    if (got_ns > exp_ns + TOL_NS || got_ns < exp_ns - TOL_NS) begin
      errors++;
      $display("%t FAIL %-32s got %10.3f us, expected %10.3f us",
               $time, what, got_ns / 1000.0, exp_ns / 1000.0);
    end else begin
      $display("%t ok   %-32s %10.3f us", $time, what, got_ns / 1000.0);
    end
  endtask

  // Width of the next full pulse on steer (0) or throttle (1).
  task automatic measure_width(input bit which, output real width_ns);
    real t0;
    if (which) begin
      @(posedge throttle); t0 = $realtime;
      @(negedge throttle); width_ns = $realtime - t0;
    end else begin
      @(posedge steer); t0 = $realtime;
      @(negedge steer); width_ns = $realtime - t0;
    end
  endtask

  // Both outputs, in parallel, skipping one pulse each: the first pulse
  // after a change may still carry the old value.
  task automatic expect_outputs(input string what, input int s_val, input int t_val);
    real ws, wt;
    fork
      begin @(posedge steer);    measure_width(0, ws); end
      begin @(posedge throttle); measure_width(1, wt); end
    join
    check({what, " steer"},    ws, us_from_crsf(s_val) * 1000.0);
    check({what, " throttle"}, wt, us_from_crsf(t_val) * 1000.0);
  endtask

  // ---------------------------------------------------------------------
  // Scenario
  // ---------------------------------------------------------------------
  initial begin
    int  e0;
    real t0, w;

    $dumpfile("build/tb_top.vcd");
    $dumpvars(0, rx, steer, throttle, tx_on, tx_junk,
              dut.rx_valid, dut.frame_valid, dut.link_ok, dut.ever_valid,
              dut.steer_val, dut.thr_val, dut.missed);

    // 1. power-up: nothing until the first frame
    #25_000_000;
    if (steer_edges != 0 || thr_edges != 0) begin
      errors++;
      $display("%t FAIL pulses before the first frame", $time);
    end else begin
      $display("%t ok   silent before the first frame", $time);
    end

    // 2. link up
    tx_steer = 11'd172; tx_thr = 11'd1811; tx_on = 1;
    expect_outputs("link up 172/1811", 172, 1811);
    @(posedge steer); t0 = $realtime;
    @(posedge steer);
    check("steer period", $realtime - t0, PERIOD_NS);

    // 3. new values
    tx_steer = 11'd1811; tx_thr = 11'd172;
    expect_outputs("values 1811/172", 1811, 172);
    tx_steer = 11'd992; tx_thr = 11'd992;
    expect_outputs("values 992/992", 992, 992);

    // 4. bad CRC and foreign frames between good ones change nothing
    tx_junk = 1;
    expect_outputs("junk frames interleaved", 992, 992);
    tx_junk = 0;
    if (leaks != 0) begin
      errors++;
      $display("%t FAIL values from bad frames reached the parser outputs", $time);
    end else begin
      $display("%t ok   bad frames never reached the outputs", $time);
    end

    // 5. failsafe: frames stop
    tx_on = 0;
    e0 = steer_edges;
    #35_000_000;                                       // inside the timeout
    if (steer_edges == e0) begin
      errors++;
      $display("%t FAIL steer stopped before the failsafe timeout", $time);
    end else begin
      $display("%t ok   steer still pulsing 35 ms after the last frame", $time);
    end
    #55_000_000;                                       // 90 ms after the last frame
    e0 = steer_edges;
    #45_000_000;
    if (steer_edges != e0) begin
      errors++;
      $display("%t FAIL steer still pulsing in failsafe", $time);
    end else begin
      $display("%t ok   steer silent in failsafe", $time);
    end
    measure_width(1, w);
    check("throttle failsafe", w, 1_500_000.0);

    // 6. link back
    tx_steer = 11'd172; tx_thr = 11'd1811; tx_on = 1;
    expect_outputs("recovery 172/1811", 172, 1811);

    if (errors == 0) begin
      $display("tb_top: PASS");
      $finish;
    end else begin
      $display("tb_top: FAIL, %0d errors", errors);
      $stop;
    end
  end

  initial begin
    #1_500_000_000;                                    // 1.5 s
    $display("tb_top: TIMEOUT");
    $stop;
  end

endmodule

`default_nettype wire
