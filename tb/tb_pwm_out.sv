`timescale 1ns/1ps
`default_nettype none

// tb_pwm_out
// Standalone test for the servo pulse generator. Checks the contract from
// docs/servo_pwm.md: pulse width from the CRSF value within +-1 us, 20 ms
// period, a new value or enable = 0 takes effect only at a period boundary.
//
// Everything is measured with $realtime between edges of pwm. The tick,
// the counter and the shadow registers are internals; if they are right,
// the edges are right.

module tb_pwm_out;

  localparam int  CLK_HZ = 50_000_000;
  localparam real TOL_NS = 1000.0;              // +-1 us on every width

  logic clk = 0;
  always #10 clk = ~clk;                        // 50 MHz

  logic [10:0] value  = 11'd992;
  logic        enable = 1'b0;
  logic        pwm;

  pwm_out #(
    .CLK_HZ (CLK_HZ)
  ) dut (
    .clk    (clk),
    .value  (value),
    .enable (enable),
    .pwm    (pwm)
  );

  int errors = 0;

  // Expected pulse width in ns for a CRSF value: us = (v - 992) * 5/8 + 1500.
  function automatic real expect_ns(input int v);
    return ((v - 992) * 5.0 / 8.0 + 1500.0) * 1000.0;
  endfunction

  task automatic check(input string what, input real got_ns, input real exp_ns);
    if (got_ns > exp_ns + TOL_NS || got_ns < exp_ns - TOL_NS) begin
      errors++;
      $display("%t FAIL %-30s got %10.3f us, expected %10.3f us",
               $time, what, got_ns / 1000.0, exp_ns / 1000.0);
    end else begin
      $display("%t ok   %-30s %10.3f us", $time, what, got_ns / 1000.0);
    end
  endtask

  // Width of the next full pulse and the period measured from its rising
  // edge to the following one.
  task automatic measure(output real width_ns, output real period_ns);
    real t0, t1, t2;
    @(posedge pwm); t0 = $realtime;
    @(negedge pwm); t1 = $realtime;
    @(posedge pwm); t2 = $realtime;
    width_ns  = t1 - t0;
    period_ns = t2 - t0;
  endtask

  int vals [5];

  initial begin
    real   w, p, t0;
    string name;

    // Dump only what is cheap: pwm changes twice per period, the inputs and
    // the shadow registers once. clk would add 50 million lines per second
    // of simulated time, dut.cnt 1.6 million. Add them when debugging.
    $dumpfile("build/tb_pwm_out.vcd");
    $dumpvars(0, value, enable, pwm, dut.width, dut.en_q);

    vals[0] = 172; vals[1] = 992; vals[2] = 1811; vals[3] = 0; vals[4] = 2047;

    // 1. disabled from power-up: no pulses at all
    #25_000_000;                                        // 25 ms, more than a period
    if (pwm !== 1'b0) begin
      errors++;
      $display("%t FAIL pwm not low while disabled", $time);
    end else begin
      $display("%t ok   silent while disabled", $time);
    end

    enable = 1'b1;

    // 2. static widths and the period. The first pulse after a change may
    //    still carry the old width, so skip one edge before measuring.
    foreach (vals[i]) begin
      value = vals[i][10:0];
      @(posedge pwm);
      measure(w, p);
      $sformat(name, "width value=%0d", vals[i]);
      check(name, w, expect_ns(vals[i]));
      $sformat(name, "period value=%0d", vals[i]);
      check(name, p, 20_000_000.0);
    end

    // 3. value changed mid-pulse: the running pulse keeps the old width,
    //    the next one has the new width
    value = 11'd1811;
    @(posedge pwm); @(posedge pwm); t0 = $realtime;
    #500_000;                                           // 0.5 ms into the pulse
    value = 11'd172;
    @(negedge pwm); w = $realtime - t0;
    check("old width kept after change", w, expect_ns(1811));
    measure(w, p);
    check("new width next period", w, expect_ns(172));

    // 4. value raised after the pulse ended: no second pulse in this period
    @(posedge pwm); t0 = $realtime;
    @(negedge pwm);
    #200_000;
    value = 11'd1811;
    @(posedge pwm); p = $realtime - t0;
    check("no retrigger, next edge at", p, 20_000_000.0);

    // 5. enable dropped mid-pulse: the pulse completes, then silence
    value = 11'd992;
    @(posedge pwm); @(posedge pwm); t0 = $realtime;
    #500_000;
    enable = 1'b0;
    @(negedge pwm); w = $realtime - t0;
    check("pulse completes on disable", w, expect_ns(992));
    fork
      begin
        @(posedge pwm);
        errors++;
        $display("%t FAIL pulse after disable", $time);
      end
      begin
        #45_000_000;                                    // more than two periods
        $display("%t ok   silent 45 ms after disable", $time);
      end
    join_any
    disable fork;

    if (errors == 0) begin
      $display("tb_pwm_out: PASS");
      $finish;
    end else begin
      $display("tb_pwm_out: FAIL, %0d errors", errors);
      $stop;
    end
  end

  // Watchdog: an empty or broken module never produces an edge and every
  // wait above would hang forever.
  initial begin
    #1_000_000_000;                                     // 1 s
    $display("tb_pwm_out: TIMEOUT");
    $stop;
  end

endmodule

`default_nettype wire
