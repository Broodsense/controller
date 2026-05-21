#!/bin/bash
# Script contains constants used across multiple scripts.

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/find_usb.sh"       # USB device detection

WITTY_DIR="/home/controller/wittypi"
USB_PATH="$(find_usb)"               # Resolve USB mount path
USB_CONFIG="$USB_PATH/config.env"    # Configuration file path
SCAN_DIR="$USB_PATH/scans"           # Output directory for regular scans

FORMAT="jpeg"
TIMEOUT_UPLOAD=1800  # Timeout for upload operations (30min)
BROODSENSE_API_BASE="https://europe-west1-broodsense.cloudfunctions.net/api/v1"
BROODSENSE_API_EXISTING_SCANS="$BROODSENSE_API_BASE/live/getRawTimestamps"
BROODSENSE_API_UPLOAD="${BROODSENSE_API_BASE}/getUploadUrl"

# LOCK files preventing concurrent script executions and early shutdowns
LOCKFILE_UPLOAD="/tmp/broodsense_upload.lock"
LOCKFILE_SCAN="/tmp/broodsense_scan.lock"
LOCKFILE_UPLOAD_MAX_AGE=1800  # seconds (30 minutes)
LOCKFILE_SCAN_MAX_AGE=1800  # seconds (30 minutes)