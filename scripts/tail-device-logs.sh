#!/bin/bash
# Continuously pull and tail trace.log from iPad in real-time

set -e

DEVICE_ID="00008027-0015599C2185002E"  # CS3Pro11 from xctrace list
BUNDLE_ID="com.seayniclabs.sonique"
LOCAL_LOG="$HOME/Desktop/sonique-device-trace.log"
TEMP_DIR=$(mktemp -d)

echo "🔍 Monitoring Sonique trace.log from iPad"
echo "📱 Device: CS3Pro11"
echo "📝 Local copy: $LOCAL_LOG"
echo ""
echo "Press Ctrl+C to stop"
echo "---"

# Clean up on exit
cleanup() {
    rm -rf "$TEMP_DIR"
    exit 0
}
trap cleanup INT TERM

# Initialize empty local log
touch "$LOCAL_LOG"
LAST_SIZE=0

while true; do
    # Copy trace.log from device
    if xcrun devicectl device copy from \
        --device "$DEVICE_ID" \
        --bundle-id "$BUNDLE_ID" \
        --source "Documents/trace.log" \
        --destination "$TEMP_DIR/trace.log" \
        2>/dev/null; then

        # Get new content
        CURRENT_SIZE=$(wc -c < "$TEMP_DIR/trace.log" 2>/dev/null || echo 0)

        if [ "$CURRENT_SIZE" -gt "$LAST_SIZE" ]; then
            # Append new lines to local log and display
            tail -c +$((LAST_SIZE + 1)) "$TEMP_DIR/trace.log" | tee -a "$LOCAL_LOG"
            LAST_SIZE=$CURRENT_SIZE
        fi
    fi

    sleep 0.5  # Poll every 500ms
done
