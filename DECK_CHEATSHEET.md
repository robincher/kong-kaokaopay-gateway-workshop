# decK Command Cheatsheet

Quick reference for modern decK commands (v1.40+) used in this workshop.

## Installation

**Recommended: macOS with Homebrew**
```bash
brew install kong/deck/deck
deck version  # Verify installation
```

**Linux / Manual Installation**
- Download from: https://github.com/Kong/deck/releases
- Latest version: **1.62.1**

## Essential Commands

### Deploy Configuration
```bash
# Sync config file with Kong Gateway
deck gateway sync config.yaml

# Preview changes before applying (recommended!)
deck gateway diff config.yaml
```

### Backup & Export
```bash
# Export current gateway state
deck gateway dump -o backup.yaml

# Check current version and connection
deck gateway ping
```

### Validate
```bash
# Validate configuration syntax
deck gateway validate config.yaml

# Check for conflicts
deck gateway diff config.yaml
```

## Advanced Commands

### File Manipulation
```bash
# Convert OpenAPI spec to Kong config
deck file openapi2kong -s api-spec.yaml -o kong-config.yaml

# Merge multiple config files
deck file merge services.yaml routes.yaml -o merged.yaml
```

### Troubleshooting
```bash
# Sync with detailed output
deck gateway sync config.yaml --verbose 1

# Check what endpoints decK is calling
deck gateway diff config.yaml --verbose 1

# Generate shell completion
deck completion bash  # or zsh, fish, powershell
```

## Workflow Example

```bash
# 1. Backup existing configuration
deck gateway dump -o backup.yaml

# 2. Create or modify config.yaml
vim config.yaml

# 3. Validate syntax
deck gateway validate config.yaml

# 4. Preview changes
deck gateway diff config.yaml

# 5. Apply configuration
deck gateway sync config.yaml

# 6. Verify in Kong Konnect dashboard
# Check Analytics section for traffic
```

## Common Use Cases

### Initialize a new route
```yaml
# config.yaml
services:
  - name: my-service
    host: example.com
    port: 443
    protocol: https

routes:
  - name: my-route
    service: my-service
    paths:
      - /api/v1
```

Deploy with:
```bash
deck gateway sync config.yaml
```

### Add authentication to a route
```yaml
routes:
  - name: secure-route
    service: my-service
    paths:
      - /api/secure
    plugins:
      - name: key-auth
```

### Rate limit a route
```yaml
plugins:
  - name: rate-limiting
    route: my-route
    config:
      minute: 100
```

## Version Comparison

### Old Commands (decK < v1.40)
```bash
deck sync -s config.yaml
deck dump
deck validate -s config.yaml
deck diff -s config.yaml
```

### New Commands (decK >= v1.40)
```bash
deck gateway sync config.yaml
deck gateway dump -o kong.yaml
deck gateway validate config.yaml
deck gateway diff config.yaml
```

**Note:** All examples in this workshop use modern commands (v1.40+)

## Best Practices

✅ **DO:**
- Always run `deck gateway diff` before `deck gateway sync`
- Keep `config.yaml` in version control (Git)
- Use `deck gateway dump` for backups
- Test in staging before production
- Use meaningful config file names

❌ **DON'T:**
- Run multiple decK processes simultaneously
- Skip validation before syncing
- Ignore diff output
- Run decK without checking connection first

## Resources

- **Kong Documentation:** https://developer.konghq.com/deck/
- **decK GitHub:** https://github.com/Kong/deck
- **Releases:** https://github.com/Kong/deck/releases
- **Getting Started:** https://developer.konghq.com/deck/get-started/

## Workshop Commands Quick Reference

```bash
# Scene 1: Services & Routes
deck gateway sync scene-1-services-routes/config.yaml
bash scene-1-services-routes/test.sh

# Scene 2: API Key & ACL
deck gateway sync scene-2-api-key-acl/config.yaml
bash scene-2-api-key-acl/test.sh

# Scene 3: Traffic Management
deck gateway sync scene-3-traffic-management/config.yaml
bash scene-3-traffic-management/test.sh

# Scene 4: Request Transformations
deck gateway sync scene-4-transformations/config.yaml
bash scene-4-transformations/test.sh
```

---

**For detailed information**, refer to the [Kong decK Documentation](https://developer.konghq.com/deck/).
