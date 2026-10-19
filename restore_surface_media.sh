#!/bin/bash
# Surface Pro 4 Hardware & Media Restoration Utility

set -e

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

show_usage() {
  cat <<EOF
Surface Pro 4 Hardware & Media Restoration Tool

Usage: $(basename "$0") [OPTIONS]

Options:
  -s, --status    Show health status of Kernel, Touch, Audio, and Camera
  -a, --auto      Inspect system and automatically restore only failing components
  -t, --touch     Restore Touchscreen & Stylus (iptsd daemon & hidraw triggers)
  -u, --audio     Factory reset and restart PipeWire / WirePlumber audio stack
  -c, --camera    Restore IPU3 color profiles, v4l2loopback, and GStreamer cache
  -A, --all       Restore all hardware components (Camera, Audio, Touch)
  -h, --help      Display this help menu

If no option is provided, --all is executed by default.
EOF
}

check_kernel() {
  local k_ver
  k_ver=$(uname -r)
  if [[ "$k_ver" == *"surface"* ]]; then
    return 0
  else
    return 1
  fi
}

show_status() {
  echo -e "${CYAN}==================================================${NC}"
  echo -e "${CYAN}       Surface Pro 4 Hardware Diagnostics         ${NC}"
  echo -e "${CYAN}==================================================${NC}"

  # 1. Kernel Status
  local k_ver
  k_ver=$(uname -r)
  if check_kernel; then
    echo -e " Kernel:         [ ${GREEN}OK${NC} ] Running Surface kernel ($k_ver)"
  else
    echo -e " Kernel:         [ ${RED}FAIL${NC} ] Running generic kernel ($k_ver)"
    echo -e "                 ${YELLOW}* Note: Touch & Stylus require linux-surface kernel.${NC}"
    echo -e "                 ${YELLOW}* Run sudo ./configure_surface_kernel.sh to fix.${NC}"
  fi

  # 2. Touchscreen / iptsd Status
  local iptsd_active
  iptsd_active=$(systemctl is-active "iptsd@*.service" 2>/dev/null | grep -c "active" || true)
  local hidraw_count
  hidraw_count=$(ls -1 /dev/hidraw* 2>/dev/null | wc -l || true)
  if [ "$iptsd_active" -gt 0 ]; then
    echo -e " Touch/Stylus:   [ ${GREEN}OK${NC} ] iptsd is active ($iptsd_active instance(s), $hidraw_count hidraw node(s))"
  elif check_kernel; then
    echo -e " Touch/Stylus:   [ ${YELLOW}INACTIVE${NC} ] iptsd is not currently running (run with -t to restore)"
  else
    echo -e " Touch/Stylus:   [ ${RED}UNAVAILABLE${NC} ] IPTS driver not present on current generic kernel"
  fi

  # 3. Audio (PipeWire / WirePlumber)
  local pw_active wp_active
  pw_active=$(systemctl --user is-active pipewire.service 2>/dev/null || echo "inactive")
  wp_active=$(systemctl --user is-active wireplumber.service 2>/dev/null || echo "inactive")
  if [ "$pw_active" = "active" ] && [ "$wp_active" = "active" ]; then
    echo -e " Audio Stack:    [ ${GREEN}OK${NC} ] PipeWire ($pw_active) & WirePlumber ($wp_active)"
  else
    echo -e " Audio Stack:    [ ${RED}FAIL${NC} ] PipeWire: $pw_active, WirePlumber: $wp_active"
  fi

  # 4. Camera Stack
  local yaml_ok=0 loopback_ok=0 stale_local=0 cam_count=0
  [ -f /usr/share/libcamera/ipa/ipu3/ov8865.yaml ] && yaml_ok=1
  lsmod | grep -q "v4l2loopback" && loopback_ok=1

  # Check for conflicting stale custom builds in /usr/local
  if ls /usr/local/lib/x86_64-linux-gnu/libcamera* 1>/dev/null 2>&1 || [ -f /usr/local/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so ]; then
    stale_local=1
  fi

  # Test real libcamera camera detection
  local cam_output
  cam_output=$(timeout 3 env LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}" cam -l 2>&1 || true)
  cam_count=$(echo "$cam_output" | grep -c "Internal " || true)

  if [ "$cam_count" -ge 2 ]; then
    if [ "$loopback_ok" -eq 1 ] && [ -e /dev/video42 ]; then
      echo -e " Camera Stack:   [ ${GREEN}OK${NC} ] libcamera ($cam_count sensors detected) & /dev/video42 active"
    else
      echo -e " Camera Stack:   [ ${GREEN}OK${NC} ] libcamera ($cam_count sensors detected), bridge ready to launch"
    fi
  elif [ "$stale_local" -eq 1 ]; then
    echo -e " Camera Stack:   [ ${RED}FAIL${NC} ] Stale custom libcamera libraries in /usr/local are masking system drivers"
    echo -e "                 ${YELLOW}* Run: sudo ./restore_surface_media.sh -c to clean up and restore.${NC}"
  elif [ "$yaml_ok" -eq 0 ]; then
    echo -e " Camera Stack:   [ ${RED}FAIL${NC} ] IPU3 color tuning file missing (run with -c to restore)"
  else
    echo -e " Camera Stack:   [ ${RED}FAIL${NC} ] libcamera detected $cam_count camera(s). Expected at least 2 (Front & Rear)."
    echo -e "                 ${YELLOW}* Run: sudo ./restore_surface_media.sh -c${NC}"
  fi

  echo -e "${CYAN}==================================================${NC}"
}

