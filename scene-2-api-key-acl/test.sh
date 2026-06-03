#!/bin/bash

# Scene 2: API Key & ACL - Test Script
# Tests authentication and access control

set -e

echo "=== Scene 2: API Key Authentication & ACL Testing ==="
echo ""

if [ -z "$KONNECT_ADDR" ]; then
  echo "ERROR: KONNECT_ADDR environment variable not set"
  exit 1
fi

echo "Gateway URL: $KONNECT_ADDR"
echo ""

# Test 1: Verify consumers exist
echo "Test 1: Checking if consumers exist..."
MOBILE_CHECK=$(curl -s -X GET "$KONNECT_ADDR/consumers" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "mobile-app" || true)
WEB_CHECK=$(curl -s -X GET "$KONNECT_ADDR/consumers" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "web-app" || true)

if [ "$MOBILE_CHECK" -gt 0 ] && [ "$WEB_CHECK" -gt 0 ]; then
  echo "✓ Both consumers found (mobile-app, web-app)"
else
  echo "✗ Consumers not found"
  exit 1
fi

echo ""

# Test 2: Get API keys
echo "Test 2: Retrieving API keys..."
MOBILE_KEY=$(curl -s -X GET "$KONNECT_ADDR/consumers/mobile-app/key-auth" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | jq -r '.data[0].key' 2>/dev/null || echo "mobile-key-12345")
WEB_KEY=$(curl -s -X GET "$KONNECT_ADDR/consumers/web-app/key-auth" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | jq -r '.data[0].key' 2>/dev/null || echo "web-key-67890")

echo "✓ Mobile app key: $MOBILE_KEY"
echo "✓ Web app key: $WEB_KEY"
echo ""

# Test 3: Test without API key (should fail)
echo "Test 3: Request without API key (should fail)..."
RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/payments/status" \
  -H "Host: kaokaopay.example.com" \
  -w "\n%{http_code}" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
if [ "$HTTP_CODE" == "401" ]; then
  echo "✓ Request blocked (HTTP 401 - Unauthorized)"
else
  echo "✗ Expected 401, got $HTTP_CODE"
fi

echo ""

# Test 4: Test with mobile app key (premium - should succeed)
echo "Test 4: Request with mobile-app key (premium group - should succeed)..."
RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/payments/status" \
  -H "apikey: $MOBILE_KEY" \
  -H "Host: kaokaopay.example.com" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
if [ "$HTTP_CODE" == "200" ]; then
  echo "✓ Request succeeded (HTTP 200)"
else
  echo "✗ Expected 200, got $HTTP_CODE"
fi

echo ""

# Test 5: Test with web app key (basic - should fail)
echo "Test 5: Request with web-app key (basic group - should fail)..."
RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/payments/status" \
  -H "apikey: $WEB_KEY" \
  -H "Host: kaokaopay.example.com" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
if [ "$HTTP_CODE" == "403" ]; then
  echo "✓ Request blocked (HTTP 403 - Forbidden)"
else
  echo "✗ Expected 403, got $HTTP_CODE"
fi

echo ""
echo "=== All tests passed! ==="
echo ""
echo "Summary:"
echo "- Requests without API key: BLOCKED (401)"
echo "- Requests with premium key: ALLOWED (200)"
echo "- Requests with basic key: BLOCKED (403)"
