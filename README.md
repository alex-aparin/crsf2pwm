# crsf2pwm

[![sim](https://github.com/alex-aparin/crsf2pwm/actions/workflows/sim.yml/badge.svg)](https://github.com/alex-aparin/crsf2pwm/actions/workflows/sim.yml)

CRSF-to-PWM converter for an RC car: receives CRSF from an ExpressLRS or
Crossfire receiver over UART and outputs two servo PWM signals, one for the
steering servo and one for the motor ESC. Plain synthesisable
SystemVerilog, one clock, no vendor primitives. The current target is a
Cyclone IV E development board; a MAX II EPM240 revision exists but the
design is a few logic cells too big for it.

## Layout

```
rtl/          synthesizable code, the only thing that goes into Quartus
tb/           testbenches for Icarus Verilog, one per module plus tb_top
tb/lib/       helpers shared by the testbenches (CRC, frame building)
tb/model/     Python reference model and the test vector generator
tb/vectors/   generated vectors, committed, `make vectors` regenerates them
sim/          Makefile for running simulations, waveforms land here
quartus/      Quartus project: .qpf, one .qsf per revision, .sdc, the clock probe
tools/        build, JTAG check, program, udev rule for the USB Blaster
hw/           KiCad board project
docs/         notes: design, CRSF protocol, servo PWM, pinout, board bring-up
```

## Design

```
rx -> 2 FF sync -> uart_rx -> crsf_parser -> steer_val ----------> pwm_chan -> steer
                                          -> thr_val -> failsafe mux -> pwm_chan -> throttle
                                          -> frame_valid -> link watchdog
                              pwm_timebase -> tick, start, head -> both channels, watchdog
```

`docs/design.md` has the module contracts, the timing, the failsafe policy,
the LE budget and the reasoning behind the choices. `docs/crsf.md` and
`docs/servo_pwm.md` cover the two protocols.

## Tools (Linux)

Simulation and lint from the distribution:

```
sudo apt install iverilog gtkwave make python3 verilator
```

Quartus Prime Lite for synthesis and programming: the small installer from
altera.com (`qinst-lite-linux-<version>.run`, free, needs an account),
components Quartus Prime plus the Cyclone IV device support, and MAX II if
the CPLD revision matters; Questa is not needed. It lands in
`~/altera_lite/<version>/quartus`, which is not on PATH: the scripts in
`tools/` find it by themselves, and `. tools/quartus-env.sh` puts it on
PATH for a shell. The USB Blaster needs `tools/udev-install.sh` once.

Verified with Icarus 11, Verilator 5.052, Quartus Prime Lite 25.1std on
Ubuntu 22.04.

## Simulation

Without make, from the `sim` directory:

```
mkdir build
iverilog -g2012 -Wall -I ../tb/lib -s tb_top -o build/tb_top.vvp ../tb/tb_top.sv ../rtl/*.sv
vvp -N build/tb_top.vvp
gtkwave build/tb_top.vcd
```

With make:

```
cd sim
make                 all testbenches
make tb_top          one testbench
make pwm_out         same as make tb_pwm_out
make waves-tb_top    open waveforms in GTKWave
make lint            Verilator lint, if installed
make vectors         regenerate tb/vectors from the Python model
```

Every testbench is self-checking: it prints `PASS` and exits 0, or prints the
failing checks and exits 1 through `$stop`, so `make` fails and the VS Code
task turns red. A watchdog ends a hung run.

`make waves-tb_top` also loads `sim/tb_top.gtkw` if it exists. Save one from
GTKWave with File > Write Save File to keep the signal layout between runs.

## Continuous integration

`.github/workflows/sim.yml` runs on every push and pull request: all
testbenches in Icarus (`make -C sim -k all`), the Python model self-test with
a check that the committed `tb/vectors/` match the generator, and Verilator
lint of the RTL with `-Wall`. The waveforms of a failed run are attached to
the run as an artifact for a week. The badge above shows the state of `main`.

## VS Code

`.vscode/` has tasks and recommended extensions. Open a testbench or a module
file and press Ctrl+Shift+B: the testbench for that file runs in `sim/`, so
`rtl/pwm_out.sv` and `tb/tb_pwm_out.sv` both run `tb_pwm_out`. Errors from
Icarus appear in the Problems panel. Other tasks under Terminal > Run Task:
waves in GTKWave, run + waves, all testbenches, lint, clean.

The Verilog-HDL extension lints the open file with Icarus on save. The Surfer
extension opens a `.vcd` from `sim/build/` inside VS Code as an alternative
to GTKWave.

## Build and program

The Quartus project `quartus/crsf2pwm.qpf` has three revisions:

| Revision | Target | Output |
|---|---|---|
| `crsf2pwm_c4` | the Saylinx Cyclone IV board, EP4CE6F17C8N | `.sof`, and `.jic` for the flash |
| `clock_probe` | the same board, bring-up helper: oscillator to LEDs and header pins | `.sof` |
| `crsf2pwm` | MAX II EPM240 | `.pof`; does not fit yet, see `docs/design.md` |

Everything goes through the scripts in `tools/`, which find Quartus, check
the cable and print the numbers that matter:

```
tools/udev-install.sh            once: let Quartus open the USB Blaster
tools/jtag-check.sh              cable found? board answering?
tools/build.sh [revision]        compile, default crsf2pwm_c4; errors, warnings by code, LEs, slack
tools/program.sh [revision]      into the FPGA over JTAG, gone at power-off
tools/program.sh --flash         into the configuration flash, loads at every power-up
```

The step-by-step procedure with what to expect at each step, from the
first `jtagconfig` to the car, is `docs/bringup.md`. The GUI works too:
open the `.qpf`, pick the revision under Project > Revisions, Start
Compilation, Programmer.

Current state: the Cyclone IV revision compiles clean in Quartus Prime
Lite 25.1 (273 LEs, Fmax well above 50 MHz) with the pins from
`docs/pinout.md`. Not yet confirmed on the board.