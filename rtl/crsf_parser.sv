`timescale 1ns/1ps
`default_nettype none

// crsf_parser
// Parses the CRSF byte stream and extracts two channels from the
// RC channels frame (type 0x16).
//
// Frame: [0xC8] [0x18] [0x16] [22 payload bytes] [CRC8]
// Payload: 16 channels of 11 bits back to back, LSB first.
// Channel value range 172..1811, center 992.
//
// ch_a and ch_b update together with the frame_valid strobe,
// and only if the CRC matched. Frames of other types are skipped.

module crsf_parser #(
  parameter int CH_A = 0,
  parameter int CH_B = 1
) (
  input  wire         clk,
  input  wire  [7:0]  byte_in,
  input  wire         byte_valid,
  output logic [10:0] ch_a,
  output logic [10:0] ch_b,
  output logic        frame_valid   // one-clock strobe
);

  localparam logic [7:0] ADDR_FC  = 8'hC8;
  localparam logic [7:0] TYPE_RC  = 8'h16;
  localparam logic [7:0] LEN_RC   = 8'h18;

  // TODO

endmodule

`default_nettype wire
