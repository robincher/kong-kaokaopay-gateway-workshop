#!/bin/bash

# Scene 2: API Key & ACL - Test Script
# Tests authentication and access control

set -u

echo "=== Scene 2: API Key Authentication & ACL Testing ==="
echo ""

if [ -z "${KONNECT_TOKEN:-}" ]; then
  echo "ERROR: KONNECT_TOKEN environment variable not set"
  exit 1
fi

# Proxy URL(KONNECT_ADDR) does not expose Admin API paths like /consumers.
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

# Konnect core-entities API requires consumer UUID (not username) in nested paths.
get_consumer_id() {
  local username="$1"
  local consumers_json="$2"

  if command -v jq >/dev/null 2>&1; then
    echo "$consumers_json" | jq -r --arg u "$username" '.data[] | select(.username == $u) | .id // empty' 2>/dev/null || true
  else
    echo "$consumers_json" | grep -A5 "\"username\"[[:space:]]*:[[:space:]]*\"${username}\"" | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[0-9a-f-]+"' | head -1 | grep -Eo '[0-9a-f-]{36}' || true
  fi
}

get_key_auth_key() {
  local consumer_id="$1"
  local result http_code body

  result=$(curl -s -X GET "$KONNECT_ADMIN_ADDR/consumers/${consumer_id}/key-auth" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -w $'\n%{http_code}') || return 1

  http_code=$(echo "$result" | tail -n 1)
  body=$(echo "$result" | sed '$d')

  if [ "$http_code" != "200" ]; then
    echo "ERROR: key-auth lookup failed (HTTP $http_code): $body" >&2
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq -r '.data[0].key // empty' 2>/dev/null || true
  else
    echo "$body" | grep -Eo '"key"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4
  fi
}

echo "Gateway URL: $KONNECT_ADDR"
echo "Admin API:   $KONNECT_ADMIN_ADDR"
echo ""

# Test 1: Verify consumers exist
echo "Test 1: Checking if consumers exist..."
CONSUMERS_RESULT=$(curl -s -X GET "$KONNECT_ADMIN_ADDR/consumers" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to query consumers"
  exit 1
}

CONSUMERS_HTTP_CODE=$(echo "$CONSUMERS_RESULT" | tail -n 1)
CONSUMERS_BODY=$(echo "$CONSUMERS_RESULT" | sed '$d')

if [ "$CONSUMERS_HTTP_CODE" != "200" ]; then
  echo "✗ Consumer lookup failed (HTTP $CONSUMERS_HTTP_CODE)"
  echo "$CONSUMERS_BODY"
  exit 1
fi

MOBILE_CHECK=$(echo "$CONSUMERS_BODY" | grep -c "mobile-app" || true)
WEB_CHECK=$(echo "$CONSUMERS_BODY" | grep -c "web-app" || true)

if [ "$MOBILE_CHECK" -gt 0 ] && [ "$WEB_CHECK" -gt 0 ]; then
  echo "✓ Both consumers found (mobile-app, web-app)"
else
  echo "✗ Consumers not found"
  exit 1
fi

echo ""

# Test 2: Get API keys
echo "Test 2: Retrieving API keys..."
MOBILE_CONSUMER_ID=$(get_consumer_id "mobile-app" "$CONSUMERS_BODY")
WEB_CONSUMER_ID=$(get_consumer_id "web-app" "$CONSUMERS_BODY")

if [ -z "$MOBILE_CONSUMER_ID" ] || [ -z "$WEB_CONSUMER_ID" ]; then
  echo "✗ Failed to resolve consumer UUID from username"
  exit 1
fi

MOBILE_KEY=$(get_key_auth_key "$MOBILE_CONSUMER_ID")
WEB_KEY=$(get_key_auth_key "$WEB_CONSUMER_ID")

if [ -z "$MOBILE_KEY" ] || [ -z "$WEB_KEY" ]; then
  echo "✗ API keys not found in response"
  exit 1
fi

echo "✓ Mobile app key: $MOBILE_KEY"
echo "✓ Web app key: $WEB_KEY"
echo ""

# Test 3: Test without API key (should fail)
echo "Test 3: Request without API key (should fail)..."
RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/payments/status" \
  -H "Host: kustomer.example.com" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to send request through gateway"
  exit 1
}

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
if [ "$HTTP_CODE" == "401" ]; then
  echo "✓ Request blocked (HTTP 401 - Unauthorized)"
else
  echo "✗ Expected 401, got $HTTP_CODE"
  exit 1
fi

echo ""

# Test 4: Test with mobile app key (premium - should succeed)
echo "Test 4: Request with mobile-app key (premium group - should succeed)..."
RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/payments/status" \
  -H "apikey: $MOBILE_KEY" \
  -H "Host: kustomer.example.com" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to send request through gateway"
  exit 1
}

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
if [ "$HTTP_CODE" == "200" ]; then
  echo "✓ Request succeeded (HTTP 200)"
else
  echo "✗ Expected 200, got $HTTP_CODE"
  exit 1
fi

echo ""

# Test 5: Test with web app key (basic - should fail)
echo "Test 5: Request with web-app key (basic group - should fail)..."
RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/payments/status" \
  -H "apikey: $WEB_KEY" \
  -H "Host: kustomer.example.com" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to send request through gateway"
  exit 1
}

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
if [ "$HTTP_CODE" == "403" ]; then
  echo "✓ Request blocked (HTTP 403 - Forbidden)"
else
  echo "✗ Expected 403, got $HTTP_CODE"
  exit 1
fi

echo ""
echo "=== All tests passed! ==="
echo ""
echo "Summary:"
echo "- Requests without API key: BLOCKED (401)"
echo "- Requests with premium key: ALLOWED (200)"
echo "- Requests with basic key: BLOCKED (403)"
