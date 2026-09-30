# Board bring-up

Getting the design from a green simulation onto the Saylinx Cyclone IV
board and to a moving car, one observable step at a time. Linux only; the
scripts live in `tools/`. Pins are in docs/pinout.md.

## What you need

- The board, powered through its mini-USB from a computer port or a 5 V
  supply, power switch ON, power LED lit. The USB Blaster does not power
  the board; it takes 3.3 V from the board's JTAG header to drive its
  buffers.
- USB Blaster or a clone in the header marked JTAG, top centre next to the
  CAMERA header. The other 2x5 header near the USB jack is not JTAG.
- Quartus Prime Lite with the Cyclone IV device support, see README.
- An oscilloscope for the pulse widths. A multimeter helps with the
  wiring.
- Later: an ELRS receiver bound to a transmitter, a servo, the ESC.

## 1. Cable and chain

```
tools/udev-install.sh        # once per machine, then replug the Blaster
tools/jtag-check.sh
```

| `jtagconfig` says | Meaning | Do |
|---|---|---|
| `No JTAG hardware available` | Linux does not let Quartus open the cable | udev rule, replug, another USB port |
| `USB-Blaster` then `Unable to read device chain - JTAG chain broken` | cable fine, board silent (also `Error code 87` from `quartus_pgm`) | board power ON and LED lit; ribbon in the JTAG header, seated, key aligned; 3.3 V between header pins 4 and 2; ribbon continuity |
| `USB-Blaster` then `020F10DD EP4CE6(E22\|F17)/EP4CE10...` | the FPGA answers | go on |

The chain does not care whether the FPGA is configured, so a working
chain with a dead design is normal.

## 2. Clock probe

Before the real design, prove the oscillator pin and frequency:

```
tools/build.sh clock_probe
tools/program.sh clock_probe
```

Expected within a second of programming:

- The four LEDs count in binary: LED0 toggles about 6 times a second,
  LED3 once per 1.34 s.
- Scope on the right header (seen from the bottom, `[1][2]` at the bottom
  row): pin 7 = T12 gives a square wave of 1.31 ms period, pin 9 = T11 one
  of 1.28 us. Ground on pin 1.

| Observation | Meaning |
|---|---|
| LEDs count, 1.31 ms on T12 | 50 MHz on E1, as assumed |
| LEDs count twice as slowly, 2.62 ms | 25 MHz oscillator: set `CLK_HZ` to 25_000_000 in the top and rebuild |
| Nothing moves | E1 is not the oscillator pin, or the FPGA did not configure (Programmer reports success but check the CONF_DONE LED if the board has one) |

The probe stays until power-off; it is not written to the flash.

## 3. The design without a receiver

```
tools/build.sh
tools/program.sh
```

Right after programming all four LEDs are off and both outputs are low.
That is correct: no frame yet, no pulses, the ESC would not arm. The LEDs:

| LED | Lit when |
|---|---|
| LED0 | link up: good RC frames within the failsafe window |
| LED1 | blinking while frames arrive, about 4 Hz at 250 Hz packets |
| LED2 | at least one good frame since power-up |
| LED3 | glowing while bytes arrive on rx, valid or not |

Feeding frames from the PC instead of a receiver: a USB-UART adapter, its
TX to header pin 3 and GND to pin 1, and a pyserial script built on
`tb/model/crsf.py` sending `rc_frame(...)` at 420000 baud every 4 ms. The
board's own USB-UART bridge (FPGA pins M2/N1) is an alternative that needs
a revision with rx on M2.

## 4. Receiver

Receiver TX to right header pin 3 (T14), receiver GND to pin 1, receiver
5 V from pin 2 (the board's 5 V rail) or from a separate 5 V supply; never
5 V onto a signal pin. Receiver RX stays open. Receiver settings: protocol
CRSF, not inverted, 420000 baud.

Transmitter on:

1. LED3 glows: bytes arrive. If it stays dark, the wire or the receiver's
   serial protocol setting.
2. LED2 and LED0 light, LED1 blinks: frames parse. LED3 on but LED2 off
   means bytes but no good frames: wrong baud rate, inverted signal (rx idle
   low on the scope), or another protocol.
3. Scope on pin 5 (steer) and pin 7 (throttle): pulses of 1 to 2 ms every
   20 ms, width following the sticks. Settings that work: 1 V/div, 10x
   probe with 10x set in the channel menu, 200 us/div, edge trigger on the
   channel, rising, level 1.5 V, mode Normal, trigger marker moved to the
   left. Measure > +Width reads the width, both outputs rise together so
   one trigger shows both.
4. Transmitter off: within half a second LED0 goes out, steer pulses stop,
   throttle keeps pulsing at 1500 us. Transmitter on again: everything
   resumes within a period.

## 5. Servo and ESC

- 220 ohm to 1 k in series with each signal wire, right at the board.
- Common ground between board, receiver, servo and ESC.
- Servo and ESC powered from the ESC's BEC, never from the board's 3.3 V.
  Check the BEC voltage: 6 V or 7.4 V BECs are common on car ESCs, the
  board's regulator survives them, most ELRS receivers do not.
- Which ESC: reversible car ESC or BLHeli in 3D mode stops at 1500 us,
  which is the default `THROTTLE_FAILSAFE` of 992; a one-way ESC wants
  `THROTTLE_FAILSAFE` = 172 (988 us). Set it in `crsf2pwm_c4.qsf` with
  `set_parameter -name THROTTLE_FAILSAFE 172` or change the default in
  the top and rebuild.
- First power-up with the transmitter off: nothing may move. Then
  transmitter on, throttle stick at neutral, the ESC arms.

## 6. Make it permanent

The `.sof` is gone at power-off. The configuration flash keeps it:

```
tools/program.sh --flash
```

This converts the `.sof` to a `.jic` for an EPCS16 and writes it through
the FPGA. If the programmer complains about the flash ID, read the
marking of the small 8-pin chip next to the FPGA and set `FLASH_DEVICE`
(EPCS4, EPCS16, EPCS64; a W25Q16 behaves as EPCS16, a W25Q64 as EPCS64):

```
FLASH_DEVICE=EPCS64 tools/program.sh --flash
```

Power-cycle the board: it must come up with the LEDs dark and start
working as soon as the receiver talks.

## Troubleshooting summary

| Symptom | Look at |
|---|---|
| `quartus_pgm: command not found` | `. tools/quartus-env.sh` in this shell, or use the tools/ scripts, they source it |
| `Error code 87` / chain broken | section 1 |
| Probe LEDs dark | oscillator pin, section 2 |
| LED3 dark with receiver connected | rx wire, receiver protocol setting, receiver power |
| LED3 on, LED2 off | baud rate, inversion, protocol |
| Pulses present but the servo twitches | ground, series resistor, probe compensation before blaming the design |
| Servo fine, ESC does not arm | ESC type versus `THROTTLE_FAILSAFE`, arming sequence in the ESC manual |
| Works until power-off | section 6 |
