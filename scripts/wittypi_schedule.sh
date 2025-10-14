#!/bin/bash

# BroodSense WittyPi Schedule Script
# ---------------------------------
# This script is executed on startup to:
#   - Load device settings from USB
#   - Generate and apply a WittyPi schedule for automatic power cycles
#   - Disable auto-shutdown in debug mode
#
# Sourced scripts:
#   constants.sh   : Loads global constants and paths
#   logger.sh      : Provides broodsense_log for logging
#   find_usb.sh    : Finds the USB device with config
#   utilities.sh   : WittyPi utility functions

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"

source "$SCRIPT_DIR/constants.sh"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/find_usb.sh"
source "$WITTY_DIR/utilities.sh"

USB_PATH="$(find_usb)"
USB_CONFIG="$USB_PATH/config.env"

# Check for config file
if [ ! -f "$USB_CONFIG" ]; then
    broodsense_log warning "Skipping wittypi schedule, config file is missing ($USB_CONFIG)"
    exit 1
fi

# Load settings from config.env
source "$USB_CONFIG"

# Remove any existing WittyPi schedules
/usr/bin/rm -f "$WITTY_DIR"/schedule.wpi* 2>/dev/null

# Create a new WittyPi schedule file
SCHEDULE="$WITTY_DIR/schedule.wpi"

# Scheduling Strategy:
# The system powers on every <scan_interval> minutes to perform a scan cycle.
# Normal operation: The script completes within the scan interval and powers
# off the system automatically.
# Failsafe mechanism: If the script runs longer than expected, the system will
# force shutdown 20 seconds before the next scheduled power on to maintain the
# scheduled rhythm.

/usr/bin/cat > "$SCHEDULE" <<EOF
BEGIN ${study_start//T/ }
END ${study_end//T/ }
ON M$((scan_interval - 1)) S40
OFF S20
EOF

/usr/bin/sleep 0.5 # Ensure no conflict with WittyPi's previous scheduler

# Apply the new schedule using WittyPi's runScript.sh
/bin/bash "$WITTY_DIR/runScript.sh" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    NEXTSTARTUP=$(get_startup_time)
    broodsense_log info "WittyPi scheduler executed. Next startup: $NEXTSTARTUP"
else
    broodsense_log error "WittyPi scheduler failed to execute."
fi

# If DEBUG mode is enabled, disable auto-shutdown
if [ "${DEBUG:-0}" -eq 1 ]; then
    clear_shutdown_time
    broodsense_log info "Auto shutdown disabled due to debug mode."
fi
