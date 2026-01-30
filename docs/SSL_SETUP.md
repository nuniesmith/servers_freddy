# SSL Certificate Setup for Freddy Server

This document explains the SSL certificate management system for the Freddy server, including automated Let's Encrypt certificate generation using Cloudflare DNS validation.

## Overview

The Freddy server uses **Let's Encrypt** SSL certificates with **Cloudflare DNS-01 challenge** for wildcard certificate generation. The system is designed to work automatically in CI/CD pipelines while also supporting manual certificate management.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     CI/CD Pipeline                          │
│  (GitHub Actions checks/generates certs before deployment)  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
          ┌──────────────────────┐
          │  /opt/ssl/7gram.xyz  │  ← Host directory with certs
          │  - fullchain.pem     │
          │  - privkey.pem       │
          └──────────┬───────────┘
                     │
                     │ (mounted as volume)
                     ▼
          ┌──────────────────────────┐
          │  nginx Docker Container  │
          │  /etc/letsencrypt-volume │  ← Read-only mount
          └──────────┬───────────────┘
                     │
                     │ (copied at startup)
                     ▼
          ┌──────────────────────┐
          │   /etc/nginx/ssl/    │  ← nginx SSL directory
          │   - fullchain.pem    │
          │   - privkey.pem      │
          └──────────────────────┘
```

## Certificate Types

### 1. Let's Encrypt Production Certificates (Preferred)

- **Valid for:** `7gram.xyz` and `*.7gram.xyz` (wildcard)
- **Lifetime:** 90 days (auto-renewed)
- **Validation:** Cloudflare DNS-01 challenge
- **Trusted:** By all modern browsers
- **Location:** `/opt/ssl/7gram.xyz/`

### 2. Self-Signed Fallback Certificates

- **Used when:** Let's Encrypt certificates unavailable
- **Purpose:** Allow nginx to start and serve traffic
- **Warning:** Browsers will show security warnings
- **Generated:** Automatically by nginx container at startup

## Automated Certificate Management (CI/CD)

### Prerequisites

The following GitHub Secrets must be configured in your repository:

#### Required Secrets

```bash
CLOUDFLARE_EMAIL          # Your Cloudflare account email
CLOUDFLARE_API_KEY        # Cloudflare Global API Key
# OR
CLOUDFLARE_API_TOKEN      # Cloudflare API Token (more secure)

CERTBOT_EMAIL            # Email for Let's Encrypt notifications (optional, defaults to CLOUDFLARE_EMAIL)
```

#### Getting Cloudflare API Credentials

1. **Using Global API Key (Easier)**
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
   - Navigate to: My Profile → API Tokens → Global API Key
   - Click "View" and copy the key
   - Set `CLOUDFLARE_EMAIL` and `CLOUDFLARE_API_KEY` secrets

2. **Using API Token (More Secure)**
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
   - Click "Create Token"
   - Use "Edit zone DNS" template
   - Select your zone (7gram.xyz)
   - Set `CLOUDFLARE_API_TOKEN` secret

### How CI/CD Works

The `.github/workflows/ci-cd.yml` workflow automatically:

1. **Checks existing certificates** on the server
2. **Validates expiry** (renews if < 7 days remaining)
3. **Generates new certificates** if needed using `scripts/ci-ssl-setup.sh`
4. **Copies certificates** to `/opt/ssl/7gram.xyz/`
5. **Deploys services** with the updated certificates

#### CI/CD Workflow Extract

```yaml
- name: Check and Setup SSL Certificates
  run: |
    export CLOUDFLARE_EMAIL="${{ secrets.CLOUDFLARE_EMAIL }}"
    export CLOUDFLARE_API_KEY="${{ secrets.CLOUDFLARE_API_KEY }}"
    export CERTBOT_EMAIL="${{ secrets.CERTBOT_EMAIL }}"
    ./scripts/ci-ssl-setup.sh
```

### The ci-ssl-setup.sh Script

This script handles automated certificate generation:

**Features:**
- ✅ Non-interactive (perfect for CI/CD)
- ✅ Checks if certificates already exist and are valid
- ✅ Skips generation if cert is valid for >7 days
- ✅ Uses Cloudflare DNS-01 challenge for wildcard certs
- ✅ Falls back to self-signed if Let's Encrypt fails
- ✅ Validates certificates after generation

**Usage:**

```bash
# Automated (uses environment variables)
export CLOUDFLARE_EMAIL="your@email.com"
export CLOUDFLARE_API_KEY="your-api-key"
export CERTBOT_EMAIL="your@email.com"
./scripts/ci-ssl-setup.sh

