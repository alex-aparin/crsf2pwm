# CRSF: what the decoder needs to know

## Physical layer

- UART 8N1, 420000 baud by default for ELRS and Crossfire.
- 3.3 V levels. Only the receiver's TX line is needed; telemetry is optional.
- ELRS sends an RC frame at the link packet rate, e.g. every 2 ms at 500 Hz.
  A 26-byte frame takes about 0.62 ms.

## Frame

| Byte | Value | Meaning |
|---|---|---|
| 0 | 0xC8 | destination address, flight controller |
| 1 | length | number of bytes after this field: type + payload + CRC |
| 2 | type | 0x16 for RC channels, 0x14 for link statistics |
| 3.. | payload | exactly 22 bytes for type 0x16 |
| last | CRC8 | over the type byte and the payload |

For the RC frame the length is always 0x18 (24). Other frames have length up to 62.

## CRC

CRC-8/DVB-S2: polynomial 0xD5, initial value 0x00, no reflection, no final XOR.

```
crc ^= byte;
for (i = 0; i < 8; i++)
    crc = (crc & 0x80) ? (crc << 1) ^ 0xD5 : (crc << 1);
```

## Channel packing

16 channels of 11 bits back to back, LSB first, starting at bit 0 of byte 0.
Channel 0 is byte0[7:0] plus byte1[2:0]. Channel 1 is byte1[7:3] plus byte2[5:0].

Since UART also delivers bits LSB first, the serial bit stream of the payload
is simply channel 0, channel 1, channel 2 and so on. A bit counter modulo 11
and a channel counter are enough to pick out a channel without buffering.

## Values

| Value | Pulse |
|---|---|
| 172 | 988 us |
| 992 | 1500 us |
| 1811 | 2012 us |

Formula: us = (value - 992) * 5 / 8 + 1500.

## Failsafe

On link loss ELRS by default stops sending RC frames.
The decoder must watch the gap itself: no valid frame for about 0.5 s
means drop the pulses or move the channels to a safe position.

## References

- CRSF working group specification: https://github.com/crsf-wg/crsf/wiki
- ExpressLRS documentation: https://www.expresslrs.org/
