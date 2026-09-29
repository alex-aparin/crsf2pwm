`timescale 1ns/1ps
`default_nettype none

// crsf2pwm_top
// Top level: CRSF over UART in, two servo PWM signals out.
//
//   rx -> 2-flop synchroniser -> uart_rx -> crsf_parser -> pwm_chan x2
//                                              |              ^
//                                              v              |
//                                          link watchdog   pwm_timebase
//
// Failsafe policy (docs/servo_pwm.md):
//   - Power-up: no pulses on either output until the first valid RC frame.
//     The ESC sees no signal and can be calibrated, nothing moves.
//   - Link up: steer and throttle follow their channels.
//   - No valid RC frame for FAILSAFE_PERIODS periods of 20 ms (25 = 0.5 s):
//     steer stops pulsing and goes limp, throttle keeps pulsing at
//     THROTTLE_FAILSAFE. 992 is 1500 us, stop for a reversible car ESC;
//     use 172 (988 us) for a one-way multirotor-style ESC.
//   - Frames again: everything resumes with the next period.
//
// The watchdog counts periods, not clocks: a 5-bit counter driven by the
// timebase's start strobe instead of a 25-bit counter at 50 MHz.

module crsf2pwm_top #(
  parameter int CLK_HZ            = 50_000_000,  // board oscillator
  parameter int BAUD              = 420_000,     // CRSF default
  parameter int STEER_CH          = 0,           // CRSF channel for steering
  parameter int THROTTLE_CH       = 1,           // CRSF channel for throttle
  parameter int FAILSAFE_PERIODS  = 25,          // 20 ms periods without a frame
  parameter int THROTTLE_FAILSAFE = 992          // throttle value while the link is down
) (
  input  wire  clk,       // 50 MHz
  input  wire  rx,        // CRSF from the receiver, 3.3 V, idle high
  output logic steer,     // PWM to the steering servo
  output logic throttle   // PWM to the motor ESC
);

  // rx synchroniser: rx is asynchronous, two flops keep metastability
  // away from the UART state machine.
  logic rx_meta = 1'b1;
  logic rx_sync = 1'b1;

  always_ff @(posedge clk) begin
    rx_meta <= rx;
    rx_sync <= rx_meta;
  end

  // UART
  logic [7:0] rx_data;
  logic       rx_valid;

  uart_rx #(
    .CLK_HZ (CLK_HZ),
    .BAUD   (BAUD)
  ) u_uart (
    .clk       (clk),
    .rx        (rx_sync),
    .data      (rx_data),
    .valid     (rx_valid),
    .frame_err ()
  );

  // Frame parser
  logic [10:0] steer_val;
  logic [10:0] thr_val;
  logic        frame_valid;

  crsf_parser #(
    .CH_A   (STEER_CH),
    .CH_B   (THROTTLE_CH),
    .CLK_HZ (CLK_HZ)
  ) u_parser (
    .clk         (clk),
    .byte_in     (rx_data),
    .byte_valid  (rx_valid),
    .ch_a        (steer_val),
    .ch_b        (thr_val),
    .frame_valid (frame_valid)
  );

  // Shared servo timebase
  logic tick, start, head;

  pwm_timebase #(
    .CLK_HZ (CLK_HZ)
  ) u_timebase (
    .clk   (clk),
    .tick  (tick),
    .start (start),
    .head  (head)
  );

  // Link watchdog. All registers zero at power-up is the safe state:
  // link_ok = 0 and ever_valid = 0 mean no pulses at all.
  localparam int FS_W = $clog2(FAILSAFE_PERIODS + 1);
  localparam logic [FS_W-1:0] FS_ONE  = 1;
  localparam logic [FS_W-1:0] FS_LAST = FAILSAFE_PERIODS - 1;

  logic [FS_W-1:0] missed     = '0;     // period starts since the last good frame
  logic            link_ok    = 1'b0;
  logic            ever_valid = 1'b0;

  always_ff @(posedge clk) begin
    if (frame_valid) begin
      missed     <= '0;
      link_ok    <= 1'b1;
      ever_valid <= 1'b1;
    end else if (start) begin
      if (missed == FS_LAST) link_ok <= 1'b0;
      else                   missed  <= missed + FS_ONE;
    end
  end

  // Outputs
  localparam logic [10:0] THR_FAILSAFE_V = THROTTLE_FAILSAFE;

  logic [10:0] thr_cmd;
  assign thr_cmd = link_ok ? thr_val : THR_FAILSAFE_V;

  pwm_chan u_steer (
    .clk    (clk),
    .tick   (tick),
    .start  (start),
    .head   (head),
    .value  (steer_val),
    .enable (link_ok),
    .pwm    (steer)
  );

  pwm_chan u_throttle (
    .clk    (clk),
    .tick   (tick),
    .start  (start),
    .head   (head),
    .value  (thr_cmd),
    .enable (ever_valid),
    .pwm    (throttle)
  );

endmodule

`default_nettype wire
