#!/bin/bash

# ensure_wifi_and_internet()
# --------------
# Primary entry point for all internet needs.
# If internet is not reachable and WIFI_SSID is set, reconnects WiFi first.
# Once online, restarts systemd-timesyncd and blocks until the clock is synced.
# If a WittyPi microcontroller is attached, also writes the synced time to its RTC.

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/constants.sh"  # Global constants and paths

# imports net_to_system and system_to_rtc network time sync helpers
source "$WITTY_DIR/utilities.sh"  # WittyPi utility functions
source "$SCRIPT_DIR/logger.sh"


ensure_wifi_and_internet() {
    # If internet is not reachable and WIFI_SSID is configured, attempt reconnect first.
    if ! /usr/bin/ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
        if [[ -n "${WIFI_SSID:-}" ]]; then
            broodsense_log info "No internet - attempting to reconnect to WiFi SSID: $WIFI_SSID"
            sudo rfkill unblock wifi
            if [[ -n "${WIFI_PWD:-}" ]]; then
                nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PWD" 2>/dev/null
            else
                nmcli device wifi connect "$WIFI_SSID" 2>/dev/null
            fi
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
    fi

    # Always sync time when internet is reachable — correct clock is required for SSL.
    if /usr/bin/ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
        broodsense_log info "Internet available - syncing time from network."
        # Trigger NTP sync and wait until systemd confirms the clock is good.
        sudo systemctl restart systemd-timesyncd
        sudo /lib/systemd/systemd-time-wait-sync --one-shot
        if [[ "$(is_mc_connected)" -ne 0 ]]; then
            # WittyPi present — write synced time to its hardware RTC
            system_to_rtc
        fi
        broodsense_log info "Time sync complete: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        return 0
    else
        broodsense_log warning "No internet connectivity."
        return 1
    fi
}
