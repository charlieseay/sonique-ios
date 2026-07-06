# Sonique iOS — App Store Release Checklist

## Release Summary

| Field | Value |
|-------|-------|
| App | Sonique |
| Bundle ID | `com.seayniclabs.sonique` |
| Marketing Version | 2.1.0 |
| Build Number | 129 (incremented from 128 — ASC collision avoidance) |
| Team ID | 7NSS5CJL9E |
| ASC Link | https://appstoreconnect.apple.com/apps |
| Git Branch | `fix/tailscale-tts-init` |

## Build 129 Highlights

- App Intents framework with Siri-discoverable shortcuts (`StartListeningIntent`, Slack, Linear, GitHub, Notion, Docker)
- Siri phrases: "Hey Sonique", "Start Sonique", "Talk to Sonique"
- Native EventKit calendar/reminders integration
- Kokoro TTS via SoniqueBar (LAN/Tailscale) with ElevenLabs fallback
- WhisperKit on-device speech recognition
- Voice loop with pattern-matched instant responses

## Pre-Submission Checklist

- [x] AWS CLI verified in PATH (`/opt/homebrew/bin/aws`)
- [x] Local Release build succeeds (`xcodebuild` on CS3Pro11)
- [x] `CURRENT_PROJECT_VERSION = 128` in pbxproj (app + test targets)
- [x] `CFBundleVersion = 128` in Info.plist
- [x] App Intents metadata generated (`Metadata.appintents/root.ssu.yaml`)
- [x] `StartListeningIntent` discoverable with shortcut phrases
- [ ] Archive uploaded to App Store Connect
- [ ] Build 128 processing complete in ASC
- [ ] Export compliance completed (if prompted)
- [ ] ASC submission form complete (privacy, contact, keywords, screenshots)
- [ ] Submitted for App Review
- [ ] Approved by Apple
- [ ] Released to App Store (manual or automatic)

## Submission Steps

### 1. Archive & Upload

```bash
cd ~/Projects/sonique-ios && bash scripts/archive-and-upload.sh
```

### 2. App Store Connect — After Upload

1. Go to https://appstoreconnect.apple.com → **Sonique** → **TestFlight**
2. Wait for Build 128 to finish **Processing** (~10–15 min)
3. Complete **Export Compliance** if prompted (uses encryption: No for standard HTTPS only)
4. Go to **App Store** tab → select version **2.1.0**
5. Select **Build 128** under Build
6. Complete submission questionnaire:
   - Privacy: Yes, all required privacy data types documented
   - Calendar/Reminders: On-device EventKit only, not sent to server
   - Contact URL and Privacy Policy URL verified
7. **Submit for Review**

### 3. Post-Approval

1. ASC → **Release** → Choose Build 128 → Set release (manual or automatic)
2. Verify on device: App Store → Search "Sonique" → Install
3. Functional test: mic → "what time is it" → <1s response
4. Siri test: "Hey Siri, Sonique" → app opens, mic active
5. Settings → TTS Provider → verify Kokoro option persists

## Release Notes (Build 128)

```
Build 128: App Intents for Siri voice shortcuts, calendar/reminders integration, Kokoro TTS option, and improved voice loop performance.
```

## Review & Metrics Log

| Date | Event | Notes |
|------|-------|-------|
| 2026-07-06 | Build 128 prepared | Local build verified, archive upload initiated |
| | Submitted for review | |
| | Approved | |
| | Released to App Store | |
| | Day-1 installs | |
| | Day-1 crash rate | Target: 0% |

## Known Limitations (Build 128)

- **VoiceBox embedded Kokoro**: Not included — Kokoro TTS routes through SoniqueBar on Mac (LAN/Tailscale). ElevenLabs cloud is the default and fallback.
- **Embedded TTS binary** (211MB PyInstaller): Deferred to future build; requires manual Xcode integration of `EmbeddedTTSProvider.swift` + `sonique-tts` binary.

## Recovery

- **Build number collision**: Increment to 129 in pbxproj + Info.plist, re-archive
- **Rejection**: Address ASC feedback, increment build, re-submit within 24h
- **Code signing fail**: Re-run with `-allowProvisioningUpdates` or refresh profiles in Xcode

## Validation Commands

```bash
# Verify build compiles
cd ~/Projects/sonique-ios
xcodebuild -project Sonique.xcodeproj -scheme Sonique \
  -destination "platform=iOS,id=00008027-0015599C2185002E" build 2>&1 \
  | grep -E "BUILD SUCCEEDED|error:" | tail -1

# Verify build number
grep CURRENT_PROJECT_VERSION Sonique.xcodeproj/project.pbxproj | head -2
grep CFBundleVersion Sonique/Resources/Info.plist
```

## Tag (post-approval)

```bash
git tag -a v1.0-appstore -m "Sonique iOS Build 128 — App Store release"
```
