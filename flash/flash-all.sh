#!/bin/sh
# ============================================================================
#  flash-all.sh -- one-click flash script for Linux / macOS
#
#  Usage: put this script, all .img files and avb_pkmd.bin from the fastboot
#         package in the same directory, boot the device into bootloader mode,
#         then run:  sh flash-all.sh
#
#  Steps:
#    1. Verify the device is husky (Pixel 8 Pro)
#    2. Flash the hardware trust root (avb_custom_key) -- REQUIRED before relock
#    3. fastboot flashall to flash all partitions (android-info.txt + fastboot-info.txt)
#
#  After flashing: fastboot reboot to confirm boot, then fastboot flashing lock.
# ============================================================================
set -e

# cd to the script's directory so fastboot flashall finds the .img files
cd "$(dirname "$0")"

command -v fastboot >/dev/null 2>&1 || {
  echo "fastboot not found. Install platform-tools and add it to PATH."
  echo "https://developer.android.com/tools/releases/platform-tools"
  exit 1
}

echo "Available devices:"
fastboot devices -l

product=$(fastboot getvar product 2>&1 | sed -n 's/^product:[[:space:]]*//p' | tr -d '\r')
if [ "$product" != "husky" ]; then
  echo "Error: this package is for husky (Pixel 8 Pro), but device is ${product:-unknown}"
  exit 1
fi

echo ""
echo "=== 1/2 Flash hardware trust root: avb_custom_key ==="
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_pkmd.bin

echo ""
echo "=== 2/2 Flash all partitions: fastboot flashall ==="
fastboot flashall --skip-reboot

echo ""
echo "Flash complete."
echo "Next steps:"
echo "  fastboot reboot          # confirm the system boots"
echo "  fastboot flashing lock   # relock after confirming (trust root must be flashed)"
