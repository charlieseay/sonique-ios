# Quinn Build 135 - Standalone Architecture Spec

**Date:** 2026-07-14  
**Goal:** Simple, embedded voice assistant - Quinn as Jarvis-like companion for Claude Code  
**Branch:** `fix/tailscale-tts-init`  
**Target Build:** 135

---

## Architecture Philosophy

**Sonique = Ears + Mouth + Hands**
- iOS handles voice I/O (speech recognition, TTS)
- SoniqueBar is the brain (Claude Code integration, tools, MCP)
- Simple HTTP communication between them
- Works everywhere (LAN + Tailscale fallback)

**NOT a separate voice agent** - Quinn speaks FOR Claude Code, not alongside it.

---

## Current State (Build 134 on main branch)

❌ **Wrong architecture** - Uses LiveKit WebRTC (too complex)  
❌ **No personality** - Responds as generic assistant  
❌ **Paid TTS** - Uses ElevenLabs  
❌ **Duplicate STT** - Submits transcripts twice  

---

## Target State (Build 135 on fix/tailscale-tts-init)

✅ **Standalone architecture** - iOS ↔ SoniqueBar HTTP only  
✅ **Quinn personality** - Loads from iCloud persona files  
✅ **Free on-device TTS** - AVSpeechSynthesizer  
✅ **Fixed duplicates** - Single STT submission  
✅ **Conversational** - Brief responses, not verbose  

---

## Implementation Tasks

### 1. On-Device TTS (Replace ElevenLabs)

**File:** `Sonique/TTSClient.swift`

**Current:** Calls ElevenLabs API (`fetchFromElevenLabs`)  
**Target:** Use `AVSpeechSynthesizer` for free, offline TTS

**Requirements:**
- Remove ElevenLabs dependency
- Use `AVSpeechSynthesizer.write()` to generate PCM audio
- Output format: 24kHz mono 16-bit PCM (matches VoiceSession player)
- Natural US English voice
- Fallback gracefully if synthesis fails

**Key API:**
```swift
let synthesizer = AVSpeechSynthesizer()
let utterance = AVSpeechUtterance(string: text)
utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

synthesizer.write(utterance, toBufferCallback: { buffer in
    // Convert AVAudioPCMBuffer to Data (PCM 24kHz mono 16-bit)
}, toMarkerCallback: { _ in })
```

---

### 2. Quinn Personality Integration

**Files:** 
- `SoniqueBar/Services/ClaudeCodeBridge.swift` (Mac)
- `Sonique/SoniqueBrain.swift` (iOS - already exists)

**Current:** SoniqueBar passes raw text to Claude  
**Target:** Load Quinn's persona before calling Claude

**Persona files (iCloud):**
```
~/Library/Mobile Documents/iCloud~com~seayniclabs~sonique/Documents/SoniqueProfiles/shared/
├── assistant.json → {"name":"Quinn","photo":null}
├── IDENTITY.md → Who she is, her role
├── RULES.md → Core behavioral rules
└── SOUL.md → Evolving traits
```

**SoniqueBar changes needed:**
```swift
// ClaudeCodeBridge.swift
func execute(text: String) async throws -> String {
    let persona = await SoniqueBrain.shared.loadPersonaContext()
    let systemPrompt = "\(persona)\nUser request: \(text)"
    
    // Call claude CLI with persona-aware prompt
    let result = await executeProcess(
        executable: "/opt/homebrew/bin/claude",
        arguments: ["--print", "--permission-mode", "bypassPermissions", 
                    "--model", "haiku", systemPrompt],
        timeout: 60.0
    )
    // ...
}
```

**Persona context format:**
```
Your name is Quinn.

# Identity
[IDENTITY.md content]

# Rules
[RULES.md content]

## Voice Response Guidelines
- Keep responses concise and conversational (2-3 sentences max unless detail requested)
- Don't provide detailed reports unless asked
- Answer questions directly without preambles
- Use natural, spoken language - you're being heard, not read
```

---

### 3. Fix Duplicate STT Submission

