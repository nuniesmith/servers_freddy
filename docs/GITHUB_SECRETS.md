# GitHub Secrets Configuration

This document lists all the GitHub secrets required for the CI/CD workflow to deploy and manage the Freddy server.

## Required Secrets

### Infrastructure Secrets

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `FREDDY_TAILSCALE_IP` | Tailscale IP address of the Freddy server | `100.87.125.19` |
| `SULLIVAN_TAILSCALE_IP` | Tailscale IP address of the Sullivan server (for proxying) | `100.87.125.20` |
| `SSH_PORT` | SSH port for Freddy server | `22` |
| `SSH_USER` | SSH username for deployment | `actions` |
| `SSH_KEY` | Private SSH key for authentication | `-----BEGIN OPENSSH PRIVATE KEY-----...` |

### Tailscale Authentication

| Secret Name | Description |
|-------------|-------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth client ID for VPN connection |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth secret for VPN connection |

### DNS & SSL Configuration

| Secret Name | Description |
|-------------|-------------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token with DNS edit permissions |
| `CLOUDFLARE_ZONE_ID` | Cloudflare zone ID for 7gram.xyz |
| `SSL_EMAIL` | Email address for Let's Encrypt certificate notifications |

### Application Secrets

#### PhotoPrism

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `PHOTOPRISM_ADMIN_PASSWORD` | Admin password for PhotoPrism web interface | `SecurePassword123!` |
| `PHOTOPRISM_DB_PASSWORD` | PostgreSQL database password for PhotoPrism | `RandomDBPassword456` |

#### Nextcloud

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `NEXTCLOUD_DB_PASSWORD` | PostgreSQL database password for Nextcloud | `RandomDBPassword789` |
| `NEXTCLOUD_ADMIN_USER` | Admin username for Nextcloud | `admin` |
| `NEXTCLOUD_ADMIN_PASSWORD` | Admin password for Nextcloud web interface | `SecurePassword321!` |

### Optional Secrets

| Secret Name | Description | Default Value |
|-------------|-------------|---------------|
| `TZ` | Timezone for all containers | `America/Toronto` |
| `PUID` | User ID for file permissions | `1000` |
| `PGID` | Group ID for file permissions | `1000` |
| `MEDIA_PATH_AUDIOBOOKS` | Path to audiobooks on the server | `/media/audiobooks` |
| `DISCORD_WEBHOOK_ACTIONS` | Discord webhook URL for deployment notifications | _(none)_ |

## Setting Up Secrets

### Via GitHub Web Interface

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Enter the secret name and value
5. Click **Add secret**

### Via GitHub CLI

```bash
# Example: Set a secret using gh CLI
gh secret set NEXTCLOUD_DB_PASSWORD --body "your-secure-password"

# Set a secret from a file (useful for SSH keys)
gh secret set SSH_KEY < ~/.ssh/id_rsa
```

### Generating Secure Passwords

Use these commands to generate secure random passwords:

```bash
# Generate a 32-character password
openssl rand -base64 32

# Generate a 24-character alphanumeric password
LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24 && echo
```

## Security Best Practices

1. **Never commit secrets to the repository** - Always use GitHub Secrets
2. **Use strong passwords** - Minimum 20 characters, mix of letters, numbers, and symbols
3. **Rotate passwords regularly** - Especially for database passwords
4. **Unique passwords** - Use different passwords for each service
5. **Limit secret access** - Only necessary team members should have access
6. **Monitor secret usage** - Review GitHub Actions logs for any suspicious activity

## Automated .env Generation

The CI/CD workflow automatically generates the `.env` file on the server from these GitHub secrets. You do not need to manually create or maintain the `.env` file.

### How It Works

1. During deployment, the workflow checks if `.env` exists on the server
2. If it doesn't exist, a new one is created from GitHub secrets
3. If it exists, a backup is created (`.env.backup.<timestamp>`) before updating
4. The new `.env` is generated with proper permissions (600)
5. Docker Compose uses the `.env` file to configure all services

## Troubleshooting

### Missing Secrets Error

If you see an error like `secret.NEXTCLOUD_DB_PASSWORD is empty`, you need to add the secret to your repository.

### Database Authentication Failures

If Nextcloud or PhotoPrism fail to connect to their databases:

1. Check that the `*_DB_PASSWORD` secrets match what's in the database
2. Use the `reset_nextcloud_db` workflow input to reset the Nextcloud database
3. For PhotoPrism, you may need to manually reset the database volume

### SSH Connection Failures

If the workflow fails to connect via SSH:

1. Verify `SSH_KEY` is a valid private key (not the public key)
2. Check that `SSH_PORT` is correct (default is 22)
3. Ensure `SSH_USER` has appropriate permissions on the server
4. Verify the SSH key is authorized in `~/.ssh/authorized_keys` on the server

## Example Secret Setup Script

```bash
#!/bin/bash
# setup-secrets.sh - Helper script to set all required secrets

# Infrastructure
gh secret set FREDDY_TAILSCALE_IP --body "100.87.125.19"
gh secret set SULLIVAN_TAILSCALE_IP --body "100.87.125.20"
gh secret set SSH_PORT --body "22"
gh secret set SSH_USER --body "actions"
gh secret set SSH_KEY < ~/.ssh/freddy_deploy_key

# Tailscale
gh secret set TAILSCALE_OAUTH_CLIENT_ID --body "your-oauth-client-id"
gh secret set TAILSCALE_OAUTH_SECRET --body "your-oauth-secret"

# Cloudflare
gh secret set CLOUDFLARE_API_TOKEN --body "your-cloudflare-token"
gh secret set CLOUDFLARE_ZONE_ID --body "your-zone-id"
gh secret set SSL_EMAIL --body "admin@example.com"

# Application passwords (generate secure ones)
gh secret set PHOTOPRISM_ADMIN_PASSWORD --body "$(openssl rand -base64 32)"
gh secret set PHOTOPRISM_DB_PASSWORD --body "$(openssl rand -base64 32)"
gh secret set NEXTCLOUD_DB_PASSWORD --body "$(openssl rand -base64 32)"
gh secret set NEXTCLOUD_ADMIN_USER --body "admin"
gh secret set NEXTCLOUD_ADMIN_PASSWORD --body "$(openssl rand -base64 32)"

echo "✅ All secrets configured!"
echo "⚠️  Save the generated passwords securely!"
```

## Related Documentation

- [Deployment Notes](../DEPLOYMENT_NOTES.md)
- [Nextcloud Database Fix](./NEXTCLOUD_DB_FIX.md)
- [Post-Deploy Checklist](./POST_DEPLOY_CHECK.md)