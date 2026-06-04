# Scene 2: API Key Authentication & Consumer Groups (ACL)

Secure APIs using credentials and access control with Consumer Groups.

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│                      KONG GATEWAY                           │
│                                                              │
│  ┌─────────────────┐  ┌──────────────┐  ┌─────────────┐   │
│  │ REQUEST + KEY   │  │ KEY AUTH     │  │   ACL       │   │
│  │ apikey: xxxx    │→ │ Validate Key │→ │ Check Group │   │
│  └─────────────────┘  └──────────────┘  └──────┬──────┘   │
│                                                  │           │
│                                      ┌───────────┴────────┐ │
│                                      │                    │ │
│                            ┌─────────▼─────┐   ┌─────────▼──┐
│                            │  PREMIUM      │   │   BASIC    │
│                            │  ✓ ALLOWED    │   │   ✗ DENIED │
│                            │  mobile-app   │   │  web-app   │
│                            └─────────┬─────┘   └────────────┘
│                                      │
│                            ┌─────────▼────────┐
│                            │   SERVICE        │
│                            │ payment-service  │
│                            └──────────────────┘
└────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS
                              │
                    ┌─────────▼──────────────┐
                    │  BACKEND               │
                    │  httpbin.konghq.com    │
                    └────────────────────────┘
```

## What You'll Do

In this scene, you'll:
- **Create** two Consumers: `mobile-app` (premium) and `web-app` (basic)
- **Generate** unique API Keys for each consumer
- **Assign** consumers to Consumer Groups (premium/basic)
- **Configure** ACL plugin to restrict payment route to premium group only
- **Test** access control: ✓ Premium access allowed, ✗ Basic access denied

## Overview

Implement API security through:
- **Consumers:** Represent API users/apps (mobile-app, web-app)
- **API Keys:** Simple credentials for each consumer
- **Consumer Groups:** Organize consumers for access control
- **ACL Plugin:** Restrict routes to specific groups

## What You'll Deploy

- **Service:** `payment-service` (mock payment API)
- **Route:** `payment-route` with API Key authentication
- **Consumers:** `mobile-app` (premium), `web-app` (basic)
- **Consumer Groups:** `premium`, `basic`
- **ACL Plugin:** Restrict payment route to `premium` group

## Access Control Matrix

| Consumer | Group | Can access /payments? |
|----------|-------|----------------------|
| mobile-app | premium | ✓ Yes |
| web-app | basic | ✗ No |

## Quick Start

```bash
# Deploy configuration
deck sync -s config.yaml

# Get API keys and test access
bash test.sh
```

## Configuration Details

### Consumers & API Keys
```yaml
consumers:
  - username: mobile-app
    keyauth_credentials:
      - key: mobile-key-12345
    groups:
      - premium
      
  - username: web-app
    keyauth_credentials:
      - key: web-key-67890
    groups:
      - basic
```

### ACL Plugin (restricts to premium group)
```yaml
plugins:
  - name: acl
    config:
      allow:
        - premium
```

## Testing

**Get API key:**
```bash
curl -s -X GET "https://<gateway-url>/consumers/mobile-app/key-auth" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | jq '.data[0].key'
```

**Test with valid key (premium):**
```bash
curl -X GET "https://<gateway-url>/payments/status" \
  -H "apikey: mobile-key-12345" \
  -H "Host: kaokaopay.example.com"
# Expected: 200 OK
```

**Test with basic key (should fail):**
```bash
curl -X GET "https://<gateway-url>/payments/status" \
  -H "apikey: web-key-67890" \
  -H "Host: kaokaopay.example.com"
# Expected: 403 Forbidden
```

**Test without key (should fail):**
```bash
curl -X GET "https://<gateway-url>/payments/status" \
  -H "Host: kaokaopay.example.com"
# Expected: 401 Unauthorized
```

## Key Concepts

- **Consumer:** End-user, application, or service using the API
- **API Key (key-auth):** Simple credential consisting of a key value
- **Consumer Group:** Groups related consumers for bulk ACL management
- **ACL Plugin:** Allow/deny routes based on consumer group membership
- **Credentials:** Stored with the consumer; matched on each request

## Real-World Use Cases

1. **Mobile App vs Web App:** Different rate limits or features
2. **Partner Access:** External developers in separate groups
3. **Internal Tools:** Separate group with full access
4. **Feature Flags:** Route access by consumer group

## Verification

Check in Kong Konnect dashboard:
1. Consumers section → See `mobile-app` and `web-app`
2. Consumer Groups section → See `premium` and `basic`
3. Routes section → See `payment-route` with API Key plugin
4. Analytics → View authenticated requests

---

**Next:** Move to Scene 3 for traffic management and rate limiting
