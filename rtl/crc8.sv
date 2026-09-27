`timescale 1ns/1ps
`default_nettype none

// crc8
// CRC-8/DVB-S2: polynomial 0xD5, initial value 0x00,
// no input or output reflection, no final XOR.
// CRSF computes it over the type byte and the whole payload.
//
// Per-byte step in C for reference:
//   crc ^= byte;
//   for (i = 0; i < 8; i++)
//     crc = (crc & 0x80) ? (crc << 1) ^ 0xD5 : (crc << 1);

module crc8 (
  input  wire        clk,
  input  wire        clear,   // reset to 0x00 before a frame starts
  input  wire [7:0]  data,
  input  wire        valid,   // consume data
  output logic [7:0] crc
);

  // TODO

endmodule

`default_nettype wire
