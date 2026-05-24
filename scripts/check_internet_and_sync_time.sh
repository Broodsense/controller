#!/bin/bash

# check_internet_and_sync_time()
# --------------
# Checks for active internet connectivity by pinging a reliable public IP address (Cloudflare DNS: 1.1.1.1).
# Returns 0 (success) if internet is reachable, 1 (failure) otherwise.

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/constants.sh"  # Global constants and paths

# imports net_to_system and system_to_rtc network time sync helpers
source "$WITTY_DIR/utilities.sh"  # WittyPi utility functions
source "$SCRIPT_DIR/logger.sh"

check_internet_and_sync_time() {
    # Ping Cloudflare DNS with 1 packet, 1 second timeout.
    # If reachable, syncs system time from the network and writes it to the WittyPi RTC.
    # Returns 0 if internet is reachable, 1 otherwise.
    if /usr/bin/ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
        broodsense_log info "Internet available - syncing time from network."
        net_to_system
        system_to_rtc
        broodsense_log info "Time sync complete: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        return 0
    else
        return 1
    fi
}
