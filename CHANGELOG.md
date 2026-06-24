# Sonique iOS - Changelog

## Build 116 (2.1.0) - 2026-06-24

### 🎉 New Features

**Native iOS Capabilities**
- **Calendar Integration**: View today's events and create calendar entries via voice commands
  - "Hey Quinn, what's on my calendar today?"
  - "Create an event for tomorrow at 3pm"
- **Reminders**: List and create reminders hands-free
  - "What are my reminders?"
  - "Remind me to call Sarah"
- **Messages**: Send text messages via voice
  - "Send a message to John saying I'm on my way"
- **Mail**: Compose emails via voice
  - "Send an email to support about my question"
- **Apple Intelligence**: iOS 18.1+ Writing Tools and Image Playground support
  - Auto-detected on compatible devices
  - Gracefully falls back on older devices

**Architecture Improvements**
- Smart capability routing: Native iOS capabilities execute locally before routing to Mac backend
- Voice command parsing with natural language understanding
- SwiftUI coordinators for seamless message/mail composition

### 🔧 Technical Changes

- Implemented `NativeCapabilities.swift` using EventKit and MessageUI frameworks
- Added `CapabilityExecutor.swift` for voice command parsing and routing
- Created `MessageMailCoordinator.swift` for UIKit/SwiftUI bridging
- Added `AppleIntelligenceCapabilities.swift` with iOS 18.1+ availability detection
- Integrated native capabilities into VoiceLoop processing pipeline

### 📱 Permissions Required

New permission requests on first use:
- Calendar access (for events)
- Reminders access (for task management)

### 🐛 Bug Fixes

- Fixed app crash on launch related to HomeKit initialization
- Removed HomeKit temporarily (will return with proper App Store entitlement)
- Improved VoiceLoop error handling for native capability fallback

### 🚀 What's Next

- HomeKit integration (requires App Store entitlement setup)
- Enhanced Apple Intelligence features as APIs become available
- Expanded voice command vocabulary
- Shortcuts integration for custom automations

---

## Build 109 (2.1.0) - Previous Release

- Voice assistant baseline with Mac backend integration
- ElevenLabs TTS integration
- Apple Speech Recognition
- Tailscale connectivity support
