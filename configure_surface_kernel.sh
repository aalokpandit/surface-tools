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

echo "[1/4] Ensuring linux-surface 6.18 kernel, touch, and media packages are installed..."
apt-get update
apt-get install -y \
  linux-image-6.18.7-surface-1 \
  linux-headers-6.18.7-surface-1 \
  iptsd \
  libwacom-surface \
  v4l2loopback-utils \
  git \
  build-essential

# Prevent auto-upgrading to 6.19 until IPU3 upstream regression is fixed
apt-mark hold linux-image-6.18.7-surface-1 linux-headers-6.18.7-surface-1 2>/dev/null || true
apt-get remove -y linux-image-surface linux-headers-surface 2>/dev/null || true

echo "[1b/4] Building and installing compatible v4l2loopback driver for 6.18 kernel..."
TMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/umlaeute/v4l2loopback.git "$TMP_DIR/v4l2loopback"
make -C "$TMP_DIR/v4l2loopback" KERNELRELEASE="6.18.7-surface-1"
make -C "$TMP_DIR/v4l2loopback" KERNELRELEASE="6.18.7-surface-1" install
depmod -a 6.18.7-surface-1
rm -rf "$TMP_DIR"

echo "[1c/4] Enabling camera modules to load automatically on boot..."
mkdir -p /etc/modules-load.d
echo -e "dw9719\nv4l2loopback" > /etc/modules-load.d/surface-camera.conf

echo "[2/4] Removing Ubuntu generic HWE metapackages..."
apt-get remove -y \
  linux-generic-hwe-24.04 \
  linux-image-generic-hwe-24.04 \
  linux-headers-generic-hwe-24.04 \
  linux-generic \
  linux-image-generic \
  linux-headers-generic 2>/dev/null || true

echo "[3/4] Purging broken/unused 6.19 and generic 7.0 kernels..."
apt-get purge -y \
  linux-image-6.19.8-surface-3 \
  linux-headers-6.19.8-surface-3 \
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
