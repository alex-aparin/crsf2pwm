# Pinout

Net names in KiCad match the ports of `crsf2pwm_top`. When changing a
pin, update three places: this table, the revision's `.qsf`
(`quartus/crsf2pwm_c4.qsf` for Cyclone IV, `quartus/crsf2pwm.qsf` for
MAX II), and the schematic.

Four pins in total. `clk` must sit on a dedicated clock input: GCLK0..3
(pins 12, 14, 62, 64) on the EPM240T100, CLK0..CLK15 on the Cyclone IV E;
the fitter warns when a clock is placed elsewhere. The other three go on
any user I/O that reaches a header and is not shared with an on-board LED,
button or memory.

Cyclone IV board: Saylinx, EP4CE6F17C8N (256-pin BGA, pins named like
E1), a clone of the ALINX AX4010. The basics-graphics-music project
(github.com/yuri-panchul/basics-graphics-music) has this exact board as
`boards/saylinx`: its `board_specific.qsf` lists every pin and matches the
silkscreen here, and `board_specific_top.sv` shows the polarities: keys
are active low, LEDs light on 1, 7-segment segments and digits are active
low.

| Net | Module port | Cyclone IV pin | EPM240 pin | Board connector | Notes |
|---|---|---|---|---|---|
| CLK50 | clk | E1 | | on-board oscillator | 50 MHz, dedicated clock input |
| CRSF_RX | rx | M2 | | on-board USB-UART bridge, PC -> FPGA | frames from a PC over the board's mini-USB; for a receiver switch to T14 (right header pin 3, GND pin 1), 3.3 V, idle high, receiver RX pin left open |
| STEER | steer | T13 | | right header pin 5 | servo powered separately, 220 ohm .. 1 k series resistor |
| THROTTLE | throttle | T12 | | right header pin 7 | ESC powered separately, same resistor |
| LED0..3 | led[0..3] | D9, C9, F9, E10 | | on-board LEDs, light on 1 | status: link, frames, first frame, rx activity |

Other board resources, from the AX4010 data, for later: keys M15, M16,
E16 and reset N13 (with pull-ups); the on-board USB-UART bridge connects
to the FPGA on M2 (FPGA receives) and N1 (FPGA transmits), an option for
feeding test frames from the PC without a separate adapter.

## Saylinx board headers

Transcribed from the silkscreen on the bottom side; the labels are FPGA
pin names. "Left" and "right" are as seen from the bottom, with the VGA
connector at the top.

Left header, numbering starts at the top row, `[2] [1]`: even pins in the
left column, odd in the right.

| Pins | Left | Right |
|---|---|---|
| 2, 1 | VCC | GND |
| 4, 3 | J16 | B1 |
| 6, 5 | A2 | B3 |
| 8, 7 | A3 | B4 |
| 10, 9 | A4 | B5 |
| 12, 11 | A5 | B6 |
| 14, 13 | A6 | B7 |
| 16, 15 | A7 | B8 |
| 18, 17 | A8 | B9 |
| 20, 19 | A9 | B10 |
| 22, 21 | A10 | B11 |
| 24, 23 | A11 | B12 |
| 26, 25 | A12 | B13 |
| 28, 27 | A13 | D5 |
| 30, 29 | D6 | C6 |
| 32, 31 | E7 | F8 |
| 34, 33 | C8 | D8 |
| 36, 35 | E8 | E9 |
| 38, 37 | GND | GND |
| 40, 39 | 3V3 | 3V3 |

Right header, numbering starts at the bottom row, `[1] [2]`: odd pins in
the left column, even in the right, counting upwards.

| Pins | Left | Right |
|---|---|---|
| 39, 40 | 3V3 | 3V3 |
| 37, 38 | GND | GND |
| 35, 36 | P1 | N2 |
| 33, 34 | R1 | P2 |
| 31, 32 | K9 | P8 |
| 29, 30 | L10 | L9 |
| 27, 28 | T2 | M9 |
| 25, 26 | T3 | P3 |
| 23, 24 | T4 | R3 |
| 21, 22 | T5 | R4 |
| 19, 20 | T6 | R5 |
| 17, 18 | T7 | R6 |
| 15, 16 | T8 | R7 |
| 13, 14 | T9 | R8 |
| 11, 12 | T10 | R9 |
| 9, 10 | T11 | R10 |
| 7, 8 | T12 | R11 |
| 5, 6 | T13 | R12 |
| 3, 4 | T14 | R13 |
| 1, 2 | GND | VCC |

VCC on the headers is the board's 5 V input rail, 3V3 is the regulated
3.3 V. In the AX4010 data these two headers are GPIO_0 and GPIO_1, plain
I/O not shared with any on-board peripheral.

## clock_probe

`quartus/clock_probe.qsf` builds `quartus/probe/clock_probe.sv`: a
26-bit counter on `clk` = E1. The four LEDs count in binary at 0.75 Hz,
the first sign of life without any instrument, and four divided outputs
sit on each header for the scope. At 50 MHz:

| Header pin | FPGA pin | Signal | Period |
|---|---|---|---|
| right 3, left 6 | T14, A2 | clk / 2^26 | 1.34 s |
| right 5, left 8 | T13, A3 | clk / 2^23 | 168 ms |
| right 7, left 10 | T12, A4 | clk / 2^16 | 1.31 ms |
| right 9, left 12 | T11, A5 | clk / 2^6 | 1.28 us |

Nothing toggling means E1 is not the oscillator pin; doubled periods mean
a 25 MHz oscillator.

## JTAG, 2x5 header for USB Blaster

| Pin | Signal |
|---|---|
| 1 | TCK |
| 2 | GND |
| 3 | TDO |
| 4 | VCC 3.3 V, powers the cable buffers |
| 5 | TMS |
| 6 | not connected |
| 7 | not connected |
| 8 | not connected |
| 9 | TDI |
| 10 | GND |
