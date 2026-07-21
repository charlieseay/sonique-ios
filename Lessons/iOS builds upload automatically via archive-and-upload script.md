---
tags: [lesson, sonique, ios, xcode, testflight]
created: 2026-06-09
---

# Lesson: iOS builds upload automatically via archive-and-upload.sh script

## What happened

Build 47 needed to be created and uploaded to TestFlight. Instead of using the built-in script, attempts were made to manually run `xcodebuild` commands, which failed due to missing Apple ID authentication in the CLI context.

## Root cause

The project already has a working `scripts/archive-and-upload.sh` script that:
1. Cleans the build folder
2. Archives the app with automatic provisioning (`-allowProvisioningUpdates`)
3. Exports and uploads to App Store Connect in one step
4. Uses Xcode's authenticated session (no manual IPA handling needed)

## The fix

Run the existing script:
```bash
cd ~/Projects/sonique-ios && bash scripts/archive-and-upload.sh
```

The script handles everything automatically:
- Archive creation
- Code signing with Xcode's authenticated Apple ID
- Upload to App Store Connect
- No manual IPA export needed

## Rule

**For Sonique iOS builds:** Always use `scripts/archive-and-upload.sh`. Never manually invoke `xcodebuild archive` or try to export IPAs. The script is designed to work with Xcode's authenticated session and handles all provisioning automatically.

## Why this matters

Manual `xcodebuild` commands fail because:
- They can't access Xcode's keychain-stored Apple ID credentials
- Provisioning profiles require Xcode's automatic management
- The upload step requires App Store Connect API authentication

The script works because it uses `-allowProvisioningUpdates` which leverages Xcode's existing authenticated session.

## Verification

After running the script:
- Archive appears at `~/Projects/sonique-ios/build/Sonique.xcarchive`
- Upload progress shows in the script output
- Build appears in App Store Connect → TestFlight within 10-15 minutes
- Build number can be verified with `agvtool what-version`
