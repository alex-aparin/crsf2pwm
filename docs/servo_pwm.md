# Servo PWM: what the outputs must produce

## The signal

The command is the width of one positive pulse, repeated every frame. The
line idles low.

```
value 172:   _|‾‾|______________________________|‾‾|_______   988 us high
value 1811:  _|‾‾‾‾|____________________________|‾‾‾‾|_____   2012 us high
              <-------------- 20 ms -------------->
```

| Pulse width | Meaning | CRSF |
|---|---|---|
| 988 us | one end of travel | 172 |
| 1500 us | centre, neutral | 992 |
| 2012 us | other end of travel | 1811 |

Period 20 ms, 50 Hz. This is not duty-cycle PWM: the servo starts a timer
on the rising edge and measures how long the line stays high. A 1500 us
pulse means centre whether it repeats every 20 ms or every 10 ms; the
duty cycle changes from 7.5 % to 15 %, the position does not. Anything
from roughly 3 ms to 25 ms of period works, digital servos and ESCs accept
333..500 Hz, and 50 Hz is what every servo accepts.

The useful information sits in a 1 ms window around 1.5 ms. Pulses of
0 us or 20 ms are not "minimum" and "maximum", they are the absence of a
signal.

## Where the numbers come from

Analogue servos of the 1970s compare the input pulse with a 1..2 ms
one-shot driven by the feedback potentiometer, which fixed the 1..2 ms
window and 1.5 ms centre. The 20 ms frame comes from PPM: up to eight
channels of up to 2 ms each plus a sync gap. The 988 and 2012 endpoints
are the OpenTX convention of 100 % = 512 us, see docs/crsf.md.

## What matters and what does not

- Width accuracy: +-1 us is plenty, a servo resolves about 1..2 us.
- Pulse-to-pulse stability at a constant value: the servo takes jitter as
  commands and buzzes.
- Exactly one rising edge per period. A second pulse inside a period is
  read as a second frame with a nonsense width.
- The period itself is not critical, 20.0 or 19.7 ms makes no difference.

## Outside the window

- No pulses, line low: the servo goes limp and can be turned by hand, the
  ESC sees signal loss. Acceptable failsafe for steering.
- Line constantly high: no edges, no signal.
- Below about 900 us or above about 2100 us: most servos still follow and
  may hit the mechanical stop and overheat. ESCs treat it as minimum or
  maximum or as invalid.
- CRSF 0..2047 through pwm_out gives 880..2159 us. ELRS PWM receivers have
  an "extended" 885..2115 us mode, so passing such values through is
  accepted practice.

## ESC

- Multirotor BLHeli_S / BLHeli_32 with default settings: 988..1000 us is
  zero throttle (armed, motor stopped), 2012 us full throttle, no reverse.
  The ESC arms only after it has seen low throttle at power-up.
- Car ESC, or BLHeli in bidirectional 3D mode: 1500 us is stop, below is
  reverse or brake, above is forward. Needs neutral at power-up.
- Therefore the throttle failsafe is a defined pulse, never silence: 1500
  us for a reversible ESC, 988 us for a one-way one. Check which kind is
  on the car before the integration stage.

## Reference device: ELRS PWM receiver

Does the same job as this project. Defaults: 50 Hz, 988..2012 us, centre
1500. Output modes 50, 60, 100, 160, 333, 400 Hz. Failsafe per channel,
988..2012 us, default 1500 except output 3 (throttle) at 988. No pulses
until the first connection so the ESC can calibrate. Failsafe after 1 s
without a valid packet or at link quality 0.
https://www.expresslrs.org/hardware/pwm-receivers/

## How the outputs are made

Two modules, see docs/design.md for the reasoning.

`pwm_timebase`, one per design:

- Tick of 0.625 us, one CRSF unit, from a fractional divider: at 50 MHz
  an accumulator adds 8 every clock modulo 250, a tick on every wrap,
  50 MHz * 8 / 250 = 1.6 MHz. Ticks are 32, 31, 31, 31 clocks apart.
- Period counter 0..31999 in ticks, 15 bits.
- `start`: the last clock of a period. `head`: high for the first 1408
  ticks of every period, the 880 us that every pulse contains.

`pwm_chan`, one per output:

- On `start` it loads `value` into an 11-bit down counter and latches
  `enable`. The comparator and the width latch of the textbook design are
  replaced by this counter: no adder, no 15-bit compare.
- The pulse is high while `head` or while the counter is not zero; the
  counter runs only after `head` ends. Width = 1408 + value ticks exactly.
- Because value and enable are sampled once per period, a new CRSF frame
  mid-period never tears or retriggers a pulse, and enable = 0 stops the
  pulses from the next period on.

`pwm_out` is the two together for a single output; it is what
`tb_pwm_out` tests.

## Testbench checklist for tb_pwm_out

- Values 172, 992, 1811: widths 987.5, 1500, 2011.875 us, tolerance +-1 us.
- Values 0 and 2047: 880 and 2159.375 us, no overflow.
- Period 20 ms between two rising edges.
- value changed mid-pulse: the current pulse keeps its old width, the
  next one has the new width.
- enable dropped mid-pulse: the current pulse completes, no next pulse.
- Dump only the top level, `$dumpvars(1, ...)`: a period is a million
  clocks and the counter changes every one of them.

## References

- Wikipedia, Servo control: https://en.wikipedia.org/wiki/Servo_control
- BLHeli manuals: https://github.com/bitdump/BLHeli
- Servo datasheets with the pulse spec: Tower Pro SG90 / MG996R (one page,
  widely mirrored); Futaba, Hitec and Savox list "pulse width range" and
  "neutral" per model on their sites.
