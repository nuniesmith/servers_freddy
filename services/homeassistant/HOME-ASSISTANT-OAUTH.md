# Home Assistant OAuth2 Integration with Authentik

Complete guide for integrating Home Assistant with Authentik using OAuth2/OpenID Connect for single sign-on authentication.

## Overview

Home Assistant supports OAuth2 authentication through custom identity providers, enabling SSO with Authentik credentials.

**Features:**
- Single sign-on with Authentik
- Automatic user provisioning
- Multi-factor authentication (via Authentik)
- Group-based access control
- Session management

**Architecture:**
- Home Assistant on FREDDY connects to Authentik OAuth2 provider
- HTTPS connection to auth.7gram.xyz
- Token-based authentication
- Automatic user creation on first login

## Prerequisites

1. **Authentik OAuth2 provider configured**
   - See: `freddy/services/authentik/OIDC-SETUP.md`
   - Provider name: `homeassistant`
   - Client type: Confidential
   - Redirect URIs configured

2. **Home Assistant accessible**
   - URL: https://home.7gram.xyz (or similar)
   - Admin access to configuration.yaml

3. **Network connectivity**
   - Home Assistant can reach auth.7gram.xyz
   - HTTPS connection working

## Setup in Authentik

### Step 1: Create OAuth2 Provider

1. **Login to Authentik**: https://auth.7gram.xyz

2. **Create provider**:
   - Go to: **Applications** → **Providers** → **Create**
   - **Type**: OAuth2/OpenID Provider
   - **Name**: `Home Assistant OAuth2`
   - **Authorization flow**: `default-provider-authorization-implicit-consent`
   - **Client type**: **Confidential**
   - **Client ID**: `homeassistant` (auto-generated or custom)
   - **Client Secret**: (auto-generated - save this!)
   - **Redirect URIs**:
     ```
     https://home.7gram.xyz/auth/external/callback
     ```
   - **Signing Key**: Select auto-generated key
   - **Scopes**: 
     - `openid`
     - `email`
     - `profile`

3. **Save provider**

### Step 2: Create Application

1. **Create application**:
   - Go to: **Applications** → **Applications** → **Create**
   - **Name**: `Home Assistant`
   - **Slug**: `homeassistant`
   - **Provider**: Select `Home Assistant OAuth2` (from Step 1)
   - **Launch URL**: `https://home.7gram.xyz`

2. **Save application**

### Step 3: Note Configuration Details

Save these values for Home Assistant configuration:

```
Client ID: homeassistant
Client Secret: <from-provider-creation>
Authorize URL: https://auth.7gram.xyz/application/o/authorize/
Token URL: https://auth.7gram.xyz/application/o/token/
Userinfo URL: https://auth.7gram.xyz/application/o/userinfo/
```

## Configure Home Assistant

### Step 1: Edit configuration.yaml

Add OAuth2 authentication configuration:

```yaml
# configuration.yaml

# HTTP configuration (if not already present)
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12  # Docker network
    - 100.64.0.0/10  # Tailscale network

# Authentik OAuth2 authentication
auth_providers:
  - type: homeassistant
  - type: command_line
    command: /config/auth_external.sh
    args: ["{{ username }}", "{{ password }}"]
    meta: true

# Alternative: Use trusted networks (optional)
# auth_providers:
#   - type: homeassistant
#   - type: trusted_networks
#     trusted_networks:
#       - 172.16.0.0/12
#       - 100.64.0.0/10
```

**Note**: Home Assistant doesn't have native OAuth2 auth provider. We'll use a workaround with external authentication script.

### Step 2: Create External Auth Script

Home Assistant requires external authentication script for OAuth2:

```bash
# Create auth script
cat > freddy/services/homeassistant/config/auth_external.sh << 'EOF'
#!/bin/bash
# Home Assistant external authentication script for Authentik OAuth2

USERNAME="$1"
PASSWORD="$2"

# Authentik OAuth2 token endpoint
TOKEN_URL="https://auth.7gram.xyz/application/o/token/"
CLIENT_ID="homeassistant"
CLIENT_SECRET="<your-client-secret>"

# Get OAuth2 token
RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET")

# Check if token received
if echo "$RESPONSE" | grep -q "access_token"; then
  # Extract user info
  ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
  
  # Get user info from Authentik
  USER_INFO=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://auth.7gram.xyz/application/o/userinfo/")
  
  # Output user info for Home Assistant
  echo "$USER_INFO" | jq '{
    username: .preferred_username,
    name: .name,
    is_admin: false
  }'
  
  exit 0
else
  exit 1
fi
EOF

# Make executable
chmod +x freddy/services/homeassistant/config/auth_external.sh
```

