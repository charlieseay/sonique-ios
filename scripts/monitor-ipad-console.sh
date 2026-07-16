#!/bin/bash
# Open Console.app and configure it for Sonique iPad monitoring

set -e

echo "🚀 Opening Console.app for iPad monitoring..."
echo ""
echo "📋 Manual Setup Steps:"
echo "1. Select 'CS3Pro11' in the left sidebar under Devices"
echo "2. Click the 'Start' button in the toolbar"
echo "3. In the search bar, enter this predicate:"
echo ""
echo "   subsystem == \"com.seayniclabs.sonique\" OR processImagePath CONTAINS \"Sonique\""
echo ""
echo "4. Click the filter button (funnel icon) to apply"
echo ""
echo "💡 Tip: Right-click a log line → 'Copy' to save messages"
echo ""

# Open Console.app
open -a Console

# Give it a moment to open
sleep 2

# Copy predicate to clipboard for easy paste
echo 'subsystem == "com.seayniclabs.sonique" OR processImagePath CONTAINS "Sonique"' | pbcopy

echo "✅ Console.app opened"
echo "📋 Predicate copied to clipboard - just paste it in the search bar!"
