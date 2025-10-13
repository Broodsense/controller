
# BroodSense Logging Utils
# ============================
#
# This script provides logging functions for the BroodSense controller system.
# It handles both system logging via rsyslog and USB log file management.
#
# Requirements:
# - rsyslog must be configured to redirect logs tagged with "broodsense"
#   to the desired log file (typically /var/log/broodsense/broodsense.log)
# - USB device must be mounted and accessible for USB log copying
#
# Functions:
# - broodsense_log(level, message): Log messages to system and USB
# - copy_logs(): Copy system logs to USB device



broodsense_log() {
    local SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
    source "$SCRIPT_DIR/find_usb.sh"

    local level="$1"              # Log level (debug, info, warning, error)
    local tag="broodsense"        # Tag for rsyslog identification
    local message="$2"            # Message to log
    local USB_PATH="$(find_usb)"  # Path to USB device

    # use system logger for logging
    /usr/bin/logger -t "${tag}" -p "user.${level}" "${level}: ${message}"

    # Check if USB path is valid
    if [[ -z "$USB_PATH" || ! -d "$USB_PATH" ]]; then
        /usr/bin/logger -t "broodsense" -p "user.debug" "debug: USB path '$USB_PATH' does not exist. Cannot append log string to USB."
        return 1
    fi

    # If valid, append log message to USB log file
    local log_file="$USB_PATH/broodsense.log"
    if ! echo "$(date --rfc-3339=ns | sed 's/ /T/') $tag $tag: $level: $message" >> "$log_file"; then
        /usr/bin/logger -t "broodsense" -p "user.error" "error: Failed to append log to file '$log_file'."
        return 1
    fi
}


copy_logs() {
    local SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
    source "$SCRIPT_DIR/find_usb.sh"

    local USB_PATH="$(find_usb)"

    # Ensure that the USB path exists
    if [[ -z "$USB_PATH" || ! -d "$USB_PATH" ]]; then
        broodsense_log error "USB path $USB_PATH does not exist. Cannot proceed with log copying."
        return 1
    fi

    source "$USB_PATH/config.env"

    # Remove existing logs on USB storage
    find "$USB_PATH" -maxdepth 1 -type f -name "*.log" -exec rm {} \; 2>/dev/null || {
        broodsense_log warning "Failed to remove old log files from $USB_PATH."
    }

    # Copy current logs to USB storage
    broodsense_log debug "Removed old log files, copying current log files to $USB_PATH."

    if [ "${DEBUG:-0}" -eq 0 ]; then
        # Copy everything except for debug messages
        for file in /var/log/broodsense/*.log; do
            if [[ -f "$file" ]]; then
                filename=$(basename "$file")
                grep -vi "debug" "$file" > "$USB_PATH/$filename" || {
                    broodsense_log warning "Failed to copy log file '$file' to USB."
                }
            fi
        done
    else
        # Copy everything (DEBUG mode)
        for file in /var/log/broodsense/*.log; do
            if [[ -f "$file" ]]; then
                cp "$file" "$USB_PATH/" || {
                    broodsense_log warning "Failed to copy log file '$file' to USB."
                }
            fi
        done
    fi
    return 0
}
