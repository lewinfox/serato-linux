#!/usr/bin/env bash
# One-off host changes the container can't make for itself. Run with sudo.
# Undo: rm the two files below and reboot.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

# 1. Fast Wine sync primitives in the kernel (big CPU/UI win), now and every boot.
modprobe ntsync
echo ntsync > /etc/modules-load.d/serato-wine.conf

# 2. Let the audio group open Pioneer/AlphaTheta HID devices (the container user is in it).
cat > /etc/udev/rules.d/60-serato-wine-hid.rules <<'R'
KERNEL=="hidraw*", ATTRS{idVendor}=="2b73", MODE="0660", GROUP="audio", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="08e4", MODE="0660", GROUP="audio", TAG+="uaccess"
R
udevadm control --reload-rules

echo "done. Replug the controller if it's connected."
