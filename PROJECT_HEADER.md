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

## Assessment — 2026-10-07

### Errors & Risks
[CRIT] Voice pipeline still strictly sequential (listen → process → speak); no evidence of streaming redesign shipped since 2026-06-10. TTFA remains 2–3s (latency unchanged). SoniqueBar streaming endpoint shipped 2026-06-11, but iOS has not been updated to consume it. Audio session mode still blocks duplex scenarios.

[HIGH] No interrupt/barge-in handling. ElevenLabs cloud STT still in use (500ms–1s latency); on-device alternative (WhisperKit) not implemented. TTS initialization delayed until full LLM response received.

[MED] Recent voice switches (ElevenLabs Jessica, VoiceBox integration) working but don't address core latency issue. Build 205 latest (Aug 31 git log shows prior commits through June).

### Security
✓ No hardcoded secrets (tokens properly proxied via backend). ✓ Entitlements correct (microphone, speech recognition). ✓ UserDefaults config storage secure. ✓ Tailscale toggle properly scoped.

### Improvements (Blocked)
SoniqueBar now streams responses (2026-06-11 endpoint live), but iOS VoiceLoop.swift still awaits full response before calling TTS. Wire iOS to consume `/command/stream` endpoint: parse sentence boundaries from NDJSON chunks, start TTS on first chunk while LLM generates rest.

### Cost
Effort blocked on architecture decision (consume streaming vs redesign to duplex). No new services required if streaming approach used.

### Performance
**Unchanged:** TTFA 2–3s. Redesign window closed; iOS team deprioritized voice pipeline overhaul. Current voice interaction acceptable for assistant-assistant use, not for user-facing voice mode.

### Verdict
**Grade: C+** (was D 2026-06-10, regressed—implementation blocked) — Core latency issue unresolved; streaming backend available but not consumed by iOS. Architecture mismatch persists. Effort to fix is low (wire iOS to consume streaming), but no progress since June. Not blocking production (TestFlight phase), but "feels like Claude" goal deferred indefinitely.

---

## Last Updated

2026-10-07 (voice pipeline assessment)

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
