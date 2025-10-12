#!/bin/bash

# Script is executed on startup. Settings are loaded, code base is pulled and witty scheduled.

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "$0")")"
source "$SCRIPT_DIR/constants.sh"
source "$WITTY_DIR/utilities.sh"

source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/find_usb.sh"
source "$SCRIPT_DIR/shutdown.sh"

# Log startup reason
startup_reason=$(bcd2dec $(/usr/sbin/i2cget -y 1 0x08 11))
case "$startup_reason" in
    0) reason_str="N/A" ;;
    1) reason_str="ALARM1 (start alarm)" ;;
    2) reason_str="ALARM2 (stop alarm)" ;;
    3) reason_str="Manual start (button click)" ;;
    4) reason_str="Input voltage too low" ;;
    5) reason_str="Input voltage restored" ;;
    6) reason_str="Over temperature" ;;
    7) reason_str="Below temperature" ;;
    8) reason_str="ALARM1 (start alarm) delayed" ;;
    *) reason_str="Unknown reason ($startup_reason)" ;;
esac

broodsense_log info ""
broodsense_log info "Startup was caused by: $reason_str."

USB_PATH="$(find_usb)"
USB_CONFIG="$USB_PATH/config.env"

# Ensure that the USB path exists, otherwise shutdown
if [ ! -d "$USB_PATH" ]; then
    consider_shutdown
    exit 1
fi

# Import potentially updated settings from USB storage
/bin/bash "$SCRIPT_DIR/update_config.sh"
if [ $? -eq 1 ]; then
    consider_shutdown
    exit 1
fi

# Load validated config
if [ ! -f "$USB_CONFIG" ]; then
    broodsense_log warning "Config file is missing ($USB_CONFIG), exiting."
    exit 1
fi
source "$USB_CONFIG"

# Generate witty schedule reflecting the current settings
/bin/bash "$SCRIPT_DIR/wittypi_schedule.sh"


if [ "${DEBUG:-0}" -eq 1 ]; then
    # enable WiFi
    # enable / disable (autostart), start/stop (immediate)
    sudo rfkill unblock wifi
    broodsense_log info "WiFi started due to debug mode."
else
    sudo rfkill block wifi
    broodsense_log info "WiFi disabled (default)."
fi

# sync repository
/bin/bash "$SCRIPT_DIR/update_repo.sh"

# perform scan if autostart or debug mode
if [[ "${startup_reason:-0}" -eq 1 || "${DEBUG:-0}" -eq 1 ]]; then
	/bin/bash "$SCRIPT_DIR/scan.sh"
fi

consider_shutdown