### Step 3: Install Dependencies

Ensure `curl` and `jq` available in Home Assistant container:

```bash
# If using Home Assistant Container
docker compose exec homeassistant apk add --no-cache curl jq

# If using Home Assistant OS/Supervised
# Install via Add-on or SSH access
```

### Step 4: Restart Home Assistant

```bash
# Restart Home Assistant to load new auth config
docker compose restart homeassistant

# Check logs for errors
docker compose logs homeassistant | grep -i auth
```

## Alternative: Home Assistant Cloud Auth

Home Assistant natively supports trusted headers for OAuth2 via reverse proxy.

### Option 1: Use Authentik Forward Auth

Configure nginx to handle OAuth2 authentication:

```nginx
# freddy/services/nginx/conf.d/homeassistant.conf

server {
    listen 443 ssl http2;
    server_name home.7gram.xyz;

    ssl_certificate /opt/ssl/7gram.xyz/fullchain.pem;
    ssl_certificate_key /opt/ssl/7gram.xyz/privkey.pem;

    # Authentik forward auth
    include /etc/nginx/conf.d/authentik-authrequest.conf;

    location / {
        # Pass auth headers to Home Assistant
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-User $authentik_username;
        proxy_set_header X-Forwarded-Email $authentik_email;
        
        # Proxy to Home Assistant
        proxy_pass http://homeassistant:8123;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # WebSocket support
        proxy_http_version 1.1;
    }

    # Redirect HTTP to HTTPS
    listen 80;
    if ($scheme = http) {
        return 301 https://$server_name$request_uri;
    }
}
```

Then configure Home Assistant to trust forwarded auth:

```yaml
# configuration.yaml

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
  ip_ban_enabled: true
  login_attempts_threshold: 5

# Use trusted networks auth
auth_providers:
  - type: homeassistant
  - type: trusted_networks
    trusted_networks:
      - 172.16.0.0/12  # Docker network
    trusted_users:
      172.16.0.1:
        - <user-id-from-home-assistant>
    allow_bypass_login: true
```

### Option 2: Use Home Assistant Auth Header Provider

Use community integration for header-based auth:

1. **Install HACS** (Home Assistant Community Store):
   - Follow: https://hacs.xyz/docs/setup/download

2. **Install Header Auth integration**:
   - HACS → Integrations → Search "Header Auth"
   - Install and restart

3. **Configure header auth**:
   ```yaml
   # configuration.yaml
   
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 172.16.0.0/12
   
   # Header authentication
   auth_header:
     username_header: X-Forwarded-User
     email_header: X-Forwarded-Email
   ```

## User Management

### Automatic User Creation

When user logs in via OAuth2:
1. Authentik validates credentials
2. Returns user info to Home Assistant
3. Home Assistant creates local user (if not exists)
4. User granted access based on group membership

### Grant Admin Privileges

Admin privileges managed in Home Assistant:

1. **Via Web UI**:
   - Go to: **Settings** → **People** → **Users**
   - Click user
   - Enable: **Administrator**

2. **Via CLI**:
   ```bash
   # Grant admin to user
   docker compose exec homeassistant ha auth list
   docker compose exec homeassistant ha auth set <user-id> --admin
   ```

### Group-Based Access

Control access via Authentik groups:

1. **Create group in Authentik**: `homeassistant-users`
2. **Add users to group**
3. **Configure Authentik provider**:
   - Edit provider
   - Advanced settings → **Require group**: `homeassistant-users`
4. Only users in group can authenticate

## Testing

### Test OAuth2 Flow

1. **Logout of Home Assistant**

2. **Access**: https://home.7gram.xyz

3. **Should redirect to Authentik login**

4. **Enter Authentik credentials**

5. **Should redirect back to Home Assistant**

6. **Verify logged in**

### Test API Access

