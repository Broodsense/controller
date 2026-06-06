#!/bin/bash

# BroodSense Shutdown ^Management
# ==============================
#
# This script handles the controlled shutdown of the BroodSense controller.
# It manages the power-off sequence while respecting debug mode settings
# and ensuring logs are properly copied before shutdown.
#
# Behavior:
# - DEBUG=0 (production): Copies logs and shuts down the system
# - DEBUG=1 (debug): Copies logs but keeps system running for debugging

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "$0")")"
source "$SCRIPT_DIR/constants.sh"
source "$WITTY_DIR/utilities.sh"
source "$SCRIPT_DIR/logger.sh"

consider_shutdown() {
    # Conditionally shutdown the system based on DEBUG configuration
    # This function ensures proper cleanup and log copying before shutdown

    # Set emergency shutdown trap for critical errors
    trap 'poweroff' ERR

    # Load configuration settings
    if [ -f "$USB_CONFIG" ]; then
        source "$USB_CONFIG"
    else
        broodsense_log error "Config file not found: $USB_CONFIG"
    fi

    # Wait for scan/upload lock files to clear (or become stale) before shutdown
    local wait_logged=0
    while :; do
        local lock_wait=0
        for lockfile in "$LOCKFILE_SCAN" "$LOCKFILE_UPLOAD"; do
            # Use the corresponding MAX_AGE constant for each lockfile
            local max_age_var=""
            if [ "$lockfile" = "$LOCKFILE_SCAN" ]; then
                max_age_var="LOCKFILE_SCAN_MAX_AGE"
            elif [ "$lockfile" = "$LOCKFILE_UPLOAD" ]; then
                max_age_var="LOCKFILE_UPLOAD_MAX_AGE"
            fi
            local max_age=${!max_age_var:-3600}
            if [ -f "$lockfile" ]; then
                local lock_age=$(( $(date +%s) - $(stat -c %Y "$lockfile") ))
                if [ "$lock_age" -gt "$max_age" ]; then
                    broodsense_log warning "Lock file $lockfile is stale (age ${lock_age}s > ${max_age}s), removing."
                    rm -f "$lockfile"
                else
                    lock_wait=1
                    if [ $wait_logged -eq 0 ]; then
                        broodsense_log info "Waiting for $lockfile to clear before shutdown..."
                        wait_logged=1
                    fi
                fi
            fi
        done
        if [ $lock_wait -eq 0 ]; then
            break
        fi
        sleep 5
    done

    # Determine shutdown behavior based on DEBUG flag and is_mc_connected
    if [ "${DEBUG:-0}" -eq 0 ] && [ "$(is_mc_connected)" -eq 1 ]; then
        # Production mode with microcontroller connected: Copy logs and shutdown
        broodsense_log info "Initiating shutdown sequence."
        copy_logs
        poweroff
    else
        # Debug mode or MC not connected: Copy logs but keep system running
        if [ "${DEBUG:-0}" -eq 1 ]; then
            broodsense_log debug "Debug mode: Skipping shutdown, system remains active for debugging."
        else
            broodsense_log info "No WittyPi, not shutting down (cron-mode)."
        fi
        copy_logs
    fi
}


perform_shutdown() {
    # Set emergency shutdown trap for critical errors
    trap 'poweroff' ERR
    broodsense_log info "Initiating shutdown sequence."
    copy_logs
    poweroff
}
