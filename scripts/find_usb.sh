#!/bin/bash

# BroodSense USB Device Detection
# ===============================
#
# This script provides a function to locate mounted USB devices for the
# BroodSense controller system. It searches for USB devices mounted under
# /media/usb and returns the path to the first available device.
#
# Requirements:
# - USB devices must be auto-mounted under /media/usb/
# - The devmon service should be running for automatic USB mounting
#
# Usage:
#   USB_PATH=$(find_usb)
#   if [ $? -eq 0 ]; then
#       echo "USB device found at: $USB_PATH"
#   else
#       echo "No USB device available"
#   fi

find_usb() {
    # Locate the first mounted USB device under /media/usb/
    # Returns: Path to USB mount point on success, error message on failure
    # Exit codes: 0 = success, 1 = no USB device found

    local mount_point

    # Use findmnt to get all mount points, filter for /media/usb, take first match
    mount_point=$(findmnt -rn -o TARGET | grep "^/media/usb" | head -n 1)

    # Check if a USB device was found
    if [[ -z "$mount_point" ]]; then
        echo "No USB devices found under /media/usb" >&2
        return 1
    fi

    # Return the mount point path
    echo "$mount_point"
    return 0
}
