#!/bin/bash
# Complete monitoring setup that Claude can read in real-time

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$HOME/Desktop/sonique-debug-$TIMESTAMP"
IPAD_LOG="$LOG_DIR/ipad-trace.log"
MAC_LOG="$LOG_DIR/mac-backend.log"
COMBINED_LOG="$LOG_DIR/COMBINED.log"

mkdir -p "$LOG_DIR"

echo "═══════════════════════════════════════════════════════════"
echo "🚀 SONIQUE REAL-TIME MONITORING FOR CLAUDE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "📂 All logs saved to: $LOG_DIR"
echo ""
echo "📱 iPad logs: $IPAD_LOG"
echo "💻 Mac logs:  $MAC_LOG"
echo "📋 Combined:  $COMBINED_LOG"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""

# Create marker file so Claude knows monitoring is active
echo "MONITORING_ACTIVE=$(date -Iseconds)" > "$LOG_DIR/STATUS"
echo "PID=$$" >> "$LOG_DIR/STATUS"

# Start Mac backend monitoring
echo "Starting macOS backend monitor..."
(
    log stream \
      --predicate 'subsystem == "com.seayniclabs.soniquebar"' \
      --style compact \
      --color none \
      2>&1 | while IFS= read -r line; do
        timestamp=$(date +"%H:%M:%S.%3N")
        echo "[$timestamp][MAC] $line" | tee -a "$MAC_LOG" >> "$COMBINED_LOG"
    done
) &
MAC_PID=$!
echo "  ✅ Mac monitor PID: $MAC_PID" >> "$LOG_DIR/STATUS"

# Start iPad device log monitor
echo "Starting iPad device trace monitor..."
(
    DEVICE_ID="00008027-0015599C2185002E"
    BUNDLE_ID="com.seayniclabs.sonique"
    TEMP_DIR=$(mktemp -d)
    LAST_SIZE=0

    while true; do
        if xcrun devicectl device copy from \
            --device "$DEVICE_ID" \
            --bundle-id "$BUNDLE_ID" \
            --source "Documents/trace.log" \
            --destination "$TEMP_DIR/trace.log" \
            2>/dev/null; then

            CURRENT_SIZE=$(wc -c < "$TEMP_DIR/trace.log" 2>/dev/null || echo 0)

            if [ "$CURRENT_SIZE" -gt "$LAST_SIZE" ]; then
                tail -c +$((LAST_SIZE + 1)) "$TEMP_DIR/trace.log" | while IFS= read -r line; do
                    echo "[iPAD] $line" | tee -a "$IPAD_LOG" >> "$COMBINED_LOG"
                done
                LAST_SIZE=$CURRENT_SIZE
            fi
        fi
        sleep 0.3
    done
) &
IPAD_PID=$!
echo "  ✅ iPad monitor PID: $IPAD_PID" >> "$LOG_DIR/STATUS"

# Cleanup handler
cleanup() {
    echo ""
    echo "🛑 Stopping monitors..."
    kill $MAC_PID $IPAD_PID 2>/dev/null || true
    echo "MONITORING_STOPPED=$(date -Iseconds)" >> "$LOG_DIR/STATUS"
    echo ""
    echo "✅ Logs saved to: $LOG_DIR"
    echo ""
    echo "📊 Summary:"
    wc -l "$IPAD_LOG" "$MAC_LOG" "$COMBINED_LOG"
    exit 0
}
trap cleanup INT TERM

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ MONITORING ACTIVE - Test on iPad now!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "🎤 Say something on the iPad..."
echo "📺 Watch logs appear below:"
echo ""

# Tail the combined log in real-time
tail -f "$COMBINED_LOG"
