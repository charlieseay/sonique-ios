#!/bin/bash
# Test capability discovery system

echo "🔍 Testing Sonique Capability Discovery"
echo "========================================"
echo ""

# Test 1: Backend /capabilities endpoint
echo "📡 Test 1: Backend capabilities endpoint"
echo "----------------------------------------"
curl -s http://192.168.0.221:8890/capabilities | python3 -m json.tool
echo ""

# Test 2: Backend /health endpoint
echo "🏥 Test 2: Backend health check"
echo "--------------------------------"
curl -s http://192.168.0.221:8890/health
echo ""

# Test 3: Home Assistant direct check (if available)
echo "🏠 Test 3: Home Assistant availability"
echo "---------------------------------------"
if [ -f /Volumes/data/secrets/ha_token ]; then
    HA_TOKEN=$(cat /Volumes/data/secrets/ha_token)
    curl -s -H "Authorization: Bearer $HA_TOKEN" http://homeassistant.local:8123/api/ | head -c 100
    echo ""
else
    echo "HA token not found - skipping"
fi
echo ""

# Test 4: MCP CLI status (if Claude CLI available)
echo "🔌 Test 4: MCP servers via Claude CLI"
echo "--------------------------------------"
if command -v claude &> /dev/null; then
    claude mcp list 2>&1 | head -20
else
    echo "Claude CLI not available - skipping"
fi
echo ""

echo "✅ Discovery test complete"
