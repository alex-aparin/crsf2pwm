# crsf2pwm

CRSF-to-PWM converter for an RC car: receives CRSF from an ExpressLRS or
Crossfire receiver over UART and outputs two servo PWM signals, one for the
steering servo and one for the motor ESC. Implemented on an Altera MAX II
CPLD (EPM240).

## Layout

```
rtl/          synthesizable code, the only thing that goes into Quartus
tb/           testbenches for Icarus Verilog, one per module plus tb_top
tb/lib/       helpers shared by the testbenches (CRC, frame building)
tb/model/     Python reference model and the test vector generator
tb/vectors/   generated vectors, committed, `make vectors` regenerates them
sim/          Makefile for running simulations, waveforms land here
quartus/      Quartus project: .qpf, .qsf, .sdc
hw/           KiCad board project
docs/         notes: design, CRSF protocol, servo PWM, pinout
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

## Tools (Windows)

- Icarus Verilog with GTKWave: installer from https://bleyer.org/icarus/
  or `winget install Icarus.Verilog`
- Quartus Prime Lite with the MAX II device package
- USB Blaster driver from `<quartus>/drivers/usb-blaster`
- Optional: GNU Make (MSYS2 or `winget install GnuWin32.Make`) for `sim/Makefile`
- Optional: Python 3, only to regenerate `tb/vectors/` or to play with the model

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

Open `quartus/crsf2pwm.qpf` in Quartus and run Start Compilation, then
Programmer with the USB Blaster. The same from the Quartus command shell:

```
cd quartus
quartus_sh --flow compile crsf2pwm
quartus_pgm -m jtag -o "p;output_files/crsf2pwm.pof"
```