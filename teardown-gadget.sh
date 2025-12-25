#!/usr/bin/env bash
set -euo pipefail

# Teardown the existing gadget so multi-gadget.sh can recreate it cleanly.
# Safe to run multiple times.

CONFIGFS_ROOT="${1:-/sys/kernel/config/usb_gadget/pi4}"

if [ ! -d "$CONFIGFS_ROOT" ]; then
    echo "No gadget present at $CONFIGFS_ROOT; nothing to teardown."
    exit 0
fi

UDC_FILE="$CONFIGFS_ROOT/UDC"
if [ -w "$UDC_FILE" ]; then
    udc=$(cat "$UDC_FILE" 2>/dev/null || true)
    if [ -n "$udc" ]; then
        echo "" > "$UDC_FILE"
    fi
fi

# Drop config links
for link in "$CONFIGFS_ROOT/configs/c.1/uvc.usb0" "$CONFIGFS_ROOT/configs/c.1/acm.usb0"; do
    if [ -L "$link" ]; then
        rm -f "$link"
    fi
done

# Remove symlinks inside the function first to avoid EBUSY on rm -rf
UVC_FUNC="$CONFIGFS_ROOT/functions/uvc.usb0"
if [ -d "$UVC_FUNC" ]; then
    find "$UVC_FUNC" -type l -exec rm -f {} +
    rm -rf "$UVC_FUNC"
fi

ACM_FUNC="$CONFIGFS_ROOT/functions/acm.usb0"
if [ -d "$ACM_FUNC" ]; then
    find "$ACM_FUNC" -type l -exec rm -f {} +
    rm -rf "$ACM_FUNC"
fi

echo "Gadget teardown complete."
