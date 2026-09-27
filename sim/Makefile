# Simulation with Icarus Verilog. Requires GNU Make (MSYS2 on Windows).
# The plain commands are listed in README.md if make is not available.
#
#   make               all testbenches
#   make tb_top        one testbench (file name in tb/ without extension)
#   make waves-tb_top  open waveforms
#   make lint          Verilator lint
#   make clean

IVERILOG  ?= iverilog
VVP       ?= vvp
GTKWAVE   ?= gtkwave
VERILATOR ?= verilator

IVFLAGS ?= -g2012 -Wall

RTL := $(wildcard ../rtl/*.sv)
TBS := $(patsubst ../tb/%.sv,%,$(wildcard ../tb/tb_*.sv))
TOP ?= crsf2pwm_top

.PHONY: all clean lint $(TBS)

all: $(TBS)

$(TBS): %: build/%.vvp
	$(VVP) -N $<

build/%.vvp: ../tb/%.sv $(RTL) | build
	$(IVERILOG) $(IVFLAGS) -s $* -o $@ $^

build:
	mkdir -p build

waves-%:
	$(GTKWAVE) build/$*.vcd &

lint:
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) $(RTL)

clean:
	rm -rf build
