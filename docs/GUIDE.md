# Kong API Gateway Workshop - Walkthrough 

Comprehensive step-by-step instructions for all workshop scenes.

---

## Prerequisites Checklist

Before starting, verify you have:

- [ ] Kong Konnect account with Serverless Gateway in US region
- [ ] Gateway URL and API token from Konnect dashboard
- [ ] `curl` installed: `curl --version`
- [ ] `deck` CLI installed: `deck version`
- [ ] Internet connection to reach httpbin.konghq.com (mock service)

**Quick deck install:**
```bash
# macOS
brew install kong/deck/deck

# Linux
curl https://github.com/Kong/deck/releases/download/v1.28.0/deck_1.28.0_linux_amd64.tar.gz | tar xz

# Windows
# Download from: https://github.com/Kong/deck/releases
```

---

## Environment Setup

Set your Kong Konnect credentials as environment variables:

```bash
# Get these from Kong Konnect dashboard
export KONNECT_ADDR="https://<your-gateway-id>.<region>.gateway.konnect.konghq.com"
export KONNECT_TOKEN="<your-api-token>"
export KONG_PROXY="<serverless-dataplane-proxy>"

# Verify connection
curl -H "Authorization: Bearer $KONNECT_TOKEN" $KONNECT_ADDR/services
```

---

## Scene 1: Services & Routes (30 mins)

**Objective:** Understand Kong's core routing - how Services and Routes work together.

### What You'll Learn
- Create a **Service** (upstream target)
- Create a **Route** (entry point for clients)
- Test traffic flow through Kong

### Architecture
```
Client → Kong Route → Kong Service → Backend (httpbin.konghq.com)
```

### Step-by-Step

#### 1.1 Review Configuration
```bash
cd scene-1-services-routes
cat config.yaml
```

This defines:
- Service named `httpbin-service` pointing to `https://httpbin.konghq.com`
- Route named `json-route` matching path `/anything*`

#### 1.2 Deploy Configuration
```bash
deck sync -s config.yaml
```

Output: Configuration applied to your Kong Serverless Gateway

#### 1.3 Verify Service
```bash
curl -X GET "$KONNECT_ADDR/services" \
  -H "Authorization: Bearer $KONNECT_TOKEN"
```

Look for `httpbin-service` in response.

#### 1.4 Verify Routes
```bash
curl -X GET "$KONNECT_ADDR/routes" \
  -H "Authorization: Bearer $KONNECT_TOKEN"
```

Look for `json-route` with path `/anything*`.

#### 1.5 Test Routing
```bash
# Send request through Kong
curl -X GET "$KONG_PROXY/anything/test" \
  -H "Host: kaokaopay.example.com"
```

Expected: Returns JSON response from httpbin showing your request details.

#### 1.6 Monitor Traffic
1. Go to Kong Konnect dashboard
2. Select your Serverless Gateway
3. Navigate to **Analytics** section
4. You should see 1 request recorded

### Key Concepts
- **Service:** Represents your upstream API/backend
- **Route:** Frontend entry point; directs traffic to a Service
- **Host Header:** Used by Kong to match incoming requests to routes

---

## Scene 2: API Key & ACL (40 mins)

**Objective:** Secure APIs using credentials and access control lists.

### What You'll Learn
- Create **Consumers** (API users/clients)
- Generate **API Key** credentials
- Organize Consumers in **Consumer Groups**
- Use **ACL plugin** to restrict route access

### Architecture
```
Client (API Key) → Kong (API Key Auth) → ACL Check → Route → Service
```

### Step-by-Step

#### 2.1 Review Configuration
```bash
cd scene-2-api-key-acl
cat config.yaml
```

This defines:
- Service `payment-service`
- Route `payment-route` with API Key authentication
- Consumers: `mobile-app`, `web-app`
- Consumer Groups: `premium`, `basic`
- ACL plugin restricting access to `premium` group

#### 2.2 Deploy Configuration
```bash
deck sync -s config.yaml
```

