#!/bin/bash

# Scene 1: Services & Routes - Test Script
# Tests basic routing functionality

set -u

echo "=== Scene 1: Services & Routes Testing ==="
echo ""

if [ -z "${KONNECT_ADDR:-}" ]; then
  echo "ERROR: KONNECT_ADDR environment variable not set"
  echo "Set it with: export KONNECT_ADDR=https://<your-gateway-url>"
  exit 1
fi

if [ -z "${KONNECT_TOKEN:-}" ]; then
  echo "ERROR: KONNECT_TOKEN environment variable not set"
  exit 1
fi

# Serverless Gateway Proxy URL(KONNECT_ADDR) does not expose Admin API paths.
# Entity checks use Konnect Control Plane core-entities API.
KONNECT_API_ADDR="${KONNECT_API_ADDR:-https://us.api.konghq.com}"

if [ -z "${KONNECT_CP_ID:-}" ]; then
  CP_NAME="${KONNECT_CONTROL_PLANE_NAME:-${DECK_KONNECT_CONTROL_PLANE_NAME:-}}"
  if [ -z "$CP_NAME" ]; then
    echo "ERROR: Set KONNECT_CP_ID or KONNECT_CONTROL_PLANE_NAME (or DECK_KONNECT_CONTROL_PLANE_NAME)"
    exit 1
  fi

  echo "Looking up control plane ID for '$CP_NAME'..."

  CP_RESULT=$(curl -s -G "${KONNECT_API_ADDR}/v2/control-planes" \
    --data-urlencode "filter[name][eq]=${CP_NAME}" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -w $'\n%{http_code}') || {
    echo "ERROR: curl failed to reach Konnect API ($KONNECT_API_ADDR)"
    exit 1
  }

  CP_HTTP_CODE=$(echo "$CP_RESULT" | tail -n 1)
  CP_RESPONSE=$(echo "$CP_RESULT" | sed '$d')

  if [ "$CP_HTTP_CODE" != "200" ]; then
    echo "ERROR: Control plane lookup failed (HTTP $CP_HTTP_CODE)"
    echo "$CP_RESPONSE"
    exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    KONNECT_CP_ID=$(echo "$CP_RESPONSE" | jq -r '.data[0].id // empty' 2>/dev/null || true)
  else
    KONNECT_CP_ID=$(echo "$CP_RESPONSE" | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[0-9a-f-]+"' | head -1 | grep -Eo '[0-9a-f-]{36}' || true)
  fi

  if [ -z "$KONNECT_CP_ID" ]; then
    echo "ERROR: Could not find control plane '$CP_NAME'"
    echo "$CP_RESPONSE"
    exit 1
  fi

  echo "Resolved Control Plane ID: $KONNECT_CP_ID (name: $CP_NAME)"
  echo ""
fi

KONNECT_ADMIN_ADDR="${KONNECT_API_ADDR}/v2/control-planes/${KONNECT_CP_ID}/core-entities"

echo "Gateway URL: $KONNECT_ADDR"
echo "Admin API:   $KONNECT_ADMIN_ADDR"
echo ""

# Test 1: Verify service exists
echo "Test 1: Checking if service 'httpbin-service' exists..."
SERVICE_RESULT=$(curl -s -X GET "$KONNECT_ADMIN_ADDR/services" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to query services"
  exit 1
}

SERVICE_HTTP_CODE=$(echo "$SERVICE_RESULT" | tail -n 1)
SERVICE_BODY=$(echo "$SERVICE_RESULT" | sed '$d')

if [ "$SERVICE_HTTP_CODE" != "200" ]; then
  echo "✗ Service lookup failed (HTTP $SERVICE_HTTP_CODE)"
  echo "$SERVICE_BODY"
  exit 1
fi

SERVICE_CHECK=$(echo "$SERVICE_BODY" | grep -c "httpbin-service" || true)

if [ "$SERVICE_CHECK" -gt 0 ]; then
  echo "✓ Service httpbin-service found"
else
  echo "✗ Service httpbin-service not found"
  exit 1
fi

echo ""

# Test 2: Verify route exists
echo "Test 2: Checking if route 'json-route' exists..."
ROUTE_RESULT=$(curl -s -X GET "$KONNECT_ADMIN_ADDR/routes" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to query routes"
  exit 1
}

ROUTE_HTTP_CODE=$(echo "$ROUTE_RESULT" | tail -n 1)
ROUTE_BODY=$(echo "$ROUTE_RESULT" | sed '$d')

if [ "$ROUTE_HTTP_CODE" != "200" ]; then
  echo "✗ Route lookup failed (HTTP $ROUTE_HTTP_CODE)"
  echo "$ROUTE_BODY"
  exit 1
fi

ROUTE_CHECK=$(echo "$ROUTE_BODY" | grep -c "json-route" || true)

if [ "$ROUTE_CHECK" -gt 0 ]; then
  echo "✓ Route json-route found"
else
  echo "✗ Route json-route not found"
  exit 1
fi

echo ""

# Test 3: Test routing with curl
echo "Test 3: Testing request through Kong gateway..."
echo "Sending GET request to $KONNECT_ADDR/anything"
echo ""

RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/anything" \
  -H "Host: kustomer.example.com" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to send request through gateway"
  exit 1
}

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

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
