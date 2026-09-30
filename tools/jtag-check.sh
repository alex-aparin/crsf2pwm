#!/usr/bin/env bash
# Is the USB Blaster there, and does the board answer on JTAG?
#
#   tools/jtag-check.sh
#
# Exit 0 when a device is found in the chain, 1 otherwise, with a hint.

set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/quartus-env.sh"
command -v jtagconfig >/dev/null || exit 1

out=$(jtagconfig 2>&1)
echo "$out"

if grep -q 'No JTAG hardware' <<<"$out"; then
  cat <<'EOF'
-> no cable. Plug in the USB Blaster. On a fresh Linux install the udev
   rule is missing: run tools/udev-install.sh once, then replug.
EOF
  exit 1
fi

if grep -q 'chain broken' <<<"$out"; then
  cat <<'EOF'
-> cable ok, board silent. In order of likelihood:
   1. board power: switch ON, power LED lit, mini-USB plugged into a supply
   2. ribbon in the header marked JTAG (not the AS header), seated, key aligned
   3. 3.3 V between JTAG header pins 4 and 2 while the board is on
   4. the ribbon itself: continuity on all ten wires, TDO is pin 3
EOF
  exit 1
fi

case "$out" in
  *020F10DD*) echo "-> EP4CE6 found, ready to program" ;;
  *020F20DD*) echo "-> EP4CE10 found, ready to program" ;;
  *020A10DD*) echo "-> EPM240 found, ready to program" ;;
  *)          echo "-> a device answered, check that it is the one in the revision's .qsf" ;;
esac
exit 0