OAuth2 doesn't affect Home Assistant API tokens:

```bash
# Create long-lived access token in Home Assistant
# Settings → Profile → Long-Lived Access Tokens

# Test API
curl -H "Authorization: Bearer <token>" \
  https://home.7gram.xyz/api/
```

### Verify User Created

```bash
# List users
docker compose exec homeassistant ha auth list

# Check user details
docker compose exec homeassistant ha auth info <user-id>
```

## Troubleshooting

### OAuth2 Redirect Loop

**Symptom**: Browser stuck redirecting between Home Assistant and Authentik

**Solutions**:
- Verify redirect URI exact match: `https://home.7gram.xyz/auth/external/callback`
- Check external_url in Home Assistant: `http.external_url: https://home.7gram.xyz`
- Clear browser cookies
- Check nginx proxy headers

### Invalid Client Error

**Symptom**: "Invalid client_id or client_secret"

**Solutions**:
- Verify client_id matches Authentik provider
- Verify client_secret correct (no extra spaces)
- Check provider type is Confidential
- Regenerate client_secret if needed

### User Not Created

**Symptom**: Login succeeds but user not created in Home Assistant

**Check**:
- Home Assistant logs: `docker compose logs homeassistant | grep -i auth`
- Auth script executing correctly
- User info returned from Authentik

**Solutions**:
- Enable Home Assistant debug logging
- Test auth script manually
- Verify required claims in OAuth2 response

### Network Connectivity Issues

**Symptom**: Can't reach Authentik from Home Assistant

**Diagnosis**:
```bash
# Test from Home Assistant container
docker compose exec homeassistant ping auth.7gram.xyz
docker compose exec homeassistant curl -I https://auth.7gram.xyz
```

**Solutions**:
- Check DNS resolution
- Verify firewall rules
- Ensure Docker network connectivity
- Check Tailscale if using cross-server

## Security Considerations

### HTTPS Required

OAuth2 requires HTTPS:
- Never use HTTP for OAuth2 endpoints
- Use valid SSL certificates
- Enable HSTS in nginx

### Client Secret Protection

Protect client_secret:
- Never commit to git
- Store in environment variables
- Rotate periodically
- Use Docker secrets or similar

### Token Expiration

Configure token lifetimes in Authentik:
- Access token: 1 hour (default)
- Refresh token: 30 days
- ID token: 1 hour

### Session Management

Home Assistant sessions:
- Default: 30 days
- Configure via: `http.session_lifetime`
- Users must re-authenticate after expiration

## Recommended Configuration

**Best setup for Home Assistant + Authentik**:

1. **Use Authentik forward auth** (Option 1)
   - Nginx handles OAuth2
   - Home Assistant trusts forwarded headers
   - Simplest setup

2. **Pros**:
   - No Home Assistant configuration changes
   - Centralized auth at nginx
   - Works with mobile app via same mechanism

3. **Implementation**:
   - Configure nginx with Authentik forward auth
   - Set trusted_proxies in Home Assistant
   - Enable X-Forwarded headers

## Quick Reference

### Authentik Provider Configuration

```
Provider Type: OAuth2/OpenID
Client Type: Confidential
Client ID: homeassistant
Redirect URI: https://home.7gram.xyz/auth/external/callback
Scopes: openid, email, profile
```

### Home Assistant Endpoints

```
Login: https://home.7gram.xyz/auth/login
Callback: https://home.7gram.xyz/auth/external/callback
API: https://home.7gram.xyz/api/
```

### Testing Checklist

- [ ] Authentik provider created
- [ ] Application created in Authentik
- [ ] Redirect URI matches exactly
- [ ] Home Assistant auth script configured
- [ ] Dependencies installed (curl, jq)
- [ ] Test user can login via OAuth2
- [ ] User created in Home Assistant
- [ ] Admin privileges granted (if needed)
- [ ] API access still works
- [ ] No errors in logs

---

**Document Version**: 1.0  
**Last Updated**: October 20, 2025  
**Status**: Ready for deployment  
**Related**: `freddy/services/authentik/OIDC-SETUP.md`, `PORTAINER-OAUTH.md`

**Note**: Home Assistant native OAuth2 support is limited. Forward auth via nginx recommended for production use.
