#!/bin/bash
# Automated monitoring that saves logs to files Claude can read

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$HOME/Desktop/sonique-logs-$TIMESTAMP"
IPAD_LOG="$LOG_DIR/ipad.log"
MAC_LOG="$LOG_DIR/mac.log"
COMBINED_LOG="$LOG_DIR/combined.log"

# Create log directory
mkdir -p "$LOG_DIR"

echo "🚀 Starting automated Sonique monitoring"
echo "📂 Logs directory: $LOG_DIR"
echo ""
echo "Starting Mac backend monitoring in background..."

# Start Mac monitoring in background
log stream \
  --predicate 'subsystem == "com.seayniclabs.soniquebar"' \
  --style compact \
  --color none \
  2>&1 | while read -r line; do
    echo "[MAC] $line" | tee -a "$MAC_LOG" >> "$COMBINED_LOG"
done &
MAC_PID=$!

echo "✅ Mac monitoring started (PID: $MAC_PID)"
echo ""
echo "🎤 Ready to test! Say something on the iPad now."
echo ""
echo "📝 Logs are being written to:"
echo "   iPad: $IPAD_LOG"
echo "   Mac:  $MAC_LOG"
echo "   Combined: $COMBINED_LOG"
echo ""
echo "Press Ctrl+C when done testing"
echo ""

# Trap Ctrl+C to clean up
cleanup() {
    echo ""
    echo "🛑 Stopping monitors..."
    kill $MAC_PID 2>/dev/null || true
    echo "✅ Logs saved to: $LOG_DIR"
    echo ""
    echo "To view:"
    echo "  cat $COMBINED_LOG"
    exit 0
}
trap cleanup INT TERM

# Monitor iPad via Console.app streaming to file
# Since idevicesyslog doesn't work, we'll use log show on archives
echo "Waiting 5 seconds for you to start testing..."
sleep 5

echo "Collecting iPad logs every 2 seconds..."
while true; do
    # Get recent device logs - this captures the last few seconds
    log show \
      --predicate 'subsystem == "com.seayniclabs.sonique"' \
      --last 2s \
      --style compact \
      2>/dev/null | while read -r line; do
        # Only log non-empty lines and avoid duplicates
        if [[ -n "$line" ]] && ! grep -Fq "$line" "$IPAD_LOG" 2>/dev/null; then
            echo "[iPAD] $line" | tee -a "$IPAD_LOG" >> "$COMBINED_LOG"
        fi
    done
    sleep 2
done
