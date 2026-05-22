#!/bin/bash

# has_internet()
# --------------
# Checks for active internet connectivity by pinging a reliable public IP address (Cloudflare DNS: 1.1.1.1).
# Returns 0 (success) if internet is reachable, 1 (failure) otherwise.
# Usage: if has_internet; then ...
has_internet() {
    # Ping Cloudflare DNS with 1 packet, 1 second timeout
    /usr/bin/ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1
    return $?
}
