# Sonique iOS

SwiftUI voice assistant client for the CAAL backend engine.  
Connects to your self-hosted CAAL server via LiveKit WebRTC.

## Setup

### 1. Generate the Xcode project

```bash
brew install xcodegen
cd ~/Projects/sonique-ios
xcodegen generate
open Sonique.xcodeproj
```

### 2. Add your Development Team

In Xcode → Sonique target → Signing & Capabilities, set your Apple Developer team.

### 3. Add the Intents capability

In Xcode → Sonique target → Signing & Capabilities → "+ Capability" → **Siri**.

### 4. Build & run on device

LiveKit WebRTC requires a real device (not simulator) for audio.

## First run

1. Open the app → tap **Connect to Base Station**
2. Enter your CAAL server URL, e.g. `http://192.168.0.221:3000`
3. Optional: set an API key if you've set `CAAL_API_KEY` on the server
4. Tap **Test Connection** to verify
5. Tap **Done** — the app returns to the main screen ready to connect

## Siri shortcut

Default phrases work immediately (no setup required):
- "Hey Siri, Ask Sonique"
- "Hey Siri, Start Sonique"  
- "Hey Siri, Open Sonique session"

For a custom phrase, go to **Settings → Siri** and tap **Open in Shortcuts**.

## CAAL server — optional API key

Set `CAAL_API_KEY=<caal-api-key>` in the CAAL `.env.local` to require authentication.  
The iOS app sends it as `x-api-key` header on all API calls.

Provider scaffolding (UI/config only, no behavior changes yet) uses feature-flagged values:

```bash
NVIDIA_FEATURE_ENABLED=false
NVIDIA_BASE_URL=<nvidia-base-url>
NVIDIA_MODEL=<nvidia-model-id>
```

## Architecture

```
SoniqueApp/
  SoniqueApp.swift          App entry, URL scheme + intent handling
  Intents/
    ConnectIntent.swift     AppIntent + AppShortcutsProvider
  Models/
    SessionState.swift      State enums
    ConnectionDetails.swift API response model
  Services/
    SessionManager.swift    LiveKit room + state machine
    SoniqueSettings.swift   AppStorage wrapper
  Views/
    OnboardingView.swift    First-run screen
    HomeView.swift          Main UI
    OrbView.swift           Animated orb (idle/connecting/active/speaking)
    SettingsView.swift      Server URL, API key, Siri config
    DesignSystem.swift      Colors, components
  Resources/
    Info.plist              URL scheme, microphone permission
```
