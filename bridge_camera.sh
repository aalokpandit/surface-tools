#!/bin/bash

# Suppress GStreamer and Libcamera logs
export GST_DEBUG=0
export LIBCAMERA_LOG_LEVELS=4

# Guarantee system libcamera and GStreamer plugins take precedence
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
export GST_PLUGIN_SYSTEM_PATH="/usr/lib/x86_64-linux-gnu/gstreamer-1.0:${GST_PLUGIN_SYSTEM_PATH}"

GST_PID=""

# Robust function to stop any running camera pipeline and release hardware
stop_stream() {
    if [ -n "$GST_PID" ] && kill -0 "$GST_PID" 2>/dev/null; then
        kill -TERM "$GST_PID" 2>/dev/null || true
        for _ in {1..10}; do
            if ! kill -0 "$GST_PID" 2>/dev/null; then
                break
            fi
            sleep 0.2
        done
        kill -9 "$GST_PID" 2>/dev/null || true
        wait "$GST_PID" 2>/dev/null || true
    fi
    GST_PID=""

    # Clean up any lingering or orphaned camera stream processes
    pkill -9 -f "gst-launch-1.0.*libcamerasrc" 2>/dev/null || true

    # Allow kernel IPU3 / CIO2 DMA receiver buffers time to fully reset
    sleep 1.2
}

# Cleanup on exit or interrupt
cleanup() {
    trap - SIGINT SIGTERM EXIT
    echo ""
    echo "Stopping camera stream and releasing hardware..."
    stop_stream
    echo "Surface Bridge stopped."
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 1. Initialize the virtual device once
echo "Initializing Surface Bridge..."
sudo modprobe dw9719 2>/dev/null || true
if ! lsmod | grep -q "v4l2loopback" || [ ! -e /dev/video42 ]; then
    sudo modprobe -r v4l2loopback 2>/dev/null || true
    sleep 0.5
    sudo modprobe v4l2loopback devices=1 video_nr=42 card_label="Surface Bridge" exclusive_caps=0
    sleep 0.5
fi
v4l2-ctl -d /dev/video42 --set-fmt-video=width=1280,height=720,pixelformat=YUYV 2>/dev/null || true

# Start in Front Camera mode by default
CAM_MODE="FRONT"

while true; do
    clear
    echo "------------------------------------------------"
    echo "  SURFACE BRIDGE ACTIVE: /dev/video42"
    echo "  CURRENT MODE: $CAM_MODE"
    echo "------------------------------------------------"
    echo "  [s] Switch Camera (Front <-> Rear)"
    echo "  [q] Quit and Close Bridge"
    echo "------------------------------------------------"

    if [ "$CAM_MODE" == "FRONT" ]; then
        # Launch Front Camera in background
        gst-launch-1.0 -q libcamerasrc camera-name='\\_SB_.PCI0.I2C2.CAMF' ! \
            video/x-raw,width=1280,height=720 ! queue ! videoconvert ! \
            video/x-raw,format=YUY2 ! identity drop-allocation=1 ! queue ! v4l2sink device=/dev/video42 &
    else
        # Launch Rear Camera in background with Flip
        gst-launch-1.0 -q libcamerasrc camera-name='\\_SB_.PCI0.I2C3.CAMR' ! \
            video/x-raw,width=1280,height=720 ! queue ! videoflip method=horizontal-flip ! \
            videoconvert ! video/x-raw,format=YUY2 ! \
            identity drop-allocation=1 ! queue ! v4l2sink device=/dev/video42 &
    fi

    # Save the Process ID (PID) of GStreamer
    GST_PID=$!

    # Verify stream started successfully
    sleep 0.8
    if ! kill -0 "$GST_PID" 2>/dev/null; then
        echo -e "\n[WARN] Failed to open $CAM_MODE camera."
        echo "Hardware may be busy. Press [s] to retry/switch, or [q] to quit."
    fi

    # Wait for user input
    read -n 1 -s user_input

    if [ "$user_input" == "s" ]; then
        echo "Switching camera, please wait..."
        stop_stream
        if [ "$CAM_MODE" == "FRONT" ]; then CAM_MODE="REAR"; else CAM_MODE="FRONT"; fi
    elif [ "$user_input" == "q" ]; then
        echo "Closing bridge..."
        trap - SIGINT SIGTERM EXIT
        stop_stream
        echo "Bridge closed. Bye!"
        break
    fi
done