#### 2.3 Get Consumer Details
List all consumers:
```bash
curl -X GET "$KONNECT_ADDR/consumers" \
  -H "Authorization: Bearer $KONNECT_TOKEN"
```

#### 2.4 Get API Key Credentials
Retrieve API key for `mobile-app` consumer:
```bash
curl -X GET "$KONNECT_ADDR/consumers/mobile-app/key-auth" \
  -H "Authorization: Bearer $KONNECT_TOKEN"
```

Look for `key` value in response. Save it:
```bash
export MOBILE_API_KEY="<key-value>"
```

#### 2.5 Test Access - With Valid Key (Premium Group)
```bash
curl -X GET "$KONG_PROXY/payments/status" \
  -H "apikey: $MOBILE_API_KEY" \
  -H "Host: kaokaopay.example.com"
```

Expected: Success (200 OK) - mobile-app is in premium group

#### 2.6 Test Access - Without Key (Should Fail)
```bash
curl -X GET "$KONG_PROXY/payments/status" \
  -H "Host: kaokaopay.example.com"
```

Expected: 401 Unauthorized - API key required

#### 2.7 Get Key for `web-app` Consumer
```bash
curl -X GET "$KONNECT_ADDR/consumers/web-app/key-auth" \
  -H "Authorization: Bearer $KONNECT_TOKEN"
```

Save key:
```bash
export WEB_API_KEY="<key-value>"
```

#### 2.8 Test Access - With Basic Group Key (Should Fail)
```bash
curl -X GET "$KONG_PROXY/payments/status" \
  -H "apikey: $WEB_API_KEY" \
  -H "Host: kaokaopay.example.com"
```

Expected: 403 Forbidden - web-app is in basic group, route requires premium

### Key Concepts
- **Consumer:** Represents end user, app, or service
- **API Key:** Simple credential (key:value pair)
- **Consumer Group:** Organizes consumers for bulk ACL management
- **ACL Plugin:** Restricts route access to specific consumer groups

---

## Scene 3: Traffic Management (40 mins)

**Objective:** Control API traffic flow and enable safe rollouts.

### What You'll Learn
- Implement **Rate Limiting** to prevent abuse
- Configure **Canary Release** for gradual traffic migration
- Monitor traffic distribution

### Architecture - Rate Limiting
```
Client → Kong (Rate Limiting Plugin) → Service
         (Enforces quota per minute)
```

### Architecture - Canary Release
```
Client → Kong → 90% traffic → Service v1
              → 10% traffic → Service v2 (new)
```

### Step-by-Step

#### 3.1 Review Configuration
```bash
cd scene-3-traffic-management
cat config.yaml
```

This defines:
- Service `payment-api-v1` and `payment-api-v2`
- Rate Limiting: 10 requests per minute per consumer
- Canary: 10% traffic to v2, 90% to v1

#### 3.2 Deploy Configuration
```bash
deck sync -s config.yaml
```

#### 3.3 Test Rate Limiting
```bash
# Make 12 requests (limit is 10/min)
for i in {1..12}; do
  echo "Request $i:"
  curl -X GET "$KONG_PROXY/api/status" \
    -H "Host: kaokaopay.example.com" \
    -w "\nHTTP Status: %{http_code}\n"
  sleep 1
done
```

Expected: First 10 succeed (200), 11-12 fail with 429 (Too Many Requests)

#### 3.4 Verify Rate Limiting Headers
```bash
curl -X GET "$KONG_PROXY/api/status" \
  -H "Host: kaokaopay.example.com" \
  -v
```

Look for rate-limit headers in response:
```
RateLimit-Remaining: 9
RateLimit-Reset: 1623456789
```

#### 3.5 Test Canary Release
Make multiple requests and observe traffic distribution:
```bash
for i in {1..10}; do
  curl -X GET "$KONG_PROXY/api/version" \
    -H "Host: kaokaopay.example.com" | grep -o '"version":"[^"]*"'
done
```

