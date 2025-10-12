#!/bin/bash

# Run this file once to place COMB hooks in witty pi scripts.
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# This script will run after Raspberry Pi boot up and finish running the schedule script.
WITTY_AFTER_STARTUP="/home/controller/wittypi/afterStartup.sh"

# This script will be executed after Witty Pi receives shutdown command (GPIO-4 gets pulled down).
WITTY_BEFORE_SHUTDOWN="/home/controller/wittypi/beforeShutdown.sh"

COMB_AFTER_STARTUP="$SCRIPT_DIR/after_startup.sh"
COMB_BEFORE_SHUTDOWN="$SCRIPT_DIR/shutdown.sh"

# remove existing hooks (delete all lines not starting with #)
sed -i '/^[^#]/d' "$WITTY_AFTER_STARTUP"
sed -i '/^[^#]/d' "$WITTY_BEFORE_SHUTDOWN"

# add hooks
echo "sleep 10 ; /bin/bash $COMB_AFTER_STARTUP" >> "$WITTY_AFTER_STARTUP"
echo "source $COMB_BEFORE_SHUTDOWN; before_shutdown" >> "$WITTY_BEFORE_SHUTDOWN"

