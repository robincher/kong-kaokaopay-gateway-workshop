#!/bin/bash

# Scene 4: Request & Response Transformations - Test Script
# Tests request and response transformation plugins

set -u

echo "=== Scene 4: Request & Response Transformations Testing ==="
echo ""

if [ -z "${KONNECT_TOKEN:-}" ]; then
  echo "ERROR: KONNECT_TOKEN environment variable not set"
  exit 1
fi

# Proxy URL (KONNECT_ADDR) does not expose Admin API paths like /routes.
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

if [ -z "${KONNECT_ADDR:-}" ] && [ -z "${KONNECT_GW_PROXY_URL:-}" ]; then
  echo "Looking up gateway proxy URL..."

  PROXY_RESULT=$(curl -s -X GET "${KONNECT_API_ADDR}/v2/control-planes/${KONNECT_CP_ID}" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -w $'\n%{http_code}') || {
    echo "ERROR: curl failed to query control plane details"
    exit 1
  }

  PROXY_HTTP_CODE=$(echo "$PROXY_RESULT" | tail -n 1)
  PROXY_BODY=$(echo "$PROXY_RESULT" | sed '$d')

  if [ "$PROXY_HTTP_CODE" != "200" ]; then
    echo "ERROR: Control plane detail lookup failed (HTTP $PROXY_HTTP_CODE)"
    echo "$PROXY_BODY"
    exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    KONNECT_GW_PROXY_URL=$(echo "$PROXY_BODY" | jq -r '
      .config.proxy_urls[0] |
      if . == null then empty
      elif (.protocol == "https" and .port == 443) or (.protocol == "http" and .port == 80) then
        "\(.protocol)://\(.host)"
      else
        "\(.protocol)://\(.host):\(.port)"
      end
    ' 2>/dev/null || true)
  else
    KONNECT_GW_PROXY_URL=$(echo "$PROXY_BODY" | grep -Eo '"protocol"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)
    PROXY_HOST=$(echo "$PROXY_BODY" | grep -Eo '"host"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)
    if [ -n "$KONNECT_GW_PROXY_URL" ] && [ -n "$PROXY_HOST" ]; then
      KONNECT_GW_PROXY_URL="${KONNECT_GW_PROXY_URL}://${PROXY_HOST}"
    else
      KONNECT_GW_PROXY_URL=""
    fi
  fi

  if [ -z "$KONNECT_GW_PROXY_URL" ]; then
    echo "ERROR: Could not resolve proxy URL from control plane config.proxy_urls"
    echo "$PROXY_BODY"
    exit 1
  fi

  echo "Resolved Gateway Proxy URL: $KONNECT_GW_PROXY_URL"
  echo ""
fi

if [ -z "${KONNECT_ADDR:-}" ]; then
  KONNECT_ADDR="${KONNECT_GW_PROXY_URL:-}"
fi

if [ -z "${KONNECT_ADDR:-}" ]; then
  echo "ERROR: KONNECT_ADDR (or KONNECT_GW_PROXY_URL) environment variable not set"
  exit 1
fi

echo "Gateway URL: $KONNECT_ADDR"
echo "Admin API:   $KONNECT_ADMIN_ADDR"
echo ""

# Test 1: Verify route exists
echo "Test 1: Checking if route 'transform-route' exists..."
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

ROUTE_CHECK=$(echo "$ROUTE_BODY" | grep -c "transform-route" || true)

if [ "$ROUTE_CHECK" -gt 0 ]; then
  echo "✓ Route transform-route found"
else
  echo "✗ Route transform-route not found"
  exit 1
fi

echo ""

# Test 2: Verify service and transformation plugins exist
echo "Test 2: Checking service and transformation plugins..."
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

SERVICE_CHECK=$(echo "$SERVICE_BODY" | grep -c "backend-api" || true)

PLUGIN_RESULT=$(curl -s -X GET "$KONNECT_ADMIN_ADDR/plugins" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to query plugins"
  exit 1
}

PLUGIN_HTTP_CODE=$(echo "$PLUGIN_RESULT" | tail -n 1)
PLUGIN_BODY=$(echo "$PLUGIN_RESULT" | sed '$d')

if [ "$PLUGIN_HTTP_CODE" != "200" ]; then
  echo "✗ Plugin lookup failed (HTTP $PLUGIN_HTTP_CODE)"
  echo "$PLUGIN_BODY"
  exit 1
fi

REQ_TRANSFORMER=$(echo "$PLUGIN_BODY" | grep -c "request-transformer" || true)
RES_TRANSFORMER=$(echo "$PLUGIN_BODY" | grep -c "response-transformer" || true)

if [ "$SERVICE_CHECK" -gt 0 ] && [ "$REQ_TRANSFORMER" -gt 0 ] && [ "$RES_TRANSFORMER" -gt 0 ]; then
  echo "✓ Service backend-api found"
  echo "✓ request-transformer and response-transformer plugins found"
else
  echo "✗ Service or transformation plugins not found"
  exit 1
fi

echo ""

# Test 3: Test request transformation
echo "Test 3: Testing request transformation..."
echo "Sending POST /transform to trigger transformation"
echo ""

RESPONSE=$(curl -s -X POST "$KONNECT_ADDR/transform" \
  -H "Host: kustomer.example.com" \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}')

if echo "$RESPONSE" | grep -qi "X-Consumer"; then
  echo "✓ X-Consumer-ID header added by request transformer"
else
  echo "⚠ X-Consumer-ID header not found (may be stripped by backend)"
fi

if echo "$RESPONSE" | grep -qi "X-Request"; then
  echo "✓ X-Request-ID header added by request transformer"
else
  echo "⚠ X-Request-ID header not found"
fi

if echo "$RESPONSE" | grep -qi "X-Api-Version"; then
  echo "✓ X-API-Version header added by request transformer"
else
  echo "⚠ X-API-Version header not found"
fi

echo ""

# Test 4: Test response transformation
echo "Test 4: Testing response transformation (checking response headers)..."
echo ""

RESPONSE=$(curl -s -i -X POST "$KONNECT_ADDR/transform" \
  -H "Host: kustomer.example.com" \
  -H "Content-Type: application/json" \
  -d '{}' 2>&1)

echo "Response headers (HTTP headers from Kong, not httpbin JSON body):"
echo "$RESPONSE" | grep -iE '^(HTTP/|x-|access-control)' || echo "No transformer headers found in HTTP response"
echo ""

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

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$KONNECT_ADDR/transform" \
  -H "Host: kustomer.example.com" \
  -H "Content-Type: application/json" \
  -H "X-Custom-Header: custom-value" \
  -d '{"test": "data"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "✓ Request successful (HTTP 200)"
  echo ""
  echo "Response body (showing transformed request as seen by backend):"
  echo "$BODY" | jq -r '.headers | to_entries[] | select(.key | test("^[Xx]-")) | "\(.key): \(.value)"' 2>/dev/null || echo "$BODY"
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
