# Simulation with Icarus Verilog. Requires GNU Make (MSYS2 on Windows).
# The plain commands are listed in README.md if make is not available.
#
#   make               all testbenches
#   make tb_top        one testbench (file name in tb/ without extension)
#   make pwm_out       same as make tb_pwm_out, handy from an editor
#   make waves-tb_top  open waveforms, loads tb_top.gtkw from here if present
#   make lint          Verilator lint
#   make vectors       regenerate tb/vectors from the Python model
#   make clean

IVERILOG  ?= iverilog
VVP       ?= vvp
GTKWAVE   ?= gtkwave
VERILATOR ?= verilator

IVFLAGS ?= -g2012 -Wall -I ../tb/lib

RTL := $(wildcard ../rtl/*.sv)
TBS := $(patsubst ../tb/%.sv,%,$(wildcard ../tb/tb_*.sv))
TOP ?= crsf2pwm_top

# tb_pwm_out and pwm_out name the same testbench, so an editor can run the
# test for whichever file is open, the module or its testbench.
MODS  := $(patsubst tb_%,%,$(TBS))
tbname = $(if $(filter tb_%,$1),$1,tb_$1)

.PHONY: all clean lint vectors $(TBS) $(MODS)

all: $(TBS)

$(TBS): %: build/%.vvp
	$(VVP) -N $<

$(MODS): %: tb_%

build/%.vvp: ../tb/%.sv $(RTL) | build
	$(IVERILOG) $(IVFLAGS) -s $* -o $@ $^

build:
	mkdir -p build

# Signal layout: save it from GTKWave with File > Write Save File as
# sim/tb_x.gtkw, it is picked up next time and is worth committing.
#
# GTKWave is started in its own session (setsid, util-linux) so it survives
# when the shell that launched it exits, e.g. a VS Code task terminal. Where
# setsid is missing it is a plain background job.
DETACH := $(if $(shell command -v setsid 2>/dev/null),setsid -f,)

waves-%:
	$(DETACH) $(GTKWAVE) build/$(call tbname,$*).vcd $(wildcard $(call tbname,$*).gtkw) &

# PROCASSINIT is Verilator's objection to registers that get their power-up
# value in the declaration and are then written in always_ff. That is the
# style of this design on purpose: no reset, see docs/design.md. -Wfuture-
# lets older Verilators that do not know the code accept the -Wno-.
lint:
	$(VERILATOR) --lint-only -Wall -Wfuture-PROCASSINIT -Wno-PROCASSINIT --top-module $(TOP) $(RTL)

# Test vectors are committed; this only needs Python when they change.
vectors:
	python3 ../tb/model/crsf.py
	python3 ../tb/model/gen_vectors.py

clean:
	rm -rf build
