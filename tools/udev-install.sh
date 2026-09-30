#!/usr/bin/env bash
# Install the udev rule that lets Quartus open the USB Blaster without root.
# Needs sudo once. Replug the cable afterwards.

set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
sudo cp "$here/tools/51-usbblaster.rules" /etc/udev/rules.d/51-usbblaster.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "installed /etc/udev/rules.d/51-usbblaster.rules; replug the USB Blaster, then tools/jtag-check.sh"
