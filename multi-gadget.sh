#!/bin/bash
# TODO: Document this file. There's... a lot going on in here.

set -e  # Exit on error

CONFIGFS_ROOT="/sys/kernel/config/usb_gadget/pi4"

# Make script idempotent - check if gadget already exists
if [ ! -d "$CONFIGFS_ROOT" ]; then
    mkdir "$CONFIGFS_ROOT"
fi

echo 0x1d6b > "$CONFIGFS_ROOT/idVendor"
echo 0x0104 > "$CONFIGFS_ROOT/idProduct"
echo 0x0100 > "$CONFIGFS_ROOT/bcdDevice"
echo 0x0200 > "$CONFIGFS_ROOT/bcdUSB"

echo 0xEF > "$CONFIGFS_ROOT/bDeviceClass"
echo 0x02 > "$CONFIGFS_ROOT/bDeviceSubClass"
echo 0x01 > "$CONFIGFS_ROOT/bDeviceProtocol"

mkdir -p "$CONFIGFS_ROOT/strings/0x409"
echo 100000000d2386db > "$CONFIGFS_ROOT/strings/0x409/serialnumber"
echo "Samsung" > "$CONFIGFS_ROOT/strings/0x409/manufacturer"
echo "Pi Webcam" > "$CONFIGFS_ROOT/strings/0x409/product"
mkdir -p "$CONFIGFS_ROOT/configs/c.1/strings/0x409"
echo 500 > "$CONFIGFS_ROOT/configs/c.1/MaxPower"
echo "UVC" > "$CONFIGFS_ROOT/configs/c.1/strings/0x409/configuration"

mkdir -p "$CONFIGFS_ROOT/functions/uvc.usb0"
mkdir -p "$CONFIGFS_ROOT/functions/acm.usb0"
mkdir -p "$CONFIGFS_ROOT/functions/uvc.usb0/control/header/h"
if [ -e "$CONFIGFS_ROOT/functions/uvc.usb0/control/class/fs/h" ]; then
    rm -f "$CONFIGFS_ROOT/functions/uvc.usb0/control/class/fs/h"
fi
ln -s "$CONFIGFS_ROOT/functions/uvc.usb0/control/header/h" "$CONFIGFS_ROOT/functions/uvc.usb0/control/class/fs/h" 2>/dev/null || true

# For 720p:
FRAME_DIR="$CONFIGFS_ROOT/functions/uvc.usb0/streaming/mjpeg/m/720p"
mkdir -p "$FRAME_DIR"

# Frame intervals in 100ns units.
# Keep only the supported rates we expose in the gadget.
# We advertise a single rate (15fps) to match what the userspace app
# negotiates and avoid hosts falling back to very low fps (e.g. 2fps).
FRAME_INTERVALS="666666"
echo "$FRAME_INTERVALS" > "$FRAME_DIR/dwFrameInterval"
echo "1280" > "$FRAME_DIR/wWidth"
echo "720" > "$FRAME_DIR/wHeight"
echo "10000000" > "$FRAME_DIR/dwMinBitRate"
echo "100000000" > "$FRAME_DIR/dwMaxBitRate"
echo "7372800" > "$FRAME_DIR/dwMaxVideoFrameBufferSize"

# Verify frame intervals were set correctly
ACTUAL_INTERVALS=$(cat "$FRAME_DIR/dwFrameInterval")
if [ "$ACTUAL_INTERVALS" != "$FRAME_INTERVALS" ]; then
    echo "ERROR: Frame intervals not set correctly for 720p"
    echo "Expected:"
    echo "$FRAME_INTERVALS"
    echo "Actual:"
    echo "$ACTUAL_INTERVALS"
    exit 1
fi
echo "✓ 720p frame intervals verified: 15fps"