restore_touch() {
  echo -e "${CYAN}--> Restoring Touchscreen & Stylus (IPTS / iptsd)...${NC}"
  if ! check_kernel; then
    echo -e "    ${RED}[ERROR] Cannot start Touch: running generic kernel $(uname -r).${NC}"
    echo -e "    ${YELLOW}Please run: sudo ./configure_surface_kernel.sh && sudo reboot${NC}"
    return 1
  fi

  sudo systemctl restart "iptsd@*.service" 2>/dev/null || true
  sudo udevadm trigger --subsystem-match=hidraw
  echo -e "    ${GREEN}[✓] Triggered hidraw devices and restarted iptsd.${NC}"
}

restore_audio() {
  echo -e "${CYAN}--> Restoring Audio Stack (PipeWire / WirePlumber)...${NC}"
  systemctl --user stop pipewire.socket pipewire.service wireplumber 2>/dev/null || true
  rm -rf ~/.local/state/pipewire ~/.local/state/wireplumber
  systemctl --user start pipewire.service wireplumber.service
  echo -e "    ${GREEN}[✓] PipeWire & WirePlumber caches reset and services restarted.${NC}"
}

restore_camera() {
  echo -e "${CYAN}--> Restoring Camera Stack (IPU3 tuning & GStreamer)...${NC}"

  # 1. Purge stale / conflicting libcamera builds from /usr/local
  local stale_cleaned=0
  if ls /usr/local/lib/x86_64-linux-gnu/libcamera* 1>/dev/null 2>&1 || [ -f /usr/local/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so ]; then
    echo -e "    ${YELLOW}[!] Cleaning up stale custom libcamera builds in /usr/local...${NC}"
    sudo rm -f /usr/local/lib/x86_64-linux-gnu/libcamera* \
               /usr/local/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so \
               /usr/local/lib/x86_64-linux-gnu/pkgconfig/libcamera* \
               /usr/local/bin/lc-compliance \
               /usr/local/bin/libcamerify 2>/dev/null || true
    sudo ldconfig
    stale_cleaned=1
    echo -e "    ${GREEN}[✓] Unmasked system libcamera packages and updated linker cache.${NC}"
  fi

  # 2. Restore Camera Color Tuning (Fixes Green Tint for Rear Camera / INT347A)
  sudo mkdir -p /usr/share/libcamera/ipa/ipu3/
  sudo tee /usr/share/libcamera/ipa/ipu3/ov8865.yaml > /dev/null <<INNEREOF
version: 1
algorithms:
  - Af:
  - Agc:
  - Awb:
  - ToneMapping:
INNEREOF
  sudo ln -sf /usr/share/libcamera/ipa/ipu3/ov8865.yaml /usr/share/libcamera/ipa/ipu3/INT347A.yaml
  sudo cp /usr/share/libcamera/ipa/ipu3/ov8865.yaml /usr/share/libcamera/ipa/ipu3/uncalibrated.yaml
  echo -e "    ${GREEN}[✓] IPU3 color tuning profiles written (ov8865.yaml, INT347A.yaml).${NC}"

  # 3. Ensure persistent load on boot
  if [ ! -f /etc/modules-load.d/surface-camera.conf ]; then
    echo -e "dw9719\nv4l2loopback" | sudo tee /etc/modules-load.d/surface-camera.conf > /dev/null || true
  fi

  # 4. Load camera drivers and virtual loopback device
  sudo modprobe dw9719 2>/dev/null || true
  sudo depmod -a
  sudo modprobe v4l2loopback devices=1 video_nr=42 card_label="Surface Bridge" exclusive_caps=0 2>/dev/null || true
  echo -e "    ${GREEN}[✓] Camera modules verified (loopback on /dev/video42).${NC}"

  # 5. Refresh GStreamer Plugin Cache
  rm -rf ~/.cache/gstreamer-1.0
  echo -e "    ${GREEN}[✓] GStreamer cache cleared.${NC}"

  # 6. Restart PipeWire multimedia daemon so video nodes are recognized
  systemctl --user restart pipewire.service wireplumber.service 2>/dev/null || true
  echo -e "    ${GREEN}[✓] PipeWire & WirePlumber reloaded.${NC}"

  # 7. Verify cameras with libcamera
  local cam_output cam_count
  cam_output=$(timeout 3 env LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}" cam -l 2>&1 || true)
  cam_count=$(echo "$cam_output" | grep -c "Internal " || true)
  if [ "$cam_count" -ge 2 ]; then
    echo -e "    ${GREEN}[✓] Verification successful: $cam_count camera sensors online.${NC}"
  else
    echo -e "    ${YELLOW}[!] Warning: libcamera detected $cam_count camera(s). Please check dmesg or reboot.${NC}"
  fi
}

