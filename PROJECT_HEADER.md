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

## Current Phase

**Phase 1:** App Store submission (fixing rejection-blocking issues)

**Next:** Authentik OIDC + multi-account support (Phase 2)

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
