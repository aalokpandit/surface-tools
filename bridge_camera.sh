#!/bin/bash

# Suppress GStreamer and Libcamera logs
export GST_DEBUG=0
export LIBCAMERA_LOG_LEVELS=4

# 1. Initialize the virtual device once
echo "Initializing Surface Bridge..."
sudo modprobe dw9719 2>/dev/null || true
sudo modprobe -r v4l2loopback 2>/dev/null
sleep 1
sudo modprobe v4l2loopback devices=1 video_nr=14 card_label="Surface Bridge" exclusive_caps=0
sleep 1
v4l2-ctl -d /dev/video14 --set-fmt-video=width=1280,height=720,pixelformat=YUYV


# Start in Front Camera mode by default
CAM_MODE="FRONT"

while true; do
    clear
    echo "------------------------------------------------"
    echo "  SURFACE BRIDGE ACTIVE: /dev/video14"
    echo "  CURRENT MODE: $CAM_MODE"
    echo "------------------------------------------------"
    echo "  [s] Switch Camera (Front <-> Rear)"
    echo "  [q] Quit and Close Bridge"
    echo "------------------------------------------------"

    if [ "$CAM_MODE" == "FRONT" ]; then
        # Launch Front Camera in background
        gst-launch-1.0 -q libcamerasrc camera-name='\\_SB_.PCI0.I2C2.CAMF' ! \
            video/x-raw,width=1280,height=720 ! videoconvert ! \
            video/x-raw,format=YUY2 ! identity drop-allocation=1 ! v4l2sink device=/dev/video14 &
    else
        # Launch Rear Camera in background with Flip
        gst-launch-1.0 -q libcamerasrc camera-name='\\_SB_.PCI0.I2C3.CAMR' ! \
            video/x-raw,width=1280,height=720 ! videoflip method=horizontal-flip ! \
            videoconvert ! video/x-raw,format=YUY2 ! \
            identity drop-allocation=1 ! v4l2sink device=/dev/video14 &
    fi

    # Save the Process ID (PID) of GStreamer
    GST_PID=$!

    # Wait for user input
    read -n 1 -s user_input
    
    if [ "$user_input" == "s" ]; then
        kill $GST_PID 2>/dev/null
        if [ "$CAM_MODE" == "FRONT" ]; then CAM_MODE="REAR"; else CAM_MODE="FRONT"; fi
        echo "Switching..."
        sleep 1
    elif [ "$user_input" == "q" ]; then
        kill $GST_PID 2>/dev/null
        sudo modprobe -r v4l2loopback
        echo "Bridge closed. Bye!"
        break
    fi
done
