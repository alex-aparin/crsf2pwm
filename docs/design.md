# Design notes

What each module promises, how the pieces fit, and why they look the way
they do. Numbers are for 50 MHz and 420 kbaud unless said otherwise.

## Block diagram

```
          +------+    +---------+    +-------------+  steer_val   +----------+
rx ------>| sync |--->| uart_rx |--->| crsf_parser |------------->| pwm_chan |---> steer
          | 2 FF |    |         |    |             |  thr_val     +----------+
          +------+    +---------+    |             |----+  +--+   +----------+
                       data, valid   |             |    +->|mux|-->| pwm_chan |---> throttle
                                     +-------------+       +--+   +----------+
                                        frame_valid |         ^ THROTTLE_FAILSAFE
                                                    v         |
                                     +---------------+  link_ok, ever_valid
                                     | link watchdog |<------------------+
                                     +---------------+                   |
                                            ^ start                      |
                                     +--------------+  tick, start, head |
                                     | pwm_timebase |--------------------+--> both channels
                                     +--------------+
```

One clock, 50 MHz, everywhere. No derived clocks: the 1.6 MHz tick is a
one-clock enable. No reset: every register has a power-up value and the
all-zero state is the safe one (no pulses).

## Modules

| Module | Job | Contract |
|---|---|---|
| `uart_rx` | 8N1 bytes from a synchronised rx | `valid` is a one-clock strobe, `data` holds the byte in that clock. `frame_err` strobes instead of `valid` when the stop bit is low; a break gives one error. |
| `crc8` | CRC-8/DVB-S2, byte-parallel | `clear` then `valid` per byte; `crc` is the CRC of everything fed since `clear`, available in the clock after the last byte. |
| `crsf_parser` | frames in, two channels out | `frame_valid` strobes once per RC frame with a good CRC; `ch_a`, `ch_b` change only in that clock. Everything else is consumed and ignored. Silence of 100 us inside a frame aborts it. |
| `pwm_timebase` | 0.625 us tick, 20 ms period | `tick` one-clock enable at 1.6 MHz average; `start` the last clock of a period; `head` high for the first 1408 ticks of a period. |
| `pwm_chan` | one servo pulse | Samples `value` and `enable` on `start`. Width = 1408 + value ticks, exact. `enable` = 0 stops pulses from the next period on. |
| `pwm_out` | timebase + one channel | The standalone single-output module; `tb_pwm_out` tests it. |
| `crsf2pwm_top` | the car | Wires the above, adds the synchroniser, the link watchdog and the throttle failsafe mux. |

## Timing

**UART.** 119 clocks per bit. The start bit is detected by level and
confirmed half a bit later; data bits are sampled every 119 clocks after
that, i.e. at 0.5, 1.5 .. 8.5 bit periods, the stop bit at 9.5. A baud
rate error e moves the last sample by 9.5 e; +-3 % is 0.29 bit, the window
is +-0.5. `valid` comes 9.5 bit periods after the start edge.

**Parser.** One state step per byte. The CRC register is cleared by the
length byte, fed by the type and payload bytes, and compared with the CRC
byte in the clock it arrives; `frame_valid` is registered, so it strobes
one clock after the CRC byte's `valid`. Payload byte b is on the bus when
the down counter `remaining` equals 23 - b; the channel bit map is built
from that at elaboration time, so extraction is enables on the shadow
registers, no shifting.

**Timebase.** 50 MHz / 1.6 MHz = 31.25 clocks per tick; the accumulator
adds 8 modulo 250, ticks come 32, 31, 31, 31 clocks apart and every 125
clocks hold exactly 4. Period = 32000 ticks = 1 000 000 clocks = 20 ms.

**Channel.** Both edges of `pwm` are two clocks after the tick that causes
them, so the width is exact to the tick and the jitter is one clock. The
first pulse after `enable` rises is a full pulse; the last one after it
falls completes.

**Latency, frame to output.** The frame takes 0.62 ms on the wire, the
parser has the channels at its last byte, and the channel picks them up
at the next `start`: 0.6 to 20.6 ms, average about 10 ms. At 50 Hz that is
inherent; a faster PWM rate would only help if the servo accepted it.

## Failsafe policy

| State | steer | throttle |
|---|---|---|
| Power-up, no frame yet | no pulses | no pulses |
| Link up | channel | channel |
| No good RC frame for `FAILSAFE_PERIODS` periods (25 = 0.48..0.50 s) | no pulses, servo goes limp | pulses at `THROTTLE_FAILSAFE`: 992 = 1500 us, stop for a reversible car ESC |
| Frames again | channel from the next period | channel from the next period |

Why no pulses at power-up: an ESC arms only after it has seen a safe
throttle, and with no signal it just waits; nothing moves while the
transmitter is off. ELRS PWM receivers do the same. Why throttle keeps
pulsing in failsafe: silence would make a car ESC coast or beep, a defined
neutral pulse stops it. For a one-way (multirotor style) ESC set
`THROTTLE_FAILSAFE` to 172, its zero throttle. Check which ESC is on the
car before the first drive.

The watchdog counts `start` strobes since the last `frame_valid`: a 5-bit
counter instead of a 25-bit one at 50 MHz. Bad frames do not feed it, so a
receiver that keeps sending garbage still trips it.

## Resources

Measured with Quartus Prime Lite 25.1std, default settings, no pins
assigned. Logic cells after synthesis per module (own cells in
parentheses), then what the fitter needed.

