#!/bin/bash

# Scene 1: Services & Routes - Test Script
# Tests basic routing functionality

set -e

echo "=== Scene 1: Services & Routes Testing ==="
echo ""

if [ -z "$KONNECT_ADDR" ]; then
  echo "ERROR: KONNECT_ADDR environment variable not set"
  echo "Set it with: export KONNECT_ADDR=https://<your-gateway-url>"
  exit 1
fi

echo "Gateway URL: $KONNECT_ADDR"
echo ""

# Test 1: Verify service exists
echo "Test 1: Checking if service 'httpbin-service' exists..."
SERVICE_CHECK=$(curl -s -X GET "$KONNECT_ADDR/services" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "httpbin-service" || true)

if [ "$SERVICE_CHECK" -gt 0 ]; then
  echo "✓ Service httpbin-service found"
else
  echo "✗ Service httpbin-service not found"
  exit 1
fi

echo ""

# Test 2: Verify route exists
echo "Test 2: Checking if route 'json-route' exists..."
ROUTE_CHECK=$(curl -s -X GET "$KONNECT_ADDR/routes" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "json-route" || true)

if [ "$ROUTE_CHECK" -gt 0 ]; then
  echo "✓ Route json-route found"
else
  echo "✗ Route json-route not found"
  exit 1
fi

echo ""

# Test 3: Test routing with curl
echo "Test 3: Testing request through Kong gateway..."
echo "Sending GET request to $KONNECT_ADDR/anything/test"
echo ""

RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/anything/test" \
  -H "Host: kustomer.example.com" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" == "200" ]; then
  echo "✓ Request successful (HTTP $HTTP_CODE)"
  echo ""
  echo "Response from httpbin:"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
  echo "✗ Request failed (HTTP $HTTP_CODE)"
  echo "Response: $BODY"
  exit 1
fi

echo ""
echo "=== All tests passed! ==="
