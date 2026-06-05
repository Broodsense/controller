#!/bin/bash

# check_internet_and_sync_time() / ensure_wifi_and_internet()
# --------------
# check_internet_and_sync_time: checks internet connectivity by pinging Cloudflare DNS (1.1.1.1).
#   Syncs system time from the network on success. Returns 0 if reachable, 1 otherwise.
#
# ensure_wifi_and_internet: reconnects WiFi if WIFI_SSID is set and the interface is not
#   associated, then calls check_internet_and_sync_time. Used by both after_startup.sh
#   (initial connect) and upload.sh (reconnect after potential drop in always-on mode).

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

ensure_wifi_and_internet() {
    # Ensures WiFi is connected and internet is reachable. Intended for always-on
    # mode where the connection may have dropped since startup.
    #
    # If WIFI_SSID is set in the environment (sourced from USB config) and WiFi is
    # not currently associated, attempts to reconnect before checking internet.
    # No reconnect is attempted when WIFI_SSID is unset (WiFi-disabled mode).
    #
    # Returns 0 if internet is reachable, 1 otherwise.

    if [[ -n "${WIFI_SSID:-}" ]] && ! /usr/sbin/iwgetid -r >/dev/null 2>&1; then
        broodsense_log info "WiFi not connected - attempting to reconnect to $WIFI_SSID"
        sudo rfkill unblock wifi
        if [[ -n "${WIFI_PWD:-}" ]]; then
            nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PWD" 2>/dev/null
        else
            nmcli device wifi connect "$WIFI_SSID" 2>/dev/null
        fi
        # Wait for association (timeout 15 s)
        for i in {1..15}; do
            if nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep -q "^yes:${WIFI_SSID}"'$'; then
                broodsense_log info "WiFi reconnected to $WIFI_SSID."
                break
            fi
            sleep 1
        done
        if ! nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep -q "^yes:${WIFI_SSID}"'$'; then
            broodsense_log warning "WiFi reconnection to $WIFI_SSID failed or timed out."
            return 1
        fi
    fi

    check_internet_and_sync_time
}