**File:** `Sonique/VoiceSession.swift`

**Current Issue:** Speech recognition continues after first endpoint, detects second endpoint, submits twice

**Logs showing problem:**
```
11:45:21.225 [vs] SUBMIT 'Hey good morning what's your name'
11:45:21.285 [vs] SUBMIT 'Hey good morning what's your name'  ← DUPLICATE
```

**Root cause:** `submit()` doesn't stop the recognition task immediately

**Fix:**
```swift
private func submit(_ text: String) {
    endpointTimer?.cancel(); endpointTimer = nil
    let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
    lastStablePartial = ""
    guard !final.isEmpty else { ... }
    
    FileTracer.log("[vs] SUBMIT '\(final)'")
    
    // CRITICAL: Stop recognition task IMMEDIATELY
    task?.finish()
    task = nil
    request = nil
    
    NotificationCenter.default.post(...)
}
```

---

### 4. SoniqueBar - SoniqueBrain Integration

**File:** `SoniqueBar/Services/SoniqueBrain.swift` (already created)

**Status:** ✅ Already implemented with read/write persona access

**Key methods:**
```swift
SoniqueBrain.shared.loadPersonaContext() // Full persona for Claude
SoniqueBrain.shared.getAssistantName()   // "Quinn"
SoniqueBrain.shared.setAssistantName(_)  // Update name
SoniqueBrain.shared.updateIdentity(_)    // Evolve personality
SoniqueBrain.shared.recordTrait(_)       // Learn from conversations
```

---

## Testing Plan

### Test 1: Name Recognition
**Input:** "Hey Quinn, what's your name?"  
**Expected:** "I'm Quinn" (brief, not "I'm Claude")

### Test 2: Conversational Tone
**Input:** "What time is it?"  
**Expected:** "It's 11:45 AM" (concise, not verbose report)

### Test 3: On-Device TTS
**Verify:** 
- No network calls to ElevenLabs
- Natural Apple voice quality
- Works offline
- Logs show `[tts] synthesized X PCM bytes on-device`

### Test 4: No Duplicates
**Verify:** Only ONE `[vs] SUBMIT` line per utterance in logs

---

## Build Process

1. Increment build number to 135
2. Update `Sonique/Resources/Info.plist` → `<string>$(CURRENT_PROJECT_VERSION)</string>`
3. Update `Sonique.xcodeproj/project.pbxproj` → `CURRENT_PROJECT_VERSION = 135;`
4. Clean build: `xcodebuild clean`
5. Build for iPad
6. Install to device ID: `00008027-0015599C2185002E`
7. Reboot iPad to clear LaunchServices cache

---

## Success Criteria

✅ Quinn responds with her name (not Claude/Sonique)  
✅ Responses are brief and conversational  
✅ TTS works without ElevenLabs API  
✅ No duplicate STT submissions  
✅ Works offline (on-device TTS + local speech recognition)  
✅ SoniqueBar loads persona from iCloud before every response  

---

## Files to Modify

**iOS:**
- [ ] `Sonique/TTSClient.swift` - Replace ElevenLabs with AVSpeechSynthesizer
- [ ] `Sonique/VoiceSession.swift` - Fix duplicate submission
- [ ] `Sonique/Resources/Info.plist` - Build number 135
- [ ] `Sonique.xcodeproj/project.pbxproj` - Build number 135

**macOS (SoniqueBar):**
- [x] `SoniqueBar/Services/SoniqueBrain.swift` - Already created
- [ ] `SoniqueBar/Services/ClaudeCodeBridge.swift` - Wire persona loading

**Testing:**
- [ ] Monitor script for logs
- [ ] Test on iPad (00008027-0015599C2185002E)

---

## Notes

- Current branch has VoiceSession.swift, VoiceLoop.swift, TTSClient.swift intact
- SoniqueBrain references already exist in VoiceLoop
- SoniqueBar has SoniqueBrain.swift with full persona read/write
- Just need to wire on-device TTS and fix duplicate STT
