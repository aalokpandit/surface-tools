#!/bin/bash
set -e

echo "Applying IPU3 ov8865 camera color tuning fix..."

mkdir -p /usr/share/libcamera/ipa/ipu3/

cat << 'EOF' > /usr/share/libcamera/ipa/ipu3/ov8865.yaml
version: 1
algorithms:
  - Af:
  - Agc:
  - Awb:
  - ToneMapping:
EOF

ln -sf /usr/share/libcamera/ipa/ipu3/ov8865.yaml /usr/share/libcamera/ipa/ipu3/INT347A.yaml
cp -f /usr/share/libcamera/ipa/ipu3/ov8865.yaml /usr/share/libcamera/ipa/ipu3/uncalibrated.yaml

echo "Done! ov8865 tuning files updated successfully."