# For 1080p:
# mkdir -p /sys/kernel/config/usb_gadget/pi4/functions/uvc.usb0/streaming/mjpeg/m/1080p
# # Frame intervals in 100ns units: 333333 = 30fps, 666666 = 15fps, 10000000 = 1fps
# cat <<EOF > /sys/kernel/config/usb_gadget/pi4/functions/uvc.usb0/streaming/mjpeg/m/1080p/dwFrameInterval
# 333333
# 666666
# 10000000
# EOF
# cat <<EOF > /sys/kernel/config/usb_gadget/pi4/functions/uvc.usb0/streaming/mjpeg/m/1080p/wWidth
# 1920
# EOF
# cat <<EOF > /sys/kernel/config/usb_gadget/pi4/functions/uvc.usb0/streaming/mjpeg/m/1080p/wHeight
# 1080
# EOF
# cat <<EOF > /sys/kernel/config/usb_gadget/pi4/functions/uvc.usb0/streaming/mjpeg/m/1080p/dwMinBitRate
# 10000000
# EOF
# cat <<EOF > /sys/kernel/config/usb_gadget/pi4/functions/uvc.usb0/streaming/mjpeg/m/1080p/dwMaxBitRate
# 100000000
# EOF
# cat <<EOF > /sys/kernel/config/usb_gadget/pi4/functions/uvc.usb0/streaming/mjpeg/m/1080p/dwMaxVideoFrameBufferSize
# 7372800
# EOF

STREAMING_DIR="$CONFIGFS_ROOT/functions/uvc.usb0/streaming"
mkdir -p "$STREAMING_DIR/header/h"
mkdir -p "$STREAMING_DIR/class/fs"
mkdir -p "$STREAMING_DIR/class/hs"
if [ -e "$STREAMING_DIR/header/h/m" ]; then
    rm -f "$STREAMING_DIR/header/h/m"
fi
ln -s "../../mjpeg/m" "$STREAMING_DIR/header/h/m" 2>/dev/null || true
if [ -e "$STREAMING_DIR/class/fs/h" ]; then
    rm -f "$STREAMING_DIR/class/fs/h"
fi
ln -s "../../header/h" "$STREAMING_DIR/class/fs/h" 2>/dev/null || true
if [ -e "$STREAMING_DIR/class/hs/h" ]; then
    rm -f "$STREAMING_DIR/class/hs/h"
fi
ln -s "../../header/h" "$STREAMING_DIR/class/hs/h" 2>/dev/null || true

# Link functions to config
[ ! -e "$CONFIGFS_ROOT/configs/c.1/uvc.usb0" ] && \
    ln -s "$CONFIGFS_ROOT/functions/uvc.usb0" "$CONFIGFS_ROOT/configs/c.1/uvc.usb0"
[ ! -e "$CONFIGFS_ROOT/configs/c.1/acm.usb0" ] && \
    ln -s "$CONFIGFS_ROOT/functions/acm.usb0" "$CONFIGFS_ROOT/configs/c.1/acm.usb0"

udevadm settle -t 5 || :

# Enable the gadget (or rebind if the UDC file is empty)
udc_current=$(cat "$CONFIGFS_ROOT/UDC" 2>/dev/null || true)
if [ -z "$udc_current" ]; then
    udc_target=$(ls /sys/class/udc | head -n1)
    if [ -z "$udc_target" ]; then
        echo "ERROR: No UDC available to bind"
        exit 1
    fi
    for attempt in $(seq 1 30); do
        echo "Binding UDC attempt $attempt: $udc_target"
        if echo "$udc_target" > "$CONFIGFS_ROOT/UDC" 2>/dev/null; then
            echo "✓ USB gadget enabled: $udc_target"
            break
        fi
        sleep 1
    done
    udc_bound=$(cat "$CONFIGFS_ROOT/UDC" 2>/dev/null || true)
    if [ -z "$udc_bound" ]; then
        echo "ERROR: Failed to bind UDC $udc_target"
        exit 1
    fi
else
    echo "✓ USB gadget already enabled: $udc_current"
fi
