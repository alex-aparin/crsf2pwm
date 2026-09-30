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

In the current `crsf2pwm_c4.qsf` the CRSF input `rx` sits on M2, the
board's own USB-UART bridge. Plug the board's mini-USB into the PC (it
powers the board and shows up as `/dev/ttyUSB0`; the user must be in the
`dialout` group) and play the receiver with `tools/crsf_send.py`, which
builds the frames with `tb/model/crsf.py`. Needs pyserial:
`sudo apt install python3-serial`.

```
tools/crsf_send.py --steer 172 --throttle 1811   # fixed values: 987.5 us on pin 5, 2011.9 us on pin 7
tools/crsf_send.py --sweep 4                     # steer sweeps end to end every 4 s: watch the falling edge move
tools/crsf_send.py --interactive                 # a/d steer, w/s throttle, c centre, 1..9 presets, q quit
tools/crsf_send.py --bad-crc                     # every second frame spoiled: outputs must not twitch
tools/crsf_send.py --duration 3                  # stops after 3 s: LED0 off and steer silent half a second later
```

The bridge is a CH340; it cannot do exactly 420000 baud and lands about
1.5 % off, well inside the receiver's tested +-3 %. LED3 glows as soon as
the script runs, LED2 and LED0 follow with the first good frame, LED1
blinks.

## 4. Receiver

The receiver needs a header pin: in `crsf2pwm_c4.qsf` swap the two `rx`
lines so that `rx` is on T14 (the M2 line is left there commented out),
rebuild and reprogram. Then receiver TX to right header pin 3 (T14),
receiver GND to pin 1, receiver 5 V from pin 2 (the board's 5 V rail) or
from a separate 5 V supply; never 5 V onto a signal pin. Receiver RX stays
open. Receiver settings: protocol CRSF, not inverted, 420000 baud.

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

This converts the `.sof` to a `.jic` for an EPCS4, the 4 Mbit flash the
Saylinx board answers with (silicon ID 0x12; the EP4CE6 image needs about
3 Mbit), and writes it through the FPGA. On another board the programmer
prints the ID it found in `Can't recognize silicon ID`: 0x10 EPCS1, 0x12
EPCS4, 0x14 EPCS16, 0x16 EPCS64, 0x18 EPCS128, W25Qxx parts report the
code of the EPCS of the same size. Then:

```
FLASH_DEVICE=EPCS16 tools/program.sh --flash
```

Power-cycle the board: it must come up with the LEDs dark and start
working as soon as the receiver talks.

## Troubleshooting summary

| Symptom | Look at |
|---|---|
| `quartus_pgm: command not found` | `. tools/quartus-env.sh` in this shell, or use the tools/ scripts, they source it |
| Board on mini-USB but no `/dev/ttyUSB0` | Ubuntu's `brltty` grabs every CH340 as a Braille display and detaches the driver a second after it appears (`dmesg` shows `claimed by ch341 while 'brltty'`): `sudo apt purge brltty`, replug |
| `Error code 87` / chain broken | section 1 |
| Probe LEDs dark | oscillator pin, section 2 |
| LED3 dark with receiver connected | rx wire, receiver protocol setting, receiver power |
| LED3 on, LED2 off | baud rate, inversion, protocol |
| Pulses present but the servo twitches | ground, series resistor, probe compensation before blaming the design |
| Servo fine, ESC does not arm | ESC type versus `THROTTLE_FAILSAFE`, arming sequence in the ESC manual |
| Works until power-off | section 6 |