Expected: ~9 requests to v1, ~1 request to v2

#### 3.6 Monitor in Dashboard
1. Konnect Dashboard → Analytics
2. View request distribution
3. Check for any rate-limited requests (429 status)

### Key Concepts
- **Rate Limiting:** Quota per minute/hour per consumer or globally
- **Canary Release:** Percentage-based traffic split for safe rollouts
- **Headers:** Kong includes rate limit metadata in responses

---

## Scene 4: Request Transformations (30 mins)

**Objective:** Modify incoming requests and outgoing responses.

### What You'll Learn
- Add/remove request headers
- Transform request body
- Add custom response headers
- Use transformation plugins

### Architecture
```
Client → Request Transformer → Service
         (Add headers, modify)
         ↓
         Response Transformer ← Add custom headers
         ↓
         Client Response
```

### Step-by-Step

#### 4.1 Review Configuration
```bash
cd scene-4-transformations
cat config.yaml
```

This defines:
- Service `backend-api`
- Request Transformer: Add `X-Consumer-ID`, `X-Request-ID` headers
- Response Transformer: Add `X-Response-Date` header

#### 4.2 Deploy Configuration
```bash
deck sync -s config.yaml
```

#### 4.3 Test Request Transformation
Make request and inspect headers that Kong added:
```bash
curl -X GET "$KONNECT_ADDR/api/data" \
  -H "Host: kaokaopay.example.com" \
  -v 2>&1 | grep "X-"
```

Expected: Headers like `X-Consumer-ID`, `X-Request-ID`

#### 4.4 Test Response Transformation
```bash
curl -X GET "$KONG_PROXY/api/data" \
  -H "Host: kaokaopay.example.com" \
  -i
```

Look in response headers for `X-Response-Date` (added by response transformer)

#### 4.5 Add Custom Header to Request
Modify `config.yaml` to add more headers:
```yaml
add_headers:
  - X-Custom-Header: kaokaopay-workshop
  - X-API-Version: "1.0"
```

Re-deploy:
```bash
deck sync -s config.yaml
```

Test again to verify new headers.

#### 4.6 Monitor Transformations
Check Kong Analytics for:
- Request volume
- Response times
- Any errors during transformation

### Key Concepts
- **Request Transformer:** Add/remove/modify headers before sending to backend
- **Response Transformer:** Add/remove headers in responses to clients
- **Use Cases:** Add tracking IDs, security headers, versioning info

---

## Testing Summary

All scenes include `test.sh` script with curl commands:

```bash
cd scene-1-services-routes
bash test.sh
```

Run all tests:
```bash
for scene in scene-*/; do
  echo "=== Testing $scene ==="
  cd "$scene"
  bash test.sh
  cd ..
done
```

---

## Troubleshooting

### Cannot connect to Kong gateway
```bash
# Verify URL and token
echo $KONNECT_ADDR
echo $KONNECT_TOKEN

# Test connectivity
curl -H "Authorization: Bearer $KONNECT_TOKEN" \
  "$KONNECT_ADDR/services"
```

### decK sync fails
```bash
# Validate config syntax
deck validate -s config.yaml

# Check for conflicts
deck diff -s config.yaml

# Dry-run before syncing
deck sync -s config.yaml --dry-run
```

### Route not routing traffic
- Verify service exists: `curl $KONNECT_ADDR/services`
- Check route path matches your request
- Confirm Host header matches route definition

### Rate limiting not working
- Verify Rate Limiting plugin is enabled
- Check consumer is correctly identified
- Inspect `RateLimit-Remaining` header

---

## Next Steps

After completing all scenes:

1. **Combine Scenes:** Create a single config with all 4 use cases
2. **Add More Plugins:** Explore CORS, JWT, OAuth2
3. **Production Setup:** Implement monitoring, logging, alerting
4. **Scaling:** Deploy Kong in high-availability configuration

---

**Need Help?** Refer to [Kong Documentation](https://docs.konghq.com)
