#!/bin/bash
echo "------------------------------------------------"
echo "Restoring Surface Pro 4 Media Stack..."
echo "------------------------------------------------"

# 1. Restore Camera Color Tuning (Fixes Green Tint)
sudo mkdir -p /usr/share/libcamera/ipa/ipu3/
sudo tee /usr/share/libcamera/ipa/ipu3/ov8865.yaml > /dev/null <<INNEREOF
version: 1
algorithms:
  - BlackLevelCorrection:
  - Agc:
  - Awb:
  - ToneMapping:
INNEREOF

# 2. Re-link the Manual V4L2Loopback Driver
# This ensures the kernel sees the driver you built from source
sudo depmod -a
sudo modprobe v4l2loopback 2>/dev/null

# 3. Refresh GStreamer Plugin Cache
# Prevents 'Symbol not found' errors after library updates
rm -rf ~/.cache/gstreamer-1.0

# 4. Factory Reset Audio (PipeWire/WirePlumber)
systemctl --user stop pipewire.socket pipewire.service wireplumber 2>/dev/null
rm -rf ~/.local/state/pipewire ~/.local/state/wireplumber
systemctl --user start pipewire.service wireplumber.service

echo "------------------------------------------------"
echo "Success! Audio restored, Colors fixed, and Bridge ready."
echo "You can now run ~/bridge_camera.sh"
echo "------------------------------------------------"
