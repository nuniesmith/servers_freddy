# 🔧 SSL Certificate Troubleshooting Guide

This guide helps diagnose and fix SSL certificate issues with the Freddy nginx reverse proxy.

## 📋 Table of Contents

- [Common Issues](#common-issues)
- [Certificate Mismatch Error](#certificate-mismatch-error)
- [Diagnostic Tools](#diagnostic-tools)
- [Manual Fixes](#manual-fixes)
- [Prevention](#prevention)

## 🚨 Common Issues

### Nginx Container Restarting (Certificate Mismatch)

**Symptoms:**
```
nginx container status: Restarting (1) XX seconds ago
docker logs nginx shows: [ERROR] Certificate and private key do not match!
```

**Root Cause:**
The certificate file (`fullchain.pem`) and private key file (`privkey.pem`) don't match. This can happen when:
1. Certificates were regenerated but the private key wasn't updated
2. Files were copied from different certificate generations
3. Let's Encrypt renewal updated one file but not the other
4. Manual file operations mixed files from different sources

---

## 🔍 Certificate Mismatch Error

### Quick Diagnosis

SSH into the server and run the diagnostic script:

```bash
sudo ~/freddy/scripts/fix-ssl-mismatch.sh --check-only
```

This will check both the Let's Encrypt source certificates and the target directory.

### Understanding the Output

The script checks:
1. **File existence** - Are both `fullchain.pem` and `privkey.pem` present?
2. **Certificate validity** - Is the certificate expired?
3. **Certificate/Key match** - Do the certificate and key belong together?

Example output when certificates match:
```
✓ Both files exist
✓ Certificate is valid (not expired)
✓ Certificate and private key MATCH
```

Example output when certificates don't match:
```
✓ Both files exist
✓ Certificate is valid (not expired)
✗ Certificate and private key DO NOT MATCH
```

### Manual Verification

You can manually verify certificates match:

```bash
# On the server
sudo su

# Certificate modulus
openssl x509 -noout -modulus -in /opt/ssl/7gram.xyz/fullchain.pem | openssl md5

# Private key modulus
openssl rsa -noout -modulus -in /opt/ssl/7gram.xyz/privkey.pem | openssl md5

# These should output the SAME hash
```

If the hashes are different, the certificate and key don't match.

---

## 🛠️ Diagnostic Tools

### 1. Automated Fix Script (Recommended)

```bash
# Check only (no changes)
sudo ~/freddy/scripts/fix-ssl-mismatch.sh --check-only

# Check and fix if needed
sudo ~/freddy/scripts/fix-ssl-mismatch.sh

# Force regeneration
sudo ~/freddy/scripts/fix-ssl-mismatch.sh --force
```

The script will:
- Check Let's Encrypt certificates in `/etc/letsencrypt/live/7gram.xyz/`
- Check target certificates in `/opt/ssl/7gram.xyz/`
- Copy good certificates from Let's Encrypt to target if needed
- Restart nginx container
- Verify the fix worked

### 2. Docker Logs

```bash
# View nginx startup logs
docker logs nginx

# Follow logs in real-time
docker logs -f nginx

# Last 50 lines
docker logs --tail 50 nginx
```

### 3. Certificate Info

```bash
# Show certificate details
sudo openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -text

# Show certificate issuer and dates
sudo openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -issuer -dates

# Check expiration
sudo openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -checkend 0 && echo "Valid" || echo "Expired"
```

### 4. Container Status

```bash
# Check all containers
docker ps -a

# Check nginx specifically
docker ps -a | grep nginx

# Inspect nginx container
docker inspect nginx
```

---

## 🔧 Manual Fixes

### Fix 1: Copy from Let's Encrypt (Recommended)

If Let's Encrypt has valid matching certificates:

```bash
sudo su
cd /opt/ssl/7gram.xyz

# Backup current certificates
cp fullchain.pem fullchain.pem.backup.$(date +%Y%m%d_%H%M%S)
cp privkey.pem privkey.pem.backup.$(date +%Y%m%d_%H%M%S)

# Copy from Let's Encrypt (follow symlinks)
cp -L /etc/letsencrypt/live/7gram.xyz/fullchain.pem .
cp -L /etc/letsencrypt/live/7gram.xyz/privkey.pem .

# Set permissions
chmod 644 fullchain.pem
chmod 600 privkey.pem
chown actions:actions fullchain.pem privkey.pem

# Restart nginx
docker restart nginx

# Verify
sleep 3
docker ps | grep nginx
```

### Fix 2: Regenerate Certificates via CI/CD

Trigger a new certificate generation through GitHub Actions:

1. Go to your repository on GitHub
2. Navigate to **Actions** tab
3. Select **"🏠 Freddy Deploy"** workflow
4. Click **"Run workflow"**
5. Check **"Update DNS records"** if needed
6. Click **"Run workflow"**

The pipeline will:
- Generate fresh Let's Encrypt certificates
- Deploy them to `/opt/ssl/7gram.xyz/`
- Restart nginx with new certificates

### Fix 3: Regenerate Locally

If you have the server configured for local certbot:

```bash
cd ~/freddy
./run.sh ssl-init --force
```

This will:
- Generate new Let's Encrypt certificates using Cloudflare DNS
- Copy them to `/opt/ssl/7gram.xyz/`
- Prompt you to restart nginx

### Fix 4: Use Self-Signed Fallback (Development Only)

If you can't get Let's Encrypt working and need nginx running immediately:

```bash
sudo su
cd /opt/ssl/7gram.xyz

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout privkey.pem \
  -out fullchain.pem \
  -subj "/C=US/ST=State/L=City/O=Freddy/CN=7gram.xyz" \
  -addext "subjectAltName=DNS:7gram.xyz,DNS:*.7gram.xyz"

chmod 644 fullchain.pem
chmod 600 privkey.pem
chown actions:actions fullchain.pem privkey.pem

docker restart nginx
```

⚠️ **Warning:** Self-signed certificates will show browser security warnings. Use only for testing.

---

## 🛡️ Prevention

### Best Practices

1. **Always use the CI/CD pipeline** for certificate management
2. **Never manually edit certificate files** in `/opt/ssl/7gram.xyz/`
3. **Let certbot/CI/CD handle renewals** - don't manually copy files
4. **Backup before manual changes**:
   ```bash
   sudo tar -czf /tmp/ssl-backup-$(date +%Y%m%d_%H%M%S).tar.gz /opt/ssl/7gram.xyz/
   ```

### Automated Monitoring

The nginx container has a health check that will detect issues:

```bash
# Check health status
docker ps | grep nginx

# If healthy: Up XX seconds (healthy)
# If unhealthy: Up XX seconds (unhealthy)
```

### Certificate Expiration

Let's Encrypt certificates expire after 90 days. Renewal should happen automatically through:

1. **CI/CD scheduled jobs** (runs weekly)
2. **Manual workflow trigger** when needed
3. **Local renewal** with `./run.sh ssl-renew`

Check expiration:
```bash
sudo openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -enddate
```

---

## 📞 Getting Help

### Check Logs First

```bash
# Nginx logs
docker logs nginx

# Check what nginx sees in the mounted volume
docker exec nginx ls -lah /etc/letsencrypt-volume/

# Check what nginx has in its SSL directory
docker exec nginx ls -lah /etc/nginx/ssl/
```

### Common Log Messages

| Log Message | Meaning | Solution |
|-------------|---------|----------|
| `Certificate and private key do not match!` | Certificate/key mismatch | Run fix script |
| `Certificate is not valid` | Expired or corrupted | Regenerate certificates |
| `Certificate file missing` | Files not found | Check volume mount |
| `Found Let's Encrypt certificates` | Certificates detected | Normal operation |
| `Using self-signed fallback` | No real certs found | Get Let's Encrypt certs |

### Debug Mode

The nginx entrypoint script now includes detailed debugging. Check for:
- `[DEBUG]` lines showing certificate detection
- `[CERT]` lines showing certificate info
- File listings from the mounted volume
- Modulus calculations for verification

### Still Having Issues?

1. Check `/opt/ssl/7gram.xyz/` exists and has correct permissions
2. Verify Docker volume mount in `docker-compose.yml`
3. Check GitHub Actions secrets are set correctly
4. Review CI/CD logs in GitHub Actions tab
5. Ensure Cloudflare API token has DNS edit permissions

---

## 📚 Related Documentation

- [SSL Setup Guide](SSL_SETUP.md) - Complete SSL certificate setup
- [Deployment Guide](DEPLOYMENT_SUMMARY.md) - Full deployment process
- [Quick Start](../QUICK_START.md) - Get started quickly

---

**Last Updated:** 2025-01-XX  
**Maintainer:** Freddy DevOps Team