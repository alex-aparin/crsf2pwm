#!/usr/bin/env bash
# Program a revision into the board through the USB Blaster.
#
#   tools/program.sh                    crsf2pwm_c4 into the FPGA: .sof, lost at power-off
#   tools/program.sh clock_probe        the bring-up probe
#   tools/program.sh --flash            crsf2pwm_c4 into the configuration flash: .jic,
#                                       loads by itself at every power-up
#   tools/program.sh crsf2pwm           MAX II: .pof, permanent by itself
#
# --flash converts the .sof with quartus_cpf. The flash type defaults to
# EPCS16; set FLASH_DEVICE to what is on the board if the programmer
# refuses (EPCS4, EPCS64, or the EPCSxx equivalent of a W25Qxx part).
#
# Builds nothing: run tools/build.sh first.

set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)

flash=0
if [ "${1:-}" = "--flash" ]; then flash=1; shift; fi
rev=${1:-crsf2pwm_c4}

. "$here/tools/quartus-env.sh"
command -v quartus_pgm >/dev/null || exit 1
cd "$here/quartus" || exit 1

"$here/tools/jtag-check.sh" || exit 1

sof=output_files/$rev.sof
pof=output_files/$rev.pof

if [ -f "$pof" ] && [ ! -f "$sof" ]; then
  # CPLD: the .pof goes straight into the device's flash.
  echo "program: $pof"
  exec quartus_pgm -m jtag -o "p;$pof"
fi

[ -f "$sof" ] || { echo "program: no $sof, run tools/build.sh $rev"; exit 1; }

if [ $flash = 0 ]; then
  echo "program: $sof (volatile)"
  exec quartus_pgm -m jtag -o "p;$sof"
fi

# Flash: the device name for quartus_cpf is the part without speed grade.
dev=$(sed -nE 's/^set_global_assignment -name DEVICE ([A-Za-z0-9]+).*/\1/p' "$rev.qsf")
dev=${dev%%[CI][0-9]*}
: "${FLASH_DEVICE:=EPCS16}"
jic=output_files/$rev.jic

echo "program: converting $sof to $jic for $FLASH_DEVICE behind $dev"
quartus_cpf -c -d "$FLASH_DEVICE" -s "$dev" "$sof" "$jic" || exit 1
echo "program: writing the flash, this takes a minute"
quartus_pgm -m jtag -o "ipv;$jic" || exit 1
echo "done. Power-cycle the board: it must come up running by itself."
