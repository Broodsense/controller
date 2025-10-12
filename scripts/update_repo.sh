#!/bin/bash

# BroodSense Repository Update Manager
# ====================================
#
# This script handles automatic updates of the BroodSense controller software.
# It supports two update sources with automatic fallback:
#   1. Primary: USB-based bare git repository (offline updates)
#   2. Fallback: Online GitHub repository (requires WiFi)
#
# Requirements:
# - UPDATE=1 flag must be set in config.env
# - For USB updates: bare git repository at USB/controller.git
# - For online updates: WiFi network "broodsense"/"broodsense" or internet access
#
# Update Process:
#   1. Check UPDATE flag in configuration
#   2. Attempt USB repository update first
#   3. If USB fails, activate WiFi and try online update
#   4. Log all update attempts and results

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "$0")")"
source "$SCRIPT_DIR/constants.sh"
source "$WITTY_DIR/utilities.sh"

source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/find_usb.sh"

USB_PATH="$(find_usb)"
USB_REPO="$USB_PATH/controller.git"
USB_CONFIG="$USB_PATH/config.env"
source "$USB_CONFIG"

if [ "${UPDATE:-0}" -eq 1 ];then
    broodsense_log info "Update flag enabled - starting repository update process."
else
    broodsense_log debug "Update flag not set (UPDATE=0), skipping code update."
    exit 0
fi

# PRIMARY UPDATE METHOD: USB Repository
# ======================================
# Try to update from USB-based bare git repository first (offline method)
USB_PATH="$(find_usb)"
USB_REPO="$USB_PATH/controller.git"

if [[ -n "$USB_PATH" && -d "$USB_PATH" && -d "$USB_REPO" ]]; then
    broodsense_log debug "USB repository found at $USB_REPO - attempting offline update."

    # Perform git pull from USB bare repository
    pull_output=$(sudo -u comb /usr/bin/git -C "$SCRIPT_DIR" pull "$USB_REPO" 2>&1 | /usr/bin/tr '\n' ' ')
    if [ $? -eq 0 ]; then
        broodsense_log info "Successfully updated from USB repository (commit: $(git -C "$SCRIPT_DIR" rev-parse --short HEAD)): $pull_output"
        exit 0
    else
        broodsense_log warning "USB repository update failed: $pull_output"
    fi
else
    broodsense_log warning "USB repository not available (Path: $USB_PATH, Repo: $USB_REPO). Falling back to online update."
fi

# FALLBACK UPDATE METHOD: Online Repository
# ==========================================
# If USB update fails, try updating from GitHub (requires internet connection)

# Activate WiFi interface
sudo rfkill unblock wifi
broodsense_log debug "Activating WiFi for online repository update."

# Allow time for WiFi connection to establish
/usr/bin/sleep 5

# Test internet connectivity
if /usr/bin/ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    # Internet is available - attempt online update
    broodsense_log debug "Internet connectivity confirmed - pulling from online repository."
    pull_output=$(sudo -u comb /usr/bin/git -C "$SCRIPT_DIR" pull 2>&1 | /usr/bin/tr '\n' ' ')

    if [ $? -eq 0 ]; then
        broodsense_log info "Successfully updated from online repository (commit: $(git -C "$SCRIPT_DIR" rev-parse --short HEAD)): $pull_output"
        exit 0
    else
        broodsense_log error "Online repository update failed: $pull_output"
        exit 1
    fi
else
    broodsense_log error "No internet connectivity available - unable to update from online repository."
    exit 1
fi
