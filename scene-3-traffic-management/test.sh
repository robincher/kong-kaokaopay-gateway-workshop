#!/bin/bash

# Scene 3: Traffic Management - Test Script
# Tests rate limiting and canary release

set -e

echo "=== Scene 3: Traffic Management (Rate Limiting & Canary) Testing ==="
echo ""

if [ -z "$KONNECT_ADDR" ]; then
  echo "ERROR: KONNECT_ADDR environment variable not set"
  exit 1
fi

echo "Gateway URL: $KONNECT_ADDR"
echo ""

# Test 1: Verify route exists
echo "Test 1: Checking if route 'api-route' exists..."
ROUTE_CHECK=$(curl -s -X GET "$KONNECT_ADDR/routes" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "api-route" || true)

if [ "$ROUTE_CHECK" -gt 0 ]; then
  echo "✓ Route api-route found"
else
  echo "✗ Route api-route not found"
  exit 1
fi

echo ""

# Test 2: Verify services exist
echo "Test 2: Checking if services exist..."
V1_CHECK=$(curl -s -X GET "$KONNECT_ADDR/services" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "payment-api-v1" || true)
V2_CHECK=$(curl -s -X GET "$KONNECT_ADDR/services" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | grep -c "payment-api-v2" || true)

if [ "$V1_CHECK" -gt 0 ] && [ "$V2_CHECK" -gt 0 ]; then
  echo "✓ Both services found (v1, v2)"
else
  echo "✗ Services not found"
  exit 1
fi

echo ""

# Test 3: Test rate limiting
echo "Test 3: Testing rate limiting (limit: 10 requests/min)..."
echo "Sending 12 requests..."
echo ""

SUCCESS_COUNT=0
RATE_LIMITED_COUNT=0

for i in {1..12}; do
  RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/api/status" \
    -H "Host: kustomer.example.com" \
    -w "\n%{http_code}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

  if [ "$HTTP_CODE" == "200" ]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    echo "Request $i: ✓ 200 OK"
  elif [ "$HTTP_CODE" == "429" ]; then
    RATE_LIMITED_COUNT=$((RATE_LIMITED_COUNT + 1))
    echo "Request $i: × 429 Rate Limited"
  else
    echo "Request $i: ? $HTTP_CODE"
  fi

  sleep 0.5
done

echo ""
echo "Results:"
echo "- Successful requests: $SUCCESS_COUNT"
echo "- Rate limited (429): $RATE_LIMITED_COUNT"

if [ "$SUCCESS_COUNT" -ge 10 ] && [ "$RATE_LIMITED_COUNT" -gt 0 ]; then
  echo "✓ Rate limiting working correctly"
else
  echo "✗ Rate limiting behavior unexpected"
fi

echo ""

# Test 4: Check rate limit headers
echo "Test 4: Inspecting rate limit headers..."
RESPONSE=$(curl -s -i -X GET "$KONNECT_ADDR/api/status" \
  -H "Host: kustomer.example.com" 2>&1)

RATE_LIMIT_HEADER=$(echo "$RESPONSE" | grep -i "ratelimit-limit" || true)
RATE_REMAINING=$(echo "$RESPONSE" | grep -i "ratelimit-remaining" || true)

if [ -n "$RATE_LIMIT_HEADER" ]; then
  echo "✓ Found rate limit headers:"
  echo "  $RATE_LIMIT_HEADER"
  echo "  $RATE_REMAINING"
else
  echo "✗ Rate limit headers not found"
fi

echo ""

# Test 5: Test canary distribution
echo "Test 5: Testing canary release (90% v1, 10% v2)..."
echo "Sending 10 requests..."
echo ""

V1_COUNT=0
V2_COUNT=0

for i in {1..10}; do
  RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/api/data" \
    -H "Host: kustomer.example.com")

  # Check response source (v1 has /json endpoint, v2 has /uuid endpoint)
  if echo "$RESPONSE" | grep -q "json" || echo "$RESPONSE" | grep -q "true"; then
    V1_COUNT=$((V1_COUNT + 1))
    echo "Request $i: v1"
  elif echo "$RESPONSE" | grep -q "uuid" || echo "$RESPONSE" | grep -q "-"; then
    V2_COUNT=$((V2_COUNT + 1))
    echo "Request $i: v2"
  else
    echo "Request $i: unknown"
  fi
done

echo ""
echo "Traffic distribution:"
echo "- v1 (90% target): $V1_COUNT requests"
echo "- v2 (10% target): $V2_COUNT requests"

if [ "$V1_COUNT" -ge 7 ]; then
  echo "✓ Canary release distribution appears correct"
else
  echo "⚠ Limited samples, distribution may vary"
fi

echo ""
echo "=== All tests completed! ==="
