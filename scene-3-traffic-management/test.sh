#!/bin/bash

# Scene 3: Traffic Management - Test Script
# Tests rate limiting and canary release

set -u

echo "=== Scene 3: Traffic Management (Rate Limiting & Canary) Testing ==="
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
echo "Test 1: Checking if route 'api-route' exists..."
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

ROUTE_CHECK=$(echo "$ROUTE_BODY" | grep -c "api-route" || true)

if [ "$ROUTE_CHECK" -gt 0 ]; then
  echo "✓ Route api-route found"
else
  echo "✗ Route api-route not found"
  exit 1
fi

echo ""

# Test 2: Verify services and upstream exist
echo "Test 2: Checking services and upstream..."
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

V1_CHECK=$(echo "$SERVICE_BODY" | grep -c "payment-api-v1" || true)
V2_CHECK=$(echo "$SERVICE_BODY" | grep -c "payment-api-v2" || true)

UPSTREAM_RESULT=$(curl -s -X GET "$KONNECT_ADMIN_ADDR/upstreams" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to query upstreams"
  exit 1
}

UPSTREAM_HTTP_CODE=$(echo "$UPSTREAM_RESULT" | tail -n 1)
UPSTREAM_BODY=$(echo "$UPSTREAM_RESULT" | sed '$d')

if [ "$UPSTREAM_HTTP_CODE" != "200" ]; then
  echo "✗ Upstream lookup failed (HTTP $UPSTREAM_HTTP_CODE)"
  echo "$UPSTREAM_BODY"
  exit 1
fi

UPSTREAM_CHECK=$(echo "$UPSTREAM_BODY" | grep -c "api-backend" || true)

if [ "$V1_CHECK" -gt 0 ] && [ "$V2_CHECK" -gt 0 ] && [ "$UPSTREAM_CHECK" -gt 0 ]; then
  echo "✓ Services found (payment-api-v1, payment-api-v2)"
  echo "✓ Upstream api-backend found"
else
  echo "✗ Services or upstream not found"
  exit 1
fi

echo ""

# Load rate-limiting plugin state (canary runs before rate-limit tests to avoid 429)
PLUGIN_RESULT=$(curl -s -X GET "$KONNECT_ADMIN_ADDR/plugins" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -w $'\n%{http_code}') || {
  echo "ERROR: curl failed to query plugins"
  exit 1
}

PLUGIN_HTTP_CODE=$(echo "$PLUGIN_RESULT" | tail -n 1)
PLUGIN_BODY=$(echo "$PLUGIN_RESULT" | sed '$d')

RATE_LIMIT_ENABLED=true
RATE_LIMIT_MINUTE=60
CANARY_REQUESTS=50

