#!/bin/bash
# Monitor both Sonique iOS and SoniqueBar macOS simultaneously in split terminal

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
IPAD_LOG="/tmp/sonique-ipad-$TIMESTAMP.log"
MAC_LOG="/tmp/soniquebar-$TIMESTAMP.log"

echo "🚀 Starting dual monitoring for Sonique"
echo "📱 iPad logs: $IPAD_LOG"
echo "💻 Mac logs: $MAC_LOG"
echo ""

# Check if we're in a terminal multiplexer or need to open new windows
if command -v tmux &> /dev/null && [ -n "$TMUX" ]; then
    # Using tmux
    echo "Using tmux split..."
    tmux split-window -h "$(dirname "$0")/monitor-mac.sh '$MAC_LOG'"
    $(dirname "$0")/monitor-ipad.sh "$IPAD_LOG"
elif command -v screen &> /dev/null && [ -n "$STY" ]; then
    # Using GNU screen
    echo "Using screen split..."
    screen -X split -v
    screen -X focus right
    screen -X screen "$(dirname "$0")/monitor-mac.sh" "$MAC_LOG"
    screen -X focus left
    "$(dirname "$0")/monitor-ipad.sh" "$IPAD_LOG"
else
    # Open in separate Terminal windows (macOS)
    echo "Opening in separate terminal windows..."
    osascript <<EOF
tell application "Terminal"
    do script "cd $(dirname "$0") && ./monitor-ipad.sh '$IPAD_LOG'"
    do script "cd $(dirname "$0") && ./monitor-mac.sh '$MAC_LOG'"
end tell
EOF
    echo "✅ Monitoring started in 2 terminal windows"
    echo "📱 iPad: $IPAD_LOG"
    echo "💻 Mac: $MAC_LOG"
fi
