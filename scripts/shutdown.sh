#!/bin/bash

# BroodSense Shutdown Management
# ==============================
#
# This script handles the controlled shutdown of the BroodSense controller.
# It manages the power-off sequence while respecting debug mode settings
# and ensuring logs are properly copied before shutdown.
#
# Behavior:
# - DEBUG=0 (production): Copies logs and shuts down the system
# - DEBUG=1 (debug): Copies logs but keeps system running for debugging

consider_shutdown() {
    # Conditionally shutdown the system based on DEBUG configuration
    # This function ensures proper cleanup and log copying before shutdown

    # Set emergency shutdown trap for critical errors
    trap 'poweroff' ERR

    # Load required dependencies
    local SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
    source "$SCRIPT_DIR/logger.sh"

    # Locate USB device and configuration
    USB_PATH="$(find_usb)"
    USB_CONFIG="$USB_PATH/config.env"

    # Load configuration settings
    if [ -f "$USB_CONFIG" ]; then
        source "$USB_CONFIG"
    else
        broodsense_log error "Config file not found: $USB_CONFIG"
    fi

    # Determine shutdown behavior based on DEBUG flag
    if [ "${DEBUG:-0}" -eq 0 ]; then
        # Production mode: Copy logs and shutdown
        broodsense_log info "Production mode: Initiating shutdown sequence."
        copy_logs
        poweroff
    else
        # Debug mode: Copy logs but keep system running
        broodsense_log debug "Debug mode: Skipping shutdown, system remains active for debugging."
        copy_logs
    fi
}
