#!/bin/bash

# BroodSense Scanning System
# ==========================
#
# This script manages the automated scanning process for the BroodSense controller.
# It handles scanner detection, configuration, and performs scans based on startup
# conditions and user settings.
#
# Features:
# - Automatic scanner detection
# - Device caching for improved performance
# - Configurable scan areas (A4, A5-left, A5-right)
# - Space monitoring to prevent USB overflow
# - Conditional scanning based on startup reason and debug mode
#
# Scan Conditions:
# - Regular scans: Triggered by WittyPi ALARM1 (scheduled scans)
# - Debug scans: Manual startup with DEBUG=1 flag
# - Output: Timestamped files in USB/scans/ or debug_scan.jpeg
#
# Requirements:
# - Scanner connected via USB
# - USB device with sufficient free space (100MB minimum)
# - scanimage utility installed

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/constants.sh"      # Global constants and paths
source "$WITTY_DIR/utilities.sh"       # WittyPi utility functions
source "$SCRIPT_DIR/logger.sh"         # Logging functions
source "$SCRIPT_DIR/find_usb.sh"       # USB device detection
SCANIMAGE_CONFIG="$SCRIPT_DIR/../scanimage.env"  # Scanner device cache file


get_device() {
    # Detect and cache scanner device information
    # Usage: get_device <from_buffer>
    # Parameters:
    #   from_buffer: 1 = use cached device, 0 = force device detection
    # Returns: Scanner device identifier string

    FROM_BUFFER="$1"                    # Whether to use cached device info
    source "$SCANIMAGE_CONFIG"          # Load cached device information

    # Try to use cached scanner device first (faster)
    if [[ "$FROM_BUFFER" -eq 1 && -n "$scan_device" ]]; then
        echo "$scan_device"
        return 0
    fi

    # Perform fresh scanner detection with retry logic
        retries=5
        while (( retries >= 0 )); do
            if ! scan_device=$(/usr/bin/scanimage -L 2>/dev/null) || [[ -z "$scan_device" ]] || grep -q "No scanners were identified" <<< "$scan_device"; then
                if (( retries == 0 )); then
                    broodsense_log error "Failed to list scan devices after multiple attempts. Is a scanner connected?"
                    exit 1
                else
                    broodsense_log warning "Failed to list scan devices. Retrying in 10 seconds... ($retries retries left)"
                    /usr/bin/sleep 10
                    (( retries-- ))
                fi
            else
                # Parse scanner device from scanimage output
                # Prefer airscan interfaces
                airscan_device=$(echo "$scan_device" | grep airscan)
                if [[ -n "$airscan_device" ]]; then
                   # Extract airscan device identifier
                   scan_device=$(echo "$airscan_device" | grep -oP "\`\K.*(?=')")
                else
                   # Use first available scanner device
                   scan_device=$(echo "$scan_device" | head -n 1 | grep -oP "\`\K.*(?=')")
                fi

                # Update device cache file
                sed -i '/^scan_device=/d' "$SCANIMAGE_CONFIG"    # Remove old entries
                echo "scan_device=\"$scan_device\"" >> "$SCANIMAGE_CONFIG"  # Add new entry

                broodsense_log debug "Scanner device detected and cached: $scan_device"
                echo "$scan_device"
                return 0
            fi
        done
}

