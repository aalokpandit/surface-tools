# Surface Pro 4 Tools
A collection of utilities to optimize the Linux experience on the Surface Pro 4.

## Tools & Utilities

### 1. `restore_surface_media.sh`
Modular restoration and diagnostic utility for the Surface Pro 4 hardware stack (Touchscreen/Stylus, Audio, and Cameras).

**Usage**:
```bash
./restore_surface_media.sh [OPTIONS]
```

**Options**:
- `-s, --status`: Show non-destructive health diagnostics for Kernel, Touch, Audio, and Camera.
- `-a, --auto`: Inspect system and conditionally restore only failing components.
- `-t, --touch`: Restore Touchscreen & Stylus (`iptsd` daemon & `hidraw` trigger).
- `-u, --audio`: Reset PipeWire / WirePlumber audio stack.
- `-c, --camera`: Restore IPU3 color profiles (`ov8865.yaml`), reload `v4l2loopback`, and clear GStreamer cache.
- `-A, --all`: Restore all hardware subsystems (default if no options specified).
- `-h, --help`: Display help menu.

---

### 2. `configure_surface_kernel.sh`
Configures the system to default to the `linux-surface` kernel (which provides IPTS touchscreen/pen drivers) and removes generic Ubuntu HWE kernels so future automatic updates don't break hardware support.

**Usage**:
```bash
sudo ./configure_surface_kernel.sh
sudo reboot
```

---

### 3. `bridge_camera.sh`
Toggleable GStreamer bridge for Front/Rear cameras via `v4l2loopback` (`/dev/video14`).

**Usage**:
```bash
./bridge_camera.sh
```
