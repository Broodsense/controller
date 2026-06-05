#!/bin/bash

# Script is executed on startup. Settings are loaded, code base is pulled and witty scheduled.

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "$0")")"
source "$SCRIPT_DIR/constants.sh"
source "$WITTY_DIR/utilities.sh"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/shutdown.sh"
source "$SCRIPT_DIR/check_internet_and_sync_time.sh"

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

# Ensure that the USB path exists, otherwise shutdown
if [ ! -d "$USB_PATH" ]; then
    consider_shutdown
    exit 1
fi

# Import potentially updated settings from USB storage
/bin/bash "$SCRIPT_DIR/update_config.sh"
if [ $? -ne 0 ]; then
    consider_shutdown
    exit 1
fi

# Load validated config
if [ ! -f "$USB_CONFIG" ]; then
    broodsense_log warning "Config file is missing ($USB_CONFIG), exiting."
    exit 1
fi
source "$USB_CONFIG"

# If given, ensure WiFi is connected and time is synced
if [[ -n "${WIFI_SSID:-}" ]]; then
    if ! ensure_wifi_and_internet; then
        broodsense_log warning "WiFi or internet connection failed for SSID: $WIFI_SSID"
    fi
else
    # disable wifi, save power
    sudo rfkill block wifi
    broodsense_log info "WiFi disabled (no SSID configured)."
fi

# Generate witty schedule reflecting the current settings
# NOTE: Must run AFTER WiFi/time sync so the WittyPi RTC alarm is programmed
# with the correct (NTP-synced) time.
/bin/bash "$SCRIPT_DIR/wittypi_schedule.sh"

# sync repository (if UPDATE flag is set in config)
/bin/bash "$SCRIPT_DIR/update_repo.sh"

# Handle cronjob based on is_mc_connected setting (WittyPi present):
if [[ "$(is_mc_connected)" -eq 0 ]]; then
    # Set up cronjob for periodic scanning
    CRON_ENTRY="*/${scan_interval} * * * * $SCRIPT_DIR/scan.sh"

    # Check if cronjob already exists
    if ! crontab -l 2>/dev/null | grep -F "scan.sh" > /dev/null; then
        # Add the cronjob
        (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
        broodsense_log info "Added periodic scan cronjob: $CRON_ENTRY"
    else
        broodsense_log debug "Scan cronjob already exists"
    fi
else
    # Remove cronjob line that contains scan.sh (if exists)
    if crontab -l 2>/dev/null | grep -F "scan.sh" > /dev/null; then
        crontab -l 2>/dev/null | grep -v "scan.sh" | crontab -
        broodsense_log info "Removed scan cronjob (WittyPi connected)"
    fi
fi

# perform scan if autostart or debug mode
if [[ "${startup_reason:-0}" -eq 1 || "${DEBUG:-0}" -eq 1 ]]; then
	/bin/bash "$SCRIPT_DIR/scan.sh"
fi

# Work done, shutdown (unless debug mode is enabled)
consider_shutdown