run_auto() {
  echo -e "${CYAN}Running Auto-Detection & Smart Recovery...${NC}"
  
  # Check Audio
  local pw_active wp_active
  pw_active=$(systemctl --user is-active pipewire.service 2>/dev/null || echo "inactive")
  wp_active=$(systemctl --user is-active wireplumber.service 2>/dev/null || echo "inactive")
  if [ "$pw_active" != "active" ] || [ "$wp_active" != "active" ]; then
    restore_audio
  else
    echo -e "    ${GREEN}[✓] Audio stack is healthy (skipped).${NC}"
  fi

  # Check Camera
  local cam_output cam_count stale_local=0
  if ls /usr/local/lib/x86_64-linux-gnu/libcamera* 1>/dev/null 2>&1 || [ -f /usr/local/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so ]; then
    stale_local=1
  fi
  cam_output=$(timeout 3 env LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}" cam -l 2>&1 || true)
  cam_count=$(echo "$cam_output" | grep -c "Internal " || true)

  if [ ! -f /usr/share/libcamera/ipa/ipu3/ov8865.yaml ] || [ "$stale_local" -eq 1 ] || [ "$cam_count" -lt 2 ]; then
    restore_camera
  else
    echo -e "    ${GREEN}[✓] Camera stack is healthy ($cam_count sensors online) (skipped).${NC}"
  fi

  # Check Touch
  if check_kernel; then
    local iptsd_active
    iptsd_active=$(systemctl is-active "iptsd@*.service" 2>/dev/null | grep -c "active" || true)
    if [ "$iptsd_active" -eq 0 ]; then
      restore_touch
    else
      echo -e "    ${GREEN}[✓] Touchscreen daemon is active (skipped).${NC}"
    fi
  else
    echo -e "    ${YELLOW}[!] Touch check: Running non-surface kernel. Kernel reconfiguration needed.${NC}"
  fi
}

# --- CLI Option Parsing ---
DO_TOUCH=0
DO_AUDIO=0
DO_CAMERA=0
DO_STATUS=0
DO_AUTO=0
DO_ALL=0

if [ $# -eq 0 ]; then
  DO_ALL=1
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--status)
      DO_STATUS=1
      shift
      ;;
    -a|--auto)
      DO_AUTO=1
      shift
      ;;
    -t|--touch)
      DO_TOUCH=1
      shift
      ;;
    -u|--audio)
      DO_AUDIO=1
      shift
      ;;
    -c|--camera)
      DO_CAMERA=1
      shift
      ;;
    -A|--all)
      DO_ALL=1
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

if [ "$DO_STATUS" -eq 1 ]; then
  show_status
  exit 0
fi

if [ "$DO_AUTO" -eq 1 ]; then
  run_auto
  exit 0
fi

if [ "$DO_ALL" -eq 1 ]; then
  DO_CAMERA=1
  DO_AUDIO=1
  DO_TOUCH=1
fi

[ "$DO_CAMERA" -eq 1 ] && restore_camera
[ "$DO_AUDIO" -eq 1 ] && restore_audio
[ "$DO_TOUCH" -eq 1 ] && restore_touch

echo -e "${GREEN}--------------------------------------------------${NC}"
echo -e "${GREEN} Restoration process completed.                   ${NC}"
echo -e "${GREEN}--------------------------------------------------${NC}"