if [ "$PLUGIN_HTTP_CODE" = "200" ]; then
  if command -v jq >/dev/null 2>&1; then
    if [ "$(echo "$PLUGIN_BODY" | jq -r '[.data[] | select(.name == "rate-limiting")] | length' 2>/dev/null || echo 0)" = "0" ]; then
      RATE_LIMIT_ENABLED=false
    else
      RATE_LIMIT_ENABLED=$(echo "$PLUGIN_BODY" | jq -r '
        [.data[] | select(.name == "rate-limiting")][0] |
        if .enabled == false then "false" else "true" end
      ' 2>/dev/null || echo true)
      RATE_LIMIT_MINUTE=$(echo "$PLUGIN_BODY" | jq -r '
        [.data[] | select(.name == "rate-limiting")][0].config.minute // 60
      ' 2>/dev/null || echo 60)
    fi
  elif echo "$PLUGIN_BODY" | grep -q '"name"[[:space:]]*:[[:space:]]*"rate-limiting"'; then
    if echo "$PLUGIN_BODY" | grep -A20 '"name"[[:space:]]*:[[:space:]]*"rate-limiting"' | grep -q '"enabled"[[:space:]]*:[[:space:]]*false'; then
      RATE_LIMIT_ENABLED=false
    fi
    PARSED_MINUTE=$(echo "$PLUGIN_BODY" | grep -A30 '"name"[[:space:]]*:[[:space:]]*"rate-limiting"' | grep -Eo '"minute"[[:space:]]*:[[:space:]]*[0-9]+' | head -1 | grep -Eo '[0-9]+' || true)
    if [ -n "$PARSED_MINUTE" ]; then
      RATE_LIMIT_MINUTE="$PARSED_MINUTE"
    fi
  else
    RATE_LIMIT_ENABLED=false
  fi
fi

if [ "$RATE_LIMIT_ENABLED" = true ] && [ "$RATE_LIMIT_MINUTE" -lt "$CANARY_REQUESTS" ]; then
  echo "ERROR: rate-limiting minute=$RATE_LIMIT_MINUTE is below canary sample size ($CANARY_REQUESTS)"
  echo "Set config.yaml minute >= $CANARY_REQUESTS (or disable the plugin) and run: deck gateway sync config.yaml"
  exit 1
fi

# Test 3: Canary first while quota is available
echo "Test 3: Testing canary release (90% v1, 10% v2)..."
echo "Sending $CANARY_REQUESTS requests to GET /api (service path should be /headers)..."
if [ "$RATE_LIMIT_ENABLED" = true ]; then
  echo "Rate limit: $RATE_LIMIT_MINUTE/min (canary runs before rate-limit burst)"
fi
echo ""

V1_COUNT=0
V2_COUNT=0
UNKNOWN_COUNT=0
RATE_LIMITED_COUNT=0

for i in $(seq 1 "$CANARY_REQUESTS"); do
  RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/api" \
    -H "Host: kustomer.example.com" \
    -w "\n%{http_code}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [ "$HTTP_CODE" = "429" ] || echo "$BODY" | grep -q "API rate limit exceeded"; then
    RATE_LIMITED_COUNT=$((RATE_LIMITED_COUNT + 1))
    echo "Request $i: × 429 Rate Limited"
  elif echo "$BODY" | grep -q 'httpbin.konghq.com'; then
    V1_COUNT=$((V1_COUNT + 1))
    echo "Request $i: v1 (httpbin.konghq.com)"
  elif echo "$BODY" | grep -q 'httpbin.org'; then
    V2_COUNT=$((V2_COUNT + 1))
    echo "Request $i: v2 (httpbin.org)"
  elif echo "$BODY" | grep -q '"slideshow"'; then
    UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    echo "Request $i: ? still on /json path (sync config with path: /headers first)"
  else
    UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    echo "Request $i: unknown (HTTP $HTTP_CODE)"
  fi
done

echo ""
echo "Traffic distribution:"
echo "- v1 (90% target, httpbin.konghq.com): $V1_COUNT requests"
echo "- v2 (10% target, httpbin.org): $V2_COUNT requests"
echo "- rate limited (429): $RATE_LIMITED_COUNT requests"
echo "- unknown: $UNKNOWN_COUNT requests"

if [ "$RATE_LIMITED_COUNT" -gt 0 ]; then
  echo "✗ Canary test hit rate limit; increase minute in config.yaml (>= $CANARY_REQUESTS) and re-sync"
elif [ "$UNKNOWN_COUNT" -gt 0 ]; then
  echo "⚠ Cannot verify weights until service path is /headers (deck gateway sync config.yaml)"
elif [ "$V1_COUNT" -ge 40 ] && [ "$V2_COUNT" -ge 2 ] && [ "$V2_COUNT" -le 12 ]; then
  echo "✓ Canary release distribution appears correct (~90/10)"
elif [ "$V1_COUNT" -ge 20 ] && [ "$V2_COUNT" -ge 20 ]; then
  echo "⚠ ~50/50 split: httpbin.org DNS expands to multiple IPs; lower v2 weight in config.yaml and re-sync"
else
  echo "⚠ Limited samples or unexpected split; try more requests"
fi

echo ""

# Test 4: Rate limiting (after canary; uses remaining quota in the same minute window)
echo "Test 4: Testing rate limiting..."
if [ "$RATE_LIMIT_ENABLED" = false ]; then
  echo "⊘ Rate limiting plugin disabled; skipping limit test"
else
  RATE_LIMIT_BURST=12
  echo "Sending $RATE_LIMIT_BURST requests to GET /api (configured limit: $RATE_LIMIT_MINUTE requests/min)..."
  echo ""

  SUCCESS_COUNT=0
  RATE_LIMITED_COUNT=0

  for i in $(seq 1 "$RATE_LIMIT_BURST"); do
    RESPONSE=$(curl -s -X GET "$KONNECT_ADDR/api" \
      -H "Host: kustomer.example.com" \
      -w "\n%{http_code}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

    if [ "$HTTP_CODE" = "200" ]; then
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      echo "Request $i: ✓ 200 OK"
    elif [ "$HTTP_CODE" = "429" ]; then
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

  if [ "$RATE_LIMITED_COUNT" -gt 0 ]; then
    echo "✓ Rate limiting working correctly"
  else
    echo "✗ Expected at least one 429 after canary test consumed quota"
  fi
fi

echo ""

# Test 5: Rate limit headers
echo "Test 5: Inspecting rate limit headers..."
if [ "$RATE_LIMIT_ENABLED" = false ]; then
  echo "⊘ Rate limiting plugin disabled; skipping header check"
else
  RESPONSE=$(curl -s -i -X GET "$KONNECT_ADDR/api" \
    -H "Host: kustomer.example.com" 2>&1)

  RATE_LIMIT_HEADER=$(echo "$RESPONSE" | grep -i "ratelimit-limit" || true)
  RATE_REMAINING=$(echo "$RESPONSE" | grep -i "ratelimit-remaining" || true)

  if [ -n "$RATE_LIMIT_HEADER" ]; then
    echo "✓ Found rate limit headers:"
    echo "  $RATE_LIMIT_HEADER"
    echo "  $RATE_REMAINING"
  elif echo "$RESPONSE" | grep -q " 429 "; then
    echo "⊘ Quota exhausted after prior tests (HTTP 429); headers not available"
  else
    echo "✗ Rate limit headers not found"
  fi
fi

echo ""
echo "=== All tests completed! ==="
