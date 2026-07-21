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

## Assessment — 2026-06-10

### Errors & Risks
[CRIT] Voice pipeline is strictly sequential (listen → process → speak) instead of streaming; latency feels 2–3x slower than Claude iOS voice mode (3–5s vs <1s TTFA). No streaming LLM response handling (VoiceLoop.swift:149-159) means TTS doesn't start until full response received. Audio session `.default` mode in `.record` category (SpeechRecognitionService.swift:85-89) blocks live duplex + barge-in; OSStatus -50 bug indicates incompatibility with Bluetooth + `.default` mode combo.

[HIGH] No interrupt handling (barge-in) — user cannot interrupt mid-response; feels unnatural vs Claude mode. No streaming transcripts — ElevenLabs cloud STT returns full transcript after ~1s silence, not word-by-word; eliminates early LLM inference. Audio session stays in `.record` mode, preventing `.voiceChat` echo cancellation for live duplex.

[MED] ElevenLabs WebSocket dependency adds 500ms–1s cloud STT roundtrip; migrating to on-device (WhisperKit + Silero VAD) would halve initial latency. TTS not pipelined with LLM — synthesis doesn't start until full response text ready; streaming TTS could reduce TTFA by 1–2s.

### Security
✓ No secrets in code (API key fetched from SoniqueBar, not bundled). ✓ Microphone + speech recognition entitlements correct. ✓ Tailscale toggle properly isolated to UserDefaults.

### Improvements
1. Replace ElevenLabs cloud STT with WhisperKit (on-device, streaming) + Silero VAD (CoreML) → <400ms to first transcript (vs 500ms–1s cloud)
2. Wire SoniqueBar to stream LLM responses (SSE or chunked) → detect sentence boundaries → start TTS on first sentence complete → TTFA <1s (vs 2–3s)
3. Switch audio session to `.voiceChat` mode before TTS; enable barge-in (VAD-based interrupt) → interruptible responses (vs currently not interruptible)
4. Add TTSQueue for parallel synthesis; implement interrupt logic to stop audio + cancel LLM stream + restart STT
5. Phase 4: Add AVSpeechSynthesizer fallback for fast cached responses (<200ms TTFA for common phrases)

**Full redesign spec:** See vault note `Voice Pipeline Redesign — 2026-06-10.md` (4-phase plan, latency budgets, component choices, risk analysis).

### Cost
Minimal: WhisperKit integration via CocoaPods; no new cloud service. Kokoro TTS optional (same interface as ElevenLabs). Time: ~8–10 days for full pipeline (4 phases).

### Performance
Current: TTFA 2–3s (speech → first audio). Redesigned: <1s TTFA. Full response latency unchanged (~3–5s), but user perceives improvement because audio starts immediately instead of waiting for LLM + TTS.

### Verdict
**D** (Poor) — Sequential architecture + cloud STT + no streaming LLM + no barge-in make this feel slow and unresponsive vs Claude iOS voice mode. Code quality is good (clean error handling, proper async/await), but architecture is fundamentally request-response, not streaming duplex. Redesign is critical for "feels like Claude" goal. Effort: medium (4 phases, ~8–10 days). Risk: medium (WhisperKit reliability on older iPhone models; Silero VAD tuning per device). Recommend phased rollout: Phase 1 (on-device VAD+ASR) → Phase 2 (streaming LLM) → Phase 3 (barge-in) → Phase 4 (fallbacks).

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
