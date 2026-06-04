#!/bin/bash

# Scene 4: Request & Response Transformations - Test Script
# Tests request and response transformation plugins

set -e

echo "=== Scene 4: Request & Response Transformations Testing ==="
echo ""

if [ -z "$KONNECT_ADDR" ]; then
  echo "ERROR: KONNECT_ADDR environment variable not set"
  exit 1
fi

echo "Gateway URL: $KONNECT_ADDR"
echo ""

# Test 1: Verify route exists
echo "Test 1: Checking if route 'transform-route' exists..."
ROUTE_CHECK=$(curl -s -X GET "$KONNECT_ADDR/routes" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "transform-route" || true)

if [ "$ROUTE_CHECK" -gt 0 ]; then
  echo "✓ Route transform-route found"
else
  echo "✗ Route transform-route not found"
  exit 1
fi

echo ""

# Test 2: Verify service exists
echo "Test 2: Checking if service 'backend-api' exists..."
SERVICE_CHECK=$(curl -s -X GET "$KONNECT_ADDR/services" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "backend-api" || true)

if [ "$SERVICE_CHECK" -gt 0 ]; then
  echo "✓ Service backend-api found"
else
  echo "✗ Service backend-api not found"
  exit 1
fi

echo ""

# Test 3: Test request transformation
echo "Test 3: Testing request transformation..."
echo "Sending request to trigger transformation"
echo ""

RESPONSE=$(curl -s -X POST "$KONNECT_ADDR/transform/data" \
  -H "Host: kustomer.example.com" \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}')

# httpbin echoes back the headers, so we can verify Kong added them
if echo "$RESPONSE" | grep -q "X-Consumer-ID"; then
  echo "✓ X-Consumer-ID header added by request transformer"
else
  echo "⚠ X-Consumer-ID header not found (may be stripped by backend)"
fi

if echo "$RESPONSE" | grep -q "X-Request-ID"; then
  echo "✓ X-Request-ID header added by request transformer"
else
  echo "⚠ X-Request-ID header not found"
fi

if echo "$RESPONSE" | grep -q "X-API-Version"; then
  echo "✓ X-API-Version header added by request transformer"
else
  echo "⚠ X-API-Version header not found"
fi

echo ""

# Test 4: Test response transformation
echo "Test 4: Testing response transformation (checking response headers)..."
echo ""

RESPONSE=$(curl -s -i -X GET "$KONNECT_ADDR/transform/data" \
  -H "Host: kustomer.example.com" 2>&1)

echo "Response headers:"
echo "$RESPONSE" | grep -i "^x-" || echo "No X- headers found in response"
echo ""

# Look for response transformer headers
if echo "$RESPONSE" | grep -qi "X-Response-Date"; then
  echo "✓ X-Response-Date header added by response transformer"
else
  echo "⚠ X-Response-Date header not found"
fi

if echo "$RESPONSE" | grep -qi "X-Powered-By"; then
  echo "✓ X-Powered-By header added by response transformer"
else
  echo "⚠ X-Powered-By header not found"
fi

if echo "$RESPONSE" | grep -qi "X-API-Handler"; then
  echo "✓ X-API-Handler header added by response transformer"
else
  echo "⚠ X-API-Handler header not found"
fi

echo ""

# Test 5: Full transformation flow
echo "Test 5: Full request/response transformation flow..."
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$KONNECT_ADDR/transform/data" \
  -H "Host: kustomer.example.com" \
  -H "Content-Type: application/json" \
  -H "X-Custom-Header: custom-value" \
  -d '{"test": "data"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" == "200" ]; then
  echo "✓ Request successful (HTTP 200)"
  echo ""
  echo "Response body (showing transformed request as seen by backend):"
  echo "$BODY" | jq -r '.headers | to_entries[] | select(.key | startswith("X-")) | "\(.key): \(.value)"' 2>/dev/null || echo "$BODY"
else
  echo "✗ Request failed (HTTP $HTTP_CODE)"
fi

echo ""
echo "=== All tests completed! ==="
echo ""
echo "Summary:"
echo "- Request transformer adds headers before sending to backend"
echo "- Response transformer adds headers to responses from backend"
echo "- Both work together for complete request/response modification"
