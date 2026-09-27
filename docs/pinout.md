# Pinout

Net names in KiCad match the ports of `crsf2pwm_top`.
When changing a pin, update three places: this table, `quartus/crsf2pwm.qsf`, the schematic.

| Net | Module port | EPM240 pin | Board connector | Notes |
|---|---|---|---|---|
| CLK50 | clk | | on-board oscillator | verify against the board documentation |
| CRSF_RX | rx | | J_CRSF, receiver TX pin | 3.3 V, idle high |
| STEER | steer | | J_SERVO signal | servo powered separately |
| THROTTLE | throttle | | J_ESC signal | ESC powered separately |

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
