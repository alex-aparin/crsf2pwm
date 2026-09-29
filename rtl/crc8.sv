`timescale 1ns/1ps
`default_nettype none

// crc8
// CRC-8/DVB-S2: polynomial 0xD5, initial value 0x00, no input or output
// reflection, no final XOR. CRSF computes it over the type byte and the
// whole payload. Catalogue check value: "123456789" gives 0xBC.
//
// Per-byte step in C for reference:
//   crc ^= byte;
//   for (i = 0; i < 8; i++)
//     crc = (crc & 0x80) ? (crc << 1) ^ 0xD5 : (crc << 1);
//
// This is the byte-parallel version: the eight shift steps are a loop in a
// function, which synthesis unrolls into a fixed XOR network. Each bit of
// the new CRC is an XOR of a few bits of (crc ^ data), no extra state, and
// the result is registered in the same clock the byte is fed. About a
// dozen LEs. A bit-serial version would save a few of them but needs eight
// clocks per byte, a counter and a busy flag; bytes arrive 1190 clocks
// apart here, so either works, and this one is simpler to use.
//
// clear and valid in the same clock: clear wins. The parser never does that.

module crc8 (
  input  wire        clk,
  input  wire        clear,   // reset to 0x00 before a frame starts
  input  wire [7:0]  data,
  input  wire        valid,   // consume data
  output logic [7:0] crc
);

  logic [7:0] crc_q = '0;

  assign crc = crc_q;

  function automatic logic [7:0] crc8_step(input logic [7:0] c, input logic [7:0] d);
    logic [7:0] r;
    r = c ^ d;
    for (int i = 0; i < 8; i++) begin
      r = r[7] ? ({r[6:0], 1'b0} ^ 8'hD5) : {r[6:0], 1'b0};
    end
    return r;
  endfunction

  always_ff @(posedge clk) begin
    if (clear)      crc_q <= '0;
    else if (valid) crc_q <= crc8_step(crc_q, data);
  end

endmodule

`default_nettype wire