# Check status
./scripts/ci-ssl-setup.sh
```

## Manual Certificate Management

### Using cert-manager.sh

The `scripts/cert-manager.sh` script provides interactive certificate management:

```bash
# Check certificate status
sudo ./scripts/cert-manager.sh check

# Request new Let's Encrypt certificate (interactive)
sudo ./scripts/cert-manager.sh request

# Upgrade from self-signed to Let's Encrypt
sudo ./scripts/cert-manager.sh upgrade

# Manually renew certificates
sudo ./scripts/cert-manager.sh renew

# Test renewal process (dry run)
sudo ./scripts/cert-manager.sh test-renewal

# Generate self-signed certificate
sudo ./scripts/cert-manager.sh self-signed

# Show certificate information
./scripts/cert-manager.sh info
```

### Manual Setup Steps

If you need to set up certificates manually:

1. **Install certbot and Cloudflare plugin:**

   ```bash
   # Fedora/RHEL
   sudo dnf install -y certbot python3-certbot-dns-cloudflare

   # Debian/Ubuntu
   sudo apt-get install -y certbot python3-certbot-dns-cloudflare
   ```

2. **Create Cloudflare credentials file:**

   ```bash
   sudo mkdir -p /etc/letsencrypt
   sudo nano /etc/letsencrypt/cloudflare.ini
   ```

   Add (choose one method):

   ```ini
   # Method 1: Global API Key
   dns_cloudflare_email = your@email.com
   dns_cloudflare_api_key = your-global-api-key

   # Method 2: API Token (recommended)
   dns_cloudflare_api_token = your-api-token
   ```

   Secure the file:

   ```bash
   sudo chmod 600 /etc/letsencrypt/cloudflare.ini
   ```

3. **Request certificate:**

   ```bash
   sudo certbot certonly \
     --dns-cloudflare \
     --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
     --dns-cloudflare-propagation-seconds 60 \
     -d "7gram.xyz" \
     -d "*.7gram.xyz" \
     --agree-tos \
     --email "your@email.com" \
     --non-interactive
   ```

4. **Copy certificates to nginx directory:**

   ```bash
   sudo mkdir -p /opt/ssl/7gram.xyz
   sudo cp -L /etc/letsencrypt/live/7gram.xyz/fullchain.pem /opt/ssl/7gram.xyz/
   sudo cp -L /etc/letsencrypt/live/7gram.xyz/privkey.pem /opt/ssl/7gram.xyz/
   sudo chmod 644 /opt/ssl/7gram.xyz/fullchain.pem
   sudo chmod 600 /opt/ssl/7gram.xyz/privkey.pem
   ```

5. **Restart nginx:**

   ```bash
   cd ~/freddy
   ./run.sh restart
   ```

## Nginx Certificate Handling

### Container Startup Process

When the nginx container starts, the `docker/nginx/entrypoint.sh` script:

1. **Checks for Let's Encrypt certificates** in `/etc/letsencrypt-volume/` (mounted volume)
2. **Validates certificates** (checks expiry, validity)
3. **Copies certificates** to `/etc/nginx/ssl/`
4. **Falls back to self-signed** if Let's Encrypt certs unavailable
5. **Verifies certificate integrity** (key matches cert)
6. **Validates nginx configuration**
7. **Starts nginx**

### Volume Mounts

The `docker-compose.yml` mounts certificates as:

```yaml
services:
  nginx:
    volumes:
      - /opt/ssl/7gram.xyz:/etc/letsencrypt-volume:ro
```

- **Read-only mount** prevents container from modifying host certificates
- **Copied at startup** to `/etc/nginx/ssl/` for nginx to use

### Certificate Paths

| Location | Purpose |
|----------|---------|
| `/opt/ssl/7gram.xyz/` | Host filesystem - persistent storage |
| `/etc/letsencrypt-volume/` | Container mount point (read-only) |
| `/etc/nginx/ssl/` | nginx working directory (copied at startup) |
| `/etc/nginx/ssl/fallback/` | Self-signed fallback certificates |

## Automatic Renewal

### Systemd Timer (Production)

The `cert-manager.sh request` command sets up automatic renewal:

```bash
# Service: /etc/systemd/system/freddy-cert-renewal.service
# Timer: /etc/systemd/system/freddy-cert-renewal.timer
# Script: /usr/local/bin/renew-freddy-certs.sh
```

**Schedule:** Runs twice daily (00:00 and 12:00) with random delay

**Check timer status:**

```bash
sudo systemctl status freddy-cert-renewal.timer
```

### Manual Renewal

```bash
# Test renewal (dry run)
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Run renewal script
sudo /usr/local/bin/renew-freddy-certs.sh
```

## Troubleshooting

### Check Certificate Status

```bash
# On host
openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -text

