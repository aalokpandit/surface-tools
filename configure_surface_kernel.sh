#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "=================================================="
echo " Surface Pro 4 Kernel & Boot Configuration Tool   "
echo "=================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] This script requires root privileges."
  echo "Please run: sudo ./configure_surface_kernel.sh"
  exit 1
fi

echo "[1/4] Removing generic metapackages and broken 7.0/6.19 kernels..."
apt-get remove -y \
  linux-generic-hwe-24.04 \
  linux-image-generic-hwe-24.04 \
  linux-headers-generic-hwe-24.04 \
  linux-generic \
  linux-image-generic \
  linux-headers-generic 2>/dev/null || true

TO_PURGE=$(dpkg -l 'linux-image-7.0.0-*' 'linux-headers-7.0.0-*' 'linux-modules-7.0.0-*' 'linux-tools-7.0.0-*' 'linux-image-6.19*' 'linux-headers-6.19*' 2>/dev/null | awk '/^ii/{print $2}')
if [ -n "$TO_PURGE" ]; then
  apt-get purge -y $TO_PURGE
fi

echo "[2/4] Ensuring linux-surface 6.18 kernel, touch, and media packages are installed..."
apt-get update
apt-get install -y \
  linux-image-6.18.7-surface-1 \
  linux-headers-6.18.7-surface-1 \
  iptsd \
  v4l2loopback-utils \
  git \
  build-essential

# Prevent auto-upgrading to 6.19 until IPU3 upstream regression is fixed
apt-mark hold linux-image-6.18.7-surface-1 linux-headers-6.18.7-surface-1 2>/dev/null || true
apt-get remove -y linux-image-surface linux-headers-surface 2>/dev/null || true

echo "[3/4] Building and installing compatible v4l2loopback driver for 6.18 kernel..."
TMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/umlaeute/v4l2loopback.git "$TMP_DIR/v4l2loopback"
make -C "$TMP_DIR/v4l2loopback" KERNELRELEASE="6.18.7-surface-1"
make -C "$TMP_DIR/v4l2loopback" KERNELRELEASE="6.18.7-surface-1" install
depmod -a 6.18.7-surface-1
rm -rf "$TMP_DIR"

echo "[3b/4] Enabling camera modules to load automatically on boot..."
mkdir -p /etc/modules-load.d
echo -e "dw9719\nv4l2loopback" > /etc/modules-load.d/surface-camera.conf

echo "[4/4] Updating GRUB bootloader configuration..."
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub 2>/dev/null || true
sed -i 's/^GRUB_TIMEOUT=0/GRUB_TIMEOUT=3/' /etc/default/grub 2>/dev/null || true
update-grub

echo "=================================================="
echo " Configuration complete!"
echo " Available kernels in /boot:"
ls -lh /boot/vmlinuz-*
echo "=================================================="
echo " To boot into the Surface kernel, reboot now:"
echo "   sudo reboot"
echo "=================================================="
