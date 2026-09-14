#!/bin/bash
set -e

echo "=================================================="
echo " Surface Pro 4 Kernel & Boot Configuration Tool   "
echo "=================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] This script requires root privileges."
  echo "Please run: sudo ./configure_surface_kernel.sh"
  exit 1
fi

echo "[1/4] Ensuring linux-surface repository packages are installed and current..."
apt-get update
apt-get install -y linux-image-surface linux-headers-surface iptsd libwacom-surface

echo "[2/4] Removing Ubuntu generic HWE metapackages..."
apt-get remove -y \
  linux-generic-hwe-24.04 \
  linux-image-generic-hwe-24.04 \
  linux-headers-generic-hwe-24.04 \
  linux-generic \
  linux-image-generic \
  linux-headers-generic 2>/dev/null || true

echo "[3/4] Purging unused generic 7.0 kernels..."
apt-get purge -y \
  linux-image-7.0.0-*-generic \
  linux-headers-7.0.0-*-generic 2>/dev/null || true

echo "[4/4] Updating GRUB bootloader configuration..."
update-grub

echo "=================================================="
echo " Configuration complete!"
echo " Available kernels in /boot:"
ls -lh /boot/vmlinuz-*
echo "=================================================="
echo " To boot into the Surface kernel, reboot now:"
echo "   sudo reboot"
echo "=================================================="
