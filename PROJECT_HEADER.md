# Sonique (iOS)

## Project Identity

**Repository:** `~/Projects/sonique-ios`  
**Status:** Active (fixing Error 301, App Store submission phase)  
**Language:** Swift (SwiftUI)  
**Target:** iOS 17.0+  
**Role:** iOS client for Sonique voice assistant (CAAL backend)

---

## Quick Description

SwiftUI app for iPhone/iPad that provides voice input/output interface to Sonique backend. Supports ElevenLabs TTS, speech recognition, Tailscale connectivity for remote access, and configurable server endpoints. Currently in App Store review cycle; Error 301 (speech recognition initialization) recently fixed.

---

## Current State

Sonique iOS is a production SwiftUI app targeting iOS 17.0+, in App Store review cycle. Latest commit (65fd71d) updates SpeechRecognitionService. Clean repository (no uncommitted changes). Features voice input/output interface to Sonique backend, ElevenLabs TTS, speech recognition with Error 301 fix (reordered recognition task initialization before audio tap), Tailscale VPN toggle for network switching, and UserDefaults server config. Single-token auth (Phase 1); Authentik OIDC planned for Phase 2.

---

## Assessment — 2026-09-01

### Errors & Risks
[RESOLVED] ✓ Streaming LLM response handling now implemented (VoiceLoop.swift:390-413; HTTPClient.sendCommandStreaming streams chunks)
[RESOLVED] ✓ Barge-in detection + interruption predictor added (lines 163-201; interruptionPredictor.shouldInterrupt with transcript + prosodics)
[MED] Sentence-level TTS pipelining working (lines 545-560 extractCompleteSentences; speaks on sentence boundary, not full response)
[MED] Audio session mode: still uses default configuration; not yet switched to `.voiceChat` for full duplex echo cancellation
[LOW] ElevenLabs cloud STT still in use (Phase 2 planned for on-device WhisperKit); roundtrip ~500ms–1s but acceptable with streaming

### Security
✓ No secrets in code (API key fetched from SoniqueBar, not bundled)
✓ Microphone + speech recognition entitlements correct
✓ Tailscale toggle properly isolated to UserDefaults
✓ Error feedback sent to SoniqueBar with auth token (lines 682-710; includes type, message, metadata)

### Improvements
1. ✓ (DONE) Implement streaming LLM response handling (sentence-level chunks)
2. ✓ (DONE) Add barge-in detection with interruption predictor
3. Switch audio session to `.voiceChat` mode before TTS → full duplex echo cancellation
4. Replace ElevenLabs cloud STT with WhisperKit (on-device) + Silero VAD for <400ms TTFA
5. Add Kokoro TTS as fallback for common phrases (<200ms synthesis)

### Cost
Streaming now free (no additional API calls). Kokoro fallback optional (same interface as ElevenLabs).

### Performance
Current TTFA: ~2–3s (speech → first audio). With streaming + sentence-level TTS: ~1.5–2s (perceivably faster due to early audio). On-device ASR (Phase 2) target: <1s TTFA.

### Verdict
**Grade: B** — Major improvements since June. Streaming LLM responses + barge-in detection now working; user experience significantly improved. Audio session mode upgrade + on-device ASR remain for Phase 2. Current implementation production-ready for TestFlight; Phase 2 latency optimizations in progress.

**Last Updated:** 2026-09-01

---
## Last Updated

2026-06-10 (voice pipeline assessment)

---

## Last Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Speech recognition init reorder | 2026-06-09 | Create recognition task BEFORE installing audio tap (was backwards) |
| Tailscale toggle in SettingsView | 2026-06-xx | Allow easy network switching (LAN vs VPN) |
| Keep single-token auth (Phase 1) | 2026-05-xx | Swap to Authentik OIDC in Phase 2 |

---

## Resource Inventory

### Build & Dependencies
- Xcode 15.4+
- SwiftUI, AVFoundation, Speech frameworks
- ElevenLabs TTS (HTTP client)
- SettingsView stores serverURL and useTailscale in UserDefaults

### Key Services
- **Backend:** CAAL at port 8890 (LAN default) or Tailscale URL
- **TTS:** ElevenLabs API (client-side, via serverURL proxy)
- **STT:** iOS Speech Recognition (on-device)

### Key Source Files
- `SettingsView.swift` — server config, voice selection, Tailscale toggle
- `Sonique/` — main app structure (source tree pending review)
- `Sonique.entitlements` — microphone, speech recognition privacy

### Secrets
- ElevenLabs API key: backend-injected (not in app)
- CAAL token: optional, backend-managed

---

## Build & Deploy

### Local Development
```bash
cd ~/Projects/sonique-ios
open Sonique.xcodeproj
# Scheme: Sonique, Destination: iPhone (latest)
# Cmd+R to build and run in simulator
```

### For App Store / TestFlight
**CRITICAL:** Always use the automated script. Never manually invoke `xcodebuild` or export IPAs.

```bash
cd ~/Projects/sonique-ios
bash scripts/archive-and-upload.sh
```

The script:
- Archives with automatic provisioning (requires Xcode signed in with Apple ID)
- Uploads directly to App Store Connect
- Build appears in TestFlight within 10-15 minutes
- No manual IPA handling required

**Manual Xcode workflow NOT SUPPORTED** — CLI `xcodebuild` commands fail due to missing keychain authentication

### Testing
- Test on real device for microphone + speech recognition
- Verify Tailscale toggle switches serverURL correctly
- Confirm ElevenLabs TTS plays audio end-to-end

---

## Next Steps

1. **[Priority: High]** Complete App Store review cycle — address any remaining submission feedback; ship Phase 1 to production.

2. **[Priority: Med]** Phase 2 (Authentik OIDC) — implement multi-account support with device-specific registration; enable team access.

3. **[Priority: Med]** Add offline mode — cache recent conversations and offline TTS; enable voice interaction without network connectivity.

---

## Known Issues

- **Error 301:** Fixed 2026-06-09 (speech recognition initialization order)
- **App Store rejections:** Resolved privacy description issues (Build 44+)
- **Settings persistence:** UserDefaults stores config safely, no secrets in app

---

## Key Contacts

- **Owner:** Charlie Seay
- **Paired agents:** Cursor (App Store fixes), NVIDIA (analysis)

---

## See Also

- Vault: `Projects/Sonique/`
- macOS sibling: `~/Projects/sonique-mac` (menu bar controller)
- CAAL backend: `~/Projects/cael/` (server)
- Build instructions: Vault note `Build Instructions — Jarvis Mode.md`