scan() {
    # Perform a scan with the configured settings
    # This function handles space checking, path determination, and scan execution
    # Scan behavior depends on startup reason and debug mode settings

    # Scan configuration constants
    USB_MIN_FREE_SPACE=100              # Minimum free space required (MB)
    FORMAT=jpeg                         # Output image format
    MODE=Color                          # Scan mode (Color/Gray)

    # Setup paths and validate USB device
    USB_PATH="$(find_usb)" || { broodsense_log info "Scan aborted, no USB storage mounted"; exit 1; }
    USB_CONFIG="$USB_PATH/config.env"   # Configuration file path
    OUT_DIR="$USB_PATH/scans"           # Output directory for regular scans

    if [[ ! ( -d "$USB_PATH" && -f "$USB_CONFIG" ) ]]; then
        broodsense_log warning "Scan skipped: No USB device available ($USB_PATH) or config file not found ($USB_CONFIG)."
        exit 1
    fi

    # Load user configuration from USB device
    source "$USB_CONFIG"

    # Determine scan output path based on startup reason
    # startup_reason=1: WittyPi ALARM1 (scheduled scan)
    # startup_reason≠1: Manual startup or other trigger
    startup_reason=$(bcd2dec $(/usr/sbin/i2cget -y 1 0x08 11))

    if [ "${startup_reason:-0}" -eq 1 ]; then
        # Scheduled scan: Save to timestamped file in scans directory
        OUT_PATH="$OUT_DIR/$(date +'%Y-%m-%d_%H-%M-%S').$FORMAT"
        broodsense_log debug "Scheduled scan detected - output: $OUT_PATH"
    else
        # Manual startup: Only scan if DEBUG mode is enabled
        if [ "${DEBUG:-0}" -eq 1 ]; then
            OUT_PATH="$USB_PATH/debug_scan.jpeg"
            broodsense_log debug "Debug scan mode - output: $OUT_PATH"
        else
            broodsense_log info "Manual startup without DEBUG flag - skipping scan."
            exit 0
        fi
    fi

    # Ensure output directory exists
    mkdir -p "$OUT_DIR" || { broodsense_log error "Failed to create output directory $OUT_DIR."; exit 1; }

    # Check available storage space before scanning
    available_space=$(/usr/bin/df --output=avail -m "$USB_PATH" | tail -n 1)
    if [[ "$available_space" -lt "$USB_MIN_FREE_SPACE" ]]; then
        broodsense_log warning "Insufficient storage space (${available_space}MB available, ${USB_MIN_FREE_SPACE}MB required). Scan aborted."
        exit 1
    fi

    # Define scan area dimensions (in mm)
    # A4: 210 x 297mm, A5: 148 x 210mm
    local long=297.011      # A4 length
    local short=148.5055    # A5 width
    local t=0               # Top margin (default)
    local y=$long           # Height (default to A4)
    # Configure scan area based on user setting
    case "$scan_area" in
         "A4")
            # Full A4 page (210 x 297mm)
            broodsense_log debug "Scan area: A4 (210x297mm)"
            ;;
         "A5-right")
            # Right half of A4 (148 x 297mm)
            y=$short
            broodsense_log debug "Scan area: A5-right (148x297mm)"
            ;;
         "A5-left")
            # Left half of A4 (148 x 297mm, offset by 148mm)
            y=$short
            t=$short
            broodsense_log debug "Scan area: A5-left (148x297mm, offset 148mm)"
            ;;
        *)
            broodsense_log error "Invalid scan area: '$scan_area'. Valid options: A4, A5-left, A5-right"
            exit 1
            ;;
    esac

    # Execute the scan with configured parameters
    broodsense_log debug "Starting scan: ${scan_resolution}dpi, ${FORMAT} format, ${MODE} mode"
    /usr/bin/scanimage --format "$FORMAT" --mode "$MODE" --resolution "$scan_resolution" -o "$OUT_PATH" --device "$scan_device" -t "$t" -y "$y" > /dev/null 2>&1
    return $?
}

# MAIN EXECUTION FLOW
# ===================
# Try cached scanner device first, then fall back to fresh detection if needed

# Attempt scan with cached device information (faster startup)
scan_device="$(get_device 1)"
broodsense_log debug "Attempting scan with cached device: $scan_device"

if ! scan; then
    # First attempt failed - refresh scanner detection
    broodsense_log warning "Scan failed with cached device '$scan_device' - refreshing device list"

    # Force fresh scanner detection (slower but more reliable)
    scan_device="$(get_device 0)"
    broodsense_log debug "Retrying scan with refreshed device: $scan_device"

    if ! scan; then
        broodsense_log error "Scan failed on device '$scan_device'. Check scanner connection and power."
        exit 1
    else
        broodsense_log info "Scan completed successfully: $OUT_PATH"
        # Allow scanner head to return to home position
        # /usr/bin/sleep 10
    fi
else
    broodsense_log info "Scan completed successfully: $OUT_PATH"
    # Allow scanner head to return to home position
    # /usr/bin/sleep 10
fi
