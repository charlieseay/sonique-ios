#!/bin/bash
# Monitor Sonique iOS app logs in real-time from connected iPad

set -e

DEVICE_UDID="3A512515-79AA-5598-A795-A1EA3257C908"

# Check if libimobiledevice can see the device
if ! idevice_id -l | grep -q "$DEVICE_UDID" 2>/dev/null; then
    echo "⚠️  iPad not accessible via idevicesyslog (iOS 17+ network pairing)"
    echo ""
    echo "📱 Using Console.app instead..."
    exec "$(dirname "$0")/monitor-ipad-console.sh"
fi

LOG_FILE="${1:-/tmp/sonique-ipad-$(date +%Y%m%d-%H%M%S).log}"

echo "🔍 Monitoring Sonique on iPad (CS3Pro11)"
echo "📝 Logging to: $LOG_FILE"
echo "🎯 Filtering: VoiceLoop, TTS, VoiceSession, NativeIntents"
echo ""
echo "Press Ctrl+C to stop"
echo "---"

# Stream logs with filtering
idevicesyslog -u "$DEVICE_UDID" \
  -p Sonique \
  -m "VoiceLoop\|TTS\|VoiceSession\|speakSentence\|NativeIntents\|ERROR\|WARN" \
  --colors \
  -o "$LOG_FILE"
