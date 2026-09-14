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
  local yaml_ok=0 loopback_ok=0
  [ -f /usr/share/libcamera/ipa/ipu3/ov8865.yaml ] && yaml_ok=1
  lsmod | grep -q "v4l2loopback" && loopback_ok=1

  if [ "$yaml_ok" -eq 1 ] && [ "$loopback_ok" -eq 1 ]; then
    echo -e " Camera Stack:   [ ${GREEN}OK${NC} ] IPU3 color tuning present & v4l2loopback loaded"
  elif [ "$yaml_ok" -eq 1 ]; then
    echo -e " Camera Stack:   [ ${YELLOW}WARN${NC} ] IPU3 tuning present, v4l2loopback not loaded (will auto-load on bridge)"
  else
    echo -e " Camera Stack:   [ ${RED}FAIL${NC} ] IPU3 color tuning file missing (run with -c to restore)"
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
  
  # Restore Camera Color Tuning (Fixes Green Tint)
  sudo mkdir -p /usr/share/libcamera/ipa/ipu3/
  sudo tee /usr/share/libcamera/ipa/ipu3/ov8865.yaml > /dev/null <<INNEREOF
version: 1
algorithms:
  - BlackLevelCorrection:
  - Agc:
  - Awb:
  - ToneMapping:
INNEREOF
  echo -e "    ${GREEN}[✓] IPU3 color tuning profile written.${NC}"

  # Re-link driver
  sudo depmod -a
  sudo modprobe v4l2loopback 2>/dev/null || true
  echo -e "    ${GREEN}[✓] v4l2loopback reloaded.${NC}"

  # Refresh GStreamer Plugin Cache
  rm -rf ~/.cache/gstreamer-1.0
  echo -e "    ${GREEN}[✓] GStreamer cache cleared.${NC}"
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
  if [ ! -f /usr/share/libcamera/ipa/ipu3/ov8865.yaml ]; then
    restore_camera
  else
    echo -e "    ${GREEN}[✓] Camera color tuning is intact (skipped).${NC}"
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
