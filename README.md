# crsf2pwm

CRSF-to-PWM converter for an RC car: receives CRSF from an ExpressLRS or
Crossfire receiver over UART and outputs two servo PWM signals, one for the
steering servo and one for the motor ESC. Implemented on an Altera MAX II
CPLD (EPM240).

This is a learning project: the goal is to get comfortable with Verilog,
simulation, and the Quartus flow.

## Layout

```
rtl/       synthesizable code, the only thing that goes into Quartus
tb/        testbenches for Icarus Verilog and a Python reference model
sim/       Makefile for running simulations, waveforms land here
quartus/   Quartus project: .qpf, .qsf, .sdc
hw/        KiCad board project
docs/      notes: CRSF protocol, pinout
```

## Tools (Windows)

- Icarus Verilog with GTKWave: installer from https://bleyer.org/icarus/
  or `winget install Icarus.Verilog`
- Quartus Prime Lite with the MAX II device package
- USB Blaster driver from `<quartus>/drivers/usb-blaster`
- Optional: GNU Make (MSYS2 or `winget install GnuWin32.Make`) for `sim/Makefile`

## Simulation

Without make, from the `sim` directory:

```
mkdir build
iverilog -g2012 -Wall -s tb_top -o build/tb_top.vvp ../tb/tb_top.sv ../rtl/*.sv
vvp -N build/tb_top.vvp
gtkwave build/tb_top.vcd
```

With make:

```
cd sim
make                 all testbenches
make tb_top          one testbench
make waves-tb_top    open waveforms in GTKWave
make lint            Verilator lint, if installed
```

## Build and program

Open `quartus/crsf2pwm.qpf` in Quartus and run Start Compilation, then
Programmer with the USB Blaster. The same from the Quartus command shell:

```
cd quartus
quartus_sh --flow compile crsf2pwm
quartus_pgm -m jtag -o "p;output_files/crsf2pwm.pof"
```

## Roadmap

1. `uart_rx` and `tb_uart_rx`: receive a byte at 420 kbaud.
2. `crc8` and its test: CRC-8/DVB-S2, polynomial 0xD5.
3. `crsf_parser`: parse frame type 0x16, extract two channels, strobe on valid CRC.
4. `pwm_out`: 20 ms period, 988..2012 us pulse from a 172..1811 value.
5. `crsf2pwm_top` and `tb_top`: end-to-end test from bytes on rx to pulse width.
6. Quartus: synthesis, LE count, warnings, timing.
7. Pin assignment, programming, check with a logic analyzer.

## Status

Skeleton only. No logic implemented yet.
