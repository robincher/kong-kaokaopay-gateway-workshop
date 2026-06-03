# Scene 1: Services & Routes

Learn Kong's fundamental routing concepts: Services and Routes.

## Overview

A **Service** represents your backend API. A **Route** is how clients access that service through Kong. Traffic flows: Client → Route → Service → Backend.

## What You'll Deploy

- **Service:** `httpbin-service` pointing to https://httpbin.konghq.com
- **Route:** `json-route` accepting requests on path `/anything*`
- **Host:** kaokaopay.example.com

## Quick Start

```bash
# Deploy configuration
deck sync -s config.yaml

# Test the route
bash test.sh
```

## Configuration Details

### Service
```yaml
httpbin-service:
  host: httpbin.konghq.com
  port: 443
  protocol: https
```

### Route
```yaml
json-route:
  paths: ["/anything"]
  strip_path: true
  service: httpbin-service
```

## Testing

**Manual test:**
```bash
curl -X GET "https://<gateway-url>/anything/test" \
  -H "Host: kaokaopay.example.com"
```

**Expected response:** JSON showing your request details from httpbin

## Key Concepts

- **Service:** Target backend/upstream API
- **Route:** Frontend entry point matching paths/hosts
- **strip_path:** Removes matched path before forwarding to backend
- **Host Header:** Kong matches routes using host headers

## Verification

Check in Kong Konnect dashboard:
1. Services section → See `httpbin-service`
2. Routes section → See `json-route` with path `/anything`
3. Analytics → View incoming requests

---

**Next:** Move to Scene 2 for API authentication with Consumer Groups
