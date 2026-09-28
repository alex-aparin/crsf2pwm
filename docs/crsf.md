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

## Channel values

Each channel is an 11-bit field, so 0..2047 fits physically. The
specification defines 0..1984 as the valid range, centre 992. Full stick
travel at the usual +-100 % limits is 172..1811.

| Stick | Transmitter units | Pulse | CRSF |
|---|---|---|---|
| -100 % | -1024 | 988 us | 172 |
| 0 | 0 | 1500 us | 992 |
| +100 % | +1024 | 2012 us | 1811 |
| -150 % | -1536 | 880 us after clamping | 0 |
| +150 % | +1536 | 2120 us after clamping | 1984 |

Formula from the specification: us = (value - 992) * 5 / 8 + 1500.
Betaflight fits the same line as 0.62477 * value + 881.

Where the numbers come from:

- EdgeTX and OpenTX hold a channel as -1024..+1024 for -100..+100 %.
- Their PPM output maps that to 1500 +- 512 us. Hence 988 and 2012 instead
  of 1000 and 2000: 512 is a power of two, convenient on 8-bit radios.
- Futaba SBUS encodes microseconds in 5/8 us steps with 992 at 1500 us,
  and CRSF took the SBUS encoding so flight controllers could reuse the
  conversion. Transmitter units to CRSF units is 0.5 us / 0.625 us = 4/5:
  crsf = 992 + channel * 4 / 5, clamped to 0..1984 (EdgeTX crossfire.cpp).
  +-1024 * 4 / 5 = +-819, so 992 +- 819 = 172..1811.

So 172..1811 is a convention for where +-100 % sits, not a property of
the protocol. With extended limits on the transmitter values outside it
do arrive. The parser passes the 11 bits through unchanged, and pwm_out
handles any 0..2047 without overflow: it produces 880..2159 us, which
servos and ESCs accept as slightly extended travel.

ELRS sends switch channels with reduced resolution. On the receiver a
two-position switch reads 191 or 1792 (1000 or 2000 us) and a
three-position switch adds 992. Sticks use the full range.

One CRSF unit is exactly 5/8 us = 0.625 us. Counting time in 0.625 us
ticks (1.6 MHz) turns the conversion into an addition: width in ticks =
value + 1408, period 20 ms = 32000 ticks. This is how pwm_out works.

## Failsafe

On link loss ELRS by default stops sending RC frames. The decoder must
watch the gap itself. Two references for the numbers:

- This project: no valid frame for about 0.5 s, timeout is a parameter.
- ELRS PWM receivers: 1 s without a valid packet or link quality 0. The
  failsafe action is a configurable pulse width per channel, default
  1500 us on all outputs except the throttle output, which defaults to
  988 us. Before the first connection they output no pulses at all so the
  ESC can be calibrated.

What to output on failsafe depends on the load, see docs/servo_pwm.md:
the steering servo can simply get no pulses, the ESC needs a defined
pulse, neutral for a reversible ESC or minimum for a one-way one.

## References

- CRSF working group specification: https://github.com/crsf-wg/crsf/wiki
- RC channels frame, value range and the 5/8 formula:
  https://github.com/crsf-wg/crsf/wiki/CRSF_FRAMETYPE_RC_CHANNELS_PACKED
- Betaflight conversion, `crsfReadRawRC` in `src/main/rx/crsf.c` and
  `sbusChannelsReadRawRC` in `src/main/rx/sbus_channels.c`:
  https://github.com/betaflight/betaflight
- EdgeTX transmitter side, `radio/src/pulses/crossfire.cpp`:
  https://github.com/EdgeTX/edgetx
- ExpressLRS documentation: https://www.expresslrs.org/
- ExpressLRS PWM receivers, a finished device doing the same job:
  https://www.expresslrs.org/hardware/pwm-receivers/
