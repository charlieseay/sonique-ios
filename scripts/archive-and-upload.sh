#!/bin/bash
# archive-and-upload.sh — Archive Sonique and upload to App Store Connect
#
# Usage: ./scripts/archive-and-upload.sh
#
# Prerequisites:
#   - App record must exist in App Store Connect (bundle ID: com.seayniclabs.sonique)
#   - Signed into Xcode with your Apple Developer account
#   - Automatic signing enabled
#
# After upload:
#   - Build appears in App Store Connect → TestFlight within ~15 minutes
#   - Complete Export Compliance on the build if prompted
#   - Add build to internal/external testing group

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="Sonique"
ARCHIVE_PATH="$PROJECT_DIR/build/Sonique.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/Export"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

echo "====================================="
echo "  Step 1: Clean build folder"
echo "====================================="
rm -rf "$PROJECT_DIR/build"
xcodebuild clean -scheme "$SCHEME" -configuration Release 2>&1 | tail -3

echo ""
echo "====================================="
echo "  Step 2: Archive"
echo "====================================="
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    2>&1 | grep -E "error:|warning:|Archive|ARCHIVE|Signing|error|succeeded|failed" | tail -20

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive failed — no .xcarchive created"
    exit 1
fi
echo "  → Archive: $ARCHIVE_PATH"

echo ""
echo "====================================="
echo "  Step 3: Export & Upload to ASC"
echo "====================================="
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    2>&1 | grep -E "error:|warning:|Export|Upload|Uploading|uploaded|succeeded|failed" | tail -20

echo ""
echo "====================================="
echo "  Done!"
echo "====================================="
echo ""
echo "Build uploaded to App Store Connect."
echo ""
echo "Next steps:"
echo "  1. appstoreconnect.apple.com → Sonique → TestFlight"
echo "  2. Wait for the build to finish Processing (~10-15 min)"
echo "  3. Complete Export Compliance if prompted"
echo "  4. Add build to your testing group"