| Module | Cyclone IV E, LCs | MAX II, LCs |
|---|---|---|
| `crsf_parser` incl. `crc8` | 99 (78) | 134 (110) |
| `crc8` | 21 | 24 |
| `pwm_timebase` | 47 | 56 |
| `pwm_chan` steer | 17 | 18 |
| `pwm_chan` throttle, absorbs the failsafe mux | 28 | 28 |
| `uart_rx` | 32 | 38 |
| top glue: sync, watchdog | 12 | 12 |
| **Synthesis total** | **235** | **286** |
| **Fitter** | **264 of 6272, 160 registers** | **266 needed, 240 available: does not fit** |

Cyclone IV: 4 % of an EP4CE6, Fmax 132 MHz against the 50 MHz required,
worst setup slack 12 ns. That is the target board now.

MAX II: the estimate of 220 was 20 % optimistic, mostly in the parser
(110 own cells against 80 guessed: the byte-position decodes and the
enable muxes on 44 shadow/output bits cost more than one LE per bit) and
the timebase (56 against 40: two 15-bit compares plus the accumulator).
The EPM240 is 26 cells short. If that target ever matters again, in order
of preference:

1. Count the parser's silence timeout in ticks from the timebase instead of
   clocks: the 13-bit gap counter becomes 8 bits, about 8 LEs.
2. Replace the timebase's two 15-bit equality compares by a single
   terminal-count flag from a down counter, about 8 LEs.
3. Drop the parser's output registers and let the channels sample the
   shadows, gated by a "frame complete and good" flag: 22 LEs, but the
   `ch_a`/`ch_b` contract changes and a channel may skip a period.
4. `OPTIMIZATION_TECHNIQUE AREA` and `AUTO_PACKED_REGISTERS_MAX` in the
   .qsf, worth a few percent for free.

Decisions already taken with the budget in mind, and still worth keeping
on Cyclone IV because they cost nothing: one timebase shared by both
channels, a down counter per channel instead of latch plus comparator,
`uart_rx` exposing its shift register as `data`, a watchdog that counts
periods rather than clocks.

## Verification

Every testbench is self-checking, prints `PASS` or the failing checks, and
exits through `$finish` or `$stop` so that `vvp -N` returns 0 or 1.
Testbenches read on `negedge clk`, drive UART lines in nanoseconds, and
carry a watchdog against hangs.

| Testbench | Proves | Notes |
|---|---|---|
| `tb_crc8` | CRC against 1000 vectors from the Python model plus the catalogue value 0xBC, clear mid-stream, gaps, back-to-back bytes | vectors in `tb/vectors/`, `make vectors` regenerates |
| `tb_uart_rx` | single bytes, back-to-back, +-3 % baud, glitch rejected, framing error, break, one-clock strobes, strobe count equals bytes sent | |
| `tb_crsf_parser` | two parsers on one stream (channels 0/1 and 3/15): good frames, extremes 0 and 2047, bad CRC, foreign types and lengths, garbage, bogus lengths, doubled sync, header-only, truncated frames with and without a gap, back-to-back frames, wire-speed spacing, foreign address; outputs change only in the strobe clock | |
| `tb_pwm_out` | widths for 172/992/1811/0/2047 within +-1 us, period 20 ms, value change mid-pulse, no retrigger, enable drop mid-pulse, silence while disabled | about 40 s |
| `tb_top` | bytes on rx to pulse widths; power-up silence, link up, value changes, bad and foreign frames between good ones, failsafe not premature, failsafe reached, throttle neutral in failsafe, recovery | `FAILSAFE_PERIODS` = 3 to keep it short; about 1.5 min |

The same suite runs in GitHub Actions on every push
(`.github/workflows/sim.yml`), together with the Python model self-test, a
check that the committed vectors match the generator, and Verilator lint.
`make lint` with `-Wall` is clean under Verilator 5.052 for both
`crsf2pwm_top` and `pwm_out`.

Synthesis: both Quartus revisions compile with 0 errors; the Cyclone IV
revision fits and meets timing, the MAX II one does not fit (see
Resources). Not verified yet: the design on a board.

## Decisions worth remembering

- **Level-triggered start detection with a half-bit confirmation** rather
  than an edge detector: one register less, and the confirmation is what
  rejects glitches anyway.
- **`S_WAIT` after a framing error**: without it a break condition, which
  is what an unplugged receiver looks like, would produce a byte and an
  error every ten bit periods.
- **Byte-parallel CRC**: the loop in a function unrolls to XORs. The
  bit-serial variant the roadmap mentions would save a few LEs at the cost
  of a counter and an interlock; not worth it while the budget holds.
- **Silence timeout in the parser** is what makes a frame that stops short
  cost nothing. A truncated frame glued to the next one with no gap still
  loses that next frame to the CRC check (`tb_crsf_parser` case 8); no
  byte-level parser can tell those apart, and receivers do leave gaps.
- **`frame_valid` only for RC frames**: the watchdog then measures exactly
  what matters, "do we have fresh stick data", and link statistics frames
  cannot keep a dead link alive.
- **Shadows plus output registers in the parser** are the price of the
  atomic-update contract: a bad frame never shows, the channels are never
  half old and half new.
- **Sized constants through casts.** `localparam logic [W-1:0] X = W'(expr)`
  is the one form that Icarus 11 accepts, Verilator lints clean and Quartus
  does not truncate silently. Plain `= expr` draws WIDTHTRUNC from
  Verilator, a plain `int` constant draws WIDTHEXPAND at every use.
- **Verilator's PROCASSINIT is switched off** in `make lint`: it objects to
  registers initialised in their declaration and written in `always_ff`,
  which is exactly the no-reset style chosen here.
- **Icarus 11 quirks met on the way**, so nobody trips again: no `'{}`
  array literals in declarations, `before` is a keyword, an initialiser on
  a variable declared inside a `begin` block runs once at time 0, empty
  `()` task ports draw a warning, and `$readmemh` warns when the array is
  larger than the file, hence the generated `crc8_size.svh`.
