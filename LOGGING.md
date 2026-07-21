# Sonique Real-Time Logging Guide

## Quick Start

### Option 1: Automated Dual Monitoring (RECOMMENDED)
```bash
cd ~/Projects/sonique-ios/scripts
./monitor-both.sh
```
Opens 2 terminal windows automatically - one for iPad, one for Mac.

### Option 2: Manual Terminal Setup

**Terminal 1 - iPad:**
```bash
cd ~/Projects/sonique-ios/scripts
./monitor-ipad.sh
```

**Terminal 2 - Mac:**
```bash
cd ~/Projects/sonique-mac/scripts
./monitor-mac.sh
```

### Option 3: Console.app (GUI)
1. Open Console.app
2. Select "CS3Pro11" device in sidebar
3. Click "Start" button
4. Add predicate:
   ```
   subsystem == "com.seayniclabs.sonique"
   ```

---

## What You'll See

### iPad Logs (VoiceLoop, TTS, Audio)
```
[VoiceLoop] Starting...
[VoiceLoop] observeTranscripts - received: "What time is it?"
[NativeIntents] matched: currentTime
[TTS] speakSentence: "It's 10:15 AM."
[VoiceBox] fetching TTS for: 'It's 10:15 AM.'
[VoiceSession] playPCM data: 45632 bytes
```

### Mac Logs (Backend, Claude, TTS Synthesis)
```
[CommandServer] POST /command/stream
[ClaudeCodeBridge] Executing: "Tell me a joke"
[ClaudeCodeBridge] Success: "Why don't scientists trust atoms?..."
[CommandServer] TTS request: "Why don't scientists trust atoms?"
[CommandServer] TTS generated 87234 bytes
```

---

## Debugging Workflow

1. **Start monitoring** in 2 terminals (or Console.app)
2. **Trigger action** on iPad (say "Hello" or "What time is it?")
3. **Watch both streams** to see the full flow
4. **Identify where it stops** - iPad processing? Network? Backend? TTS?

### Common Issues to Look For

**Issue:** "What time is it?" returns nothing
- **Check iPad logs for:** `[NativeIntents] matched: currentTime`
- **Then:** `[TTS] speakSentence:` followed by actual time
- **If missing:** TTS provider not initialized

**Issue:** Response text received but no audio
- **Check iPad logs for:** `[VoiceBox] fetching TTS`
- **Then:** `[VoiceSession] playPCM data: N bytes`
- **If missing:** Network issue or TTS synthesis failure

**Issue:** Long delay before response
- **Check Mac logs for:** `[ClaudeCodeBridge] Executing:`
- **Time to:** `[ClaudeCodeBridge] Success:`
- **If > 5s:** Claude CLI slow or hung

---

## Advanced Commands

### Save Full Session Archive
```bash
# iPad archive (can view in Console.app)
idevicesyslog -u 3A512515-79AA-5598-A795-A1EA3257C908 \
  archive ~/Desktop/sonique-debug-$(date +%Y%m%d-%H%M%S).logarchive
```

### Filter for Errors Only
```bash
# iPad errors
idevicesyslog -u 3A512515-79AA-5598-A795-A1EA3257C908 \
  -p Sonique \
  -m "ERROR\|WARN\|FAIL"

# Mac errors
log stream --predicate 'subsystem == "com.seayniclabs.soniquebar" AND messageType >= 16' \
  --style compact
```

### Monitor Specific Function
```bash
# Watch only TTS synthesis
idevicesyslog -u 3A512515-79AA-5598-A795-A1EA3257C908 \
  -p Sonique \
  -m "speakSentence\|fetchPCM\|playPCM"
```

---

## Device Info

- **iPad UDID:** `3A512515-79AA-5598-A795-A1EA3257C908`
- **iPad Name:** CS3Pro11 (iPad Pro 11-inch)
- **iOS Subsystem:** `com.seayniclabs.sonique`
- **macOS Subsystem:** `com.seayniclabs.soniquebar`

---

## Troubleshooting the Monitoring Tools

### idevicesyslog not working?
```bash
# Check device connection
idevice_id -l

# Test connectivity
idevicesyslog -u 3A512515-79AA-5598-A795-A1EA3257C908 pidlist
```

### No logs appearing?
1. Make sure Sonique app is running on iPad
2. Trigger an action (say something)
3. Check if FileTracer logs exist:
   ```bash
   devicectl device info files --device 3A512515-79AA-5598-A795-A1EA3257C908 \
     list --domain appDataContainer \
     --bundle-id com.seayniclabs.sonique
   ```

---

## Best Practices

1. **Start monitoring BEFORE testing** - captures initialization
2. **Keep logs running** - don't restart between tests
3. **Mark test actions in terminal** - type "// Testing time query" before triggering
4. **Save important sessions** - use archive command for later analysis
5. **Check both streams** - issue might be iOS→Mac handoff

---

## Related Files

- iPad monitoring script: `~/Projects/sonique-ios/scripts/monitor-ipad.sh`
- Mac monitoring script: `~/Projects/sonique-mac/scripts/monitor-mac.sh`
- Dual monitor script: `~/Projects/sonique-ios/scripts/monitor-both.sh`
- Research doc: `/tmp/sonique-log-research.md`
