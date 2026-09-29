// crsf_tb.svh
// Helpers shared by the testbenches. `include it inside the module, after
// the port list. Kept free of arrays and casts so that Icarus 11 is happy;
// payloads are 176-bit vectors, which is also the wire order: payload bit
// p is bit p % 8 of byte p / 8, and channel c is bits 11c .. 11c+10.

localparam logic [7:0] CRSF_ADDR_FC   = 8'hC8;
localparam logic [7:0] CRSF_TYPE_RC   = 8'h16;
localparam logic [7:0] CRSF_LEN_RC    = 8'h18;
localparam logic [7:0] CRSF_TYPE_LINK = 8'h14;
localparam logic [7:0] CRSF_LEN_LINK  = 8'h0C;

// CRC-8/DVB-S2, one byte. Same algorithm as rtl/crc8.sv; the independent
// check is tb/model/crsf.py through tb/vectors/crc8.hex in tb_crc8.
function automatic logic [7:0] crc8_step(input logic [7:0] crc, input logic [7:0] d);
  logic [7:0] r;
  r = crc ^ d;
  for (int i = 0; i < 8; i++) begin
    r = r[7] ? ({r[6:0], 1'b0} ^ 8'hD5) : {r[6:0], 1'b0};
  end
  return r;
endfunction

// Payload with all 16 channels set to v.
function automatic logic [175:0] all_channels(input logic [10:0] v);
  logic [175:0] p;
  for (int k = 0; k < 16; k++) p[11 * k +: 11] = v;
  return p;
endfunction

// Payload p with channel k replaced by v.
function automatic logic [175:0] set_channel(input logic [175:0] p, input int k, input logic [10:0] v);
  p[11 * k +: 11] = v;
  return p;
endfunction

// Channel k of a payload.
function automatic logic [10:0] get_channel(input logic [175:0] p, input int k);
  return p[11 * k +: 11];
endfunction

// CRC of an RC frame: over the type byte and the 22 payload bytes.
function automatic logic [7:0] rc_frame_crc(input logic [175:0] p);
  logic [7:0] c;
  c = crc8_step(8'h00, CRSF_TYPE_RC);
  for (int i = 0; i < 22; i++) c = crc8_step(c, p[8 * i +: 8]);
  return c;
endfunction

// Channel value to pulse width in microseconds.
function automatic real us_from_crsf(input int v);
  return (v - 992) * 5.0 / 8.0 + 1500.0;
endfunction
