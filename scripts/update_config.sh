#!/bin/bash

# Searches for a config file on USB storage and applies updates to
# the local config file.

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"

# Source depenencies
source "$SCRIPT_DIR/constants.sh"
source "$WITTY_DIR/utilities.sh"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/find_usb.sh"

TEMPLATE="$SCRIPT_DIR/../config.template"
DEFAULT_CONFIG="$SCRIPT_DIR/../default.env"

# Find USB path
USB_PATH="$(find_usb)" || { broodsense_log info "Config update aborted, no USB storage mounted"; exit 1; }
USB_CONFIG="$USB_PATH/config.env"

# Initially assume all values to be valid
VALID=1

# Read startup reason
startup_reason=$(bcd2dec $(/usr/sbin/i2cget -y 1 0x08 11))

config_to_usb() {
    # Places current env vars into template and saves it to USB storage
    sed -e "s/{study_start}/$study_start/g" \
        -e "s/{study_end}/$study_end/g" \
        -e "s/{scan_resolution}/$scan_resolution/g" \
        -e "s/{scan_interval}/$scan_interval/g" \
        -e "s/{scan_area}/$scan_area/g" "$TEMPLATE" > "$USB_CONFIG"

    # Handle DEBUG flag:
    if [ "${DEBUG:-0}" -eq 1 ]; then
        if grep -q "^# DEBUG=1" "$USB_CONFIG"; then
            sed -i 's/^# DEBUG=1/DEBUG=1/' "$USB_CONFIG"
        else
            echo "DEBUG=1" >> "$USB_CONFIG"
        fi
    fi
}

# If no config file available, copy template with defaults
if [ ! -f "$USB_CONFIG" ]; then
    broodsense_log warning "Config file not found at $USB_CONFIG. Creating default config."
    source "$DEFAULT_CONFIG"
    config_to_usb || exit 1
    broodsense_log info "Default config saved to $USB_CONFIG."
    exit 1
fi

# Overwrite current settings with settings from USB device
source "$USB_CONFIG"

broodsense_log info "Debug flag is set to DEBUG=${DEBUG:-0}."
broodsense_log info "Update flag is set to UPDATE=${UPDATE:-0}."

# Overwrite debug flag if startup was triggered by ALARM1.
if [[ "${DEBUG:-0}" -eq 1 && ( "${startup_reason:-0}" -eq 1 || "${startup_reason:-0}" -eq 8 ) ]]; then
    DEBUG=0
    broodsense_log info "Debug flag (DEBUG=1) was unset, because startup was triggered by ALARM1 and would otherwise interfere with timed shutdown."
fi

# Minimum recommended scan intervals for each resolution in minutes
# If going lower, the scan might not finish before next scheduled startup.
declare -A min_interval
min_interval[300]=4 # (cycle must finish in 3min40s)
min_interval[600]=4 # (cycle must finish in 4min40s)
min_interval[1200]=5 # (cycle must finish in 4min40s)
min_interval[2400]=12 # (cycle must finish in 11min40s)

# Validate scan_resolution
if [[ "$scan_resolution" =~ ^(300|600|1200|2400)$ ]]; then
    broodsense_log debug "Scan resolution ($scan_resolution) is valid."
else
    broodsense_log error "Invalid scan resolution: Found $scan_resolution, expected 300, 600, 1200, or 2400."
    VALID=0
fi

# Validate scan_interval
if [[ "$scan_interval" -ge "${min_interval[$scan_resolution]}" ]]; then
    broodsense_log debug "Scan interval ($scan_interval) is valid."
else
    broodsense_log error "Invalid scan interval: Found $scan_interval, expected at least ${min_interval[$scan_resolution]}."
    VALID=0
fi

# Validate study_start
if date -d "$study_start" &>/dev/null; then
    broodsense_log debug "Study start ($study_start) is valid."
else
    broodsense_log error "Invalid study start: Found $study_start, expected ISO format 'YYYY-MM-DD HH:MM:SS'."
    VALID=0
fi

# Validate study_end
if date -d "$study_end" &>/dev/null; then
    broodsense_log debug "Study end ($study_end) is valid."
else
    broodsense_log error "Invalid study end: Found $study_end, expected ISO format 'YYYY-MM-DD HH:MM:SS'."
    VALID=0
fi

# Validate scan_area key
if [ -n "$scan_area" ]; then
    case "$scan_area" in
      A4|A5-left|A5-right)
        broodsense_log debug "Scan area ($scan_area) is valid"
        ;;
      *)
        broodsense_log error "Invalid scan area: Found $scan_area, but A4, A5-left, or A5-right expected."
        VALID=0
        ;;
    esac
else
    broodsense_log error "Invalid scan area: No 'scan_area' key provided."
    VALID=0
fi

# Validate current_time key
if [ -n "$current_time" ]; then
    if date -d "$current_time" &>/dev/null; then
        broodsense_log debug "Current time ($current_time) is valid."
        # Deactivate network sync
        if ! sudo timedatectl set-ntp false; then
            broodsense_log error "Failed to disable network time synchronization."
            VALID=0
        fi

        # Set system time
        if sudo date --set="$current_time"; then
            broodsense_log info "System date successfully set to $current_time."
            if command -v system_to_rtc &>/dev/null; then
                if system_to_rtc; then
                    broodsense_log info "RTC date successfully set to $current_time."
                else
                    broodsense_log error "Failed to set RTC date to $current_time."
                    VALID=0
                fi
            else
                broodsense_log warning "system_to_rtc function is not available. Skipping RTC update."
            fi
        else
            broodsense_log error "Failed to set system date to $current_time."
            VALID=0
        fi

        # Reactivate network sync
        if ! sudo timedatectl set-ntp true; then
            broodsense_log error "Failed to re-enable network time synchronization."
            VALID=0
        fi
    else
        broodsense_log error "Invalid current time: Found $current_time, but date of ISO format 'YYYY-MM-DD HH:MM:SS' expected."
        VALID=0
    fi
else
    broodsense_log info "Optional current_time key was not provided."
fi

# Validate DEBUG key
case "${DEBUG:-unset}" in
    0|1|"unset"|"")
        ;;
    *)
        broodsense_log warning "DEBUG flag is $DEBUG, but 0 or 1 expected."
        VALID=0
esac

# Validate UPDATE key
case "${UPDATE:-unset}" in
    0|1|"unset"|"")
        ;;
    *)
        broodsense_log warning "UPDATE flag is $UPDATE, but 0 or 1 expected."
        VALID=0
esac

# write current configs to file
config_to_usb


if [ "$VALID" -eq 1 ]; then
    broodsense_log info "All config variables are valid."
    exit 0
else
    broodsense_log error "Some config variables seem to be invalid. See previous logs for details."
    exit 1
fi