# Check expiry
openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -dates

# Check if expires in 7 days
openssl x509 -checkend 604800 -noout -in /opt/ssl/7gram.xyz/fullchain.pem
echo $?  # 0 = still valid, 1 = expires within 7 days
```

### Nginx Container Logs

```bash
# View nginx startup logs
docker logs nginx

# Check for certificate issues
docker logs nginx | grep -i cert

# Watch logs in real-time
docker logs -f nginx
```

### Common Issues

#### 1. "No Let's Encrypt certificates found"

**Cause:** Certificates not generated or not in `/opt/ssl/7gram.xyz/`

**Solution:**
```bash
# Check if directory exists
ls -la /opt/ssl/7gram.xyz/

# Run certificate generation
cd ~/freddy
sudo ./scripts/cert-manager.sh request
```

#### 2. "Certificate and private key do not match"

**Cause:** Mismatch between cert and key files

**Solution:**
```bash
# Check modulus (should be identical)
openssl x509 -noout -modulus -in /opt/ssl/7gram.xyz/fullchain.pem | openssl md5
openssl rsa -noout -modulus -in /opt/ssl/7gram.xyz/privkey.pem | openssl md5

# If different, regenerate certificates
sudo ./scripts/cert-manager.sh request
```

#### 3. "Cloudflare API connection failed"

**Cause:** Invalid API credentials

**Solution:**
```bash
# Test Cloudflare API (Global API Key)
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "X-Auth-Email: your@email.com" \
  -H "X-Auth-Key: your-global-api-key"

# Test Cloudflare API (API Token)
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer your-api-token"

# Update GitHub secrets if needed
```

#### 4. "Browser shows security warning"

**Cause:** Using self-signed certificate instead of Let's Encrypt

**Solution:**
```bash
# Check certificate type
docker exec nginx openssl x509 -in /etc/nginx/ssl/fullchain.pem -noout -issuer

# If self-signed, upgrade to Let's Encrypt
sudo ./scripts/cert-manager.sh upgrade
```

#### 5. "Certificate expired"

**Cause:** Automatic renewal failed

**Solution:**
```bash
# Force renewal
sudo certbot renew --force-renewal

# Copy to nginx directory
sudo cp -L /etc/letsencrypt/live/7gram.xyz/fullchain.pem /opt/ssl/7gram.xyz/
sudo cp -L /etc/letsencrypt/live/7gram.xyz/privkey.pem /opt/ssl/7gram.xyz/

# Restart nginx
cd ~/freddy && ./run.sh restart
```

## Testing

### Local Testing

```bash
# Build nginx image
docker build -f docker/nginx/Dockerfile -t freddy-nginx:test .

# Run with test certificates
docker run --rm -d \
  --name nginx-test \
  -p 8080:80 \
  -p 8443:443 \
  freddy-nginx:test

# Test HTTP health check
curl http://localhost:8080/health

# Test HTTPS (self-signed warning expected)
curl -k https://localhost:8443/health

# Test redirect
curl -I http://localhost:8080/

# Cleanup
docker stop nginx-test
```

### Production Verification

```bash
# Check certificate chain
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz

# Test SSL configuration
curl -vI https://7gram.xyz 2>&1 | grep -E "(SSL|TLS|certificate)"

# Check all subdomains
for subdomain in photo nc home audiobook; do
  echo "Testing ${subdomain}.7gram.xyz..."
  curl -sI https://${subdomain}.7gram.xyz | head -1
done
```

## Security Best Practices

1. **Use API Tokens** instead of Global API Key when possible
2. **Limit token permissions** to only "Zone:DNS:Edit"
3. **Rotate credentials** periodically
4. **Keep certbot updated** for security patches
5. **Monitor certificate expiry** (Let's Encrypt sends emails)
6. **Use read-only mounts** for certificate volumes
7. **Set proper file permissions** (644 for certs, 600 for keys)

## References

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Certbot Documentation](https://certbot.eff.org/docs/)
- [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
- [DNS-01 Challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)

## Quick Reference

```bash
# Check certificate status
./scripts/cert-manager.sh check

# Request new certificate
sudo ./scripts/cert-manager.sh request

# Test renewal
sudo ./scripts/cert-manager.sh test-renewal

# View certificate info
openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -text

# Check expiry date
openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -enddate

# Restart nginx
cd ~/freddy && ./run.sh restart nginx
```
