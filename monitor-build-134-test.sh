#!/bin/bash
# Monitor Build 134 testing - Quinn personality, TTS, conversational tone

DEVICE_ID="00008027-0015599C2185002E"

echo "=== Build 134 Test Monitoring ==="
echo "Watch for:"
echo "  - [ClaudeCodeBridge] persona loading"
echo "  - [tts] on-device synthesis"
echo "  - Response content (Quinn vs Claude)"
echo ""

# Monitor SoniqueBar logs
echo "=== SoniqueBar Logs (last 30 lines) ==="
tail -30 ~/Library/Logs/SoniqueBar/stdout.log 2>/dev/null || echo "No SoniqueBar logs yet"

echo ""
echo "=== Pulling iPad logs ==="

while true; do
    xcrun devicectl device copy from \
        --device "$DEVICE_ID" \
        --domain-type appDataContainer \
        --domain-identifier com.seayniclabs.sonique \
        --user mobile \
        --source Documents/trace.log \
        --destination /tmp/sonique-trace-134.log 2>/dev/null

    if [ -f /tmp/sonique-trace-134.log ]; then
        clear
        echo "=== iPad Trace Log (last 40 lines) ==="
        tail -40 /tmp/sonique-trace-134.log
    fi

    sleep 2
done
