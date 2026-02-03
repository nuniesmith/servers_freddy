# SSL Certificate Testing Guide

## Pre-Deployment Testing

Before pushing changes to production, follow these steps to validate the SSL setup.

## 1. Local Docker Compose Validation

### Verify docker-compose.yml syntax
```bash
cd ~/freddy
docker-compose config
```

**Expected output:**
- No syntax errors
- `ssl-certs` volume listed under `volumes:`
- nginx service has `ssl-certs:/etc/letsencrypt-volume:ro` mount

### Test nginx build
```bash
docker-compose build nginx
```

**Expected output:**
- Build succeeds without errors
- Fallback certificates generated in Dockerfile
- Entrypoint script copied and made executable

## 2. Entrypoint Script Testing

### Test with no certificates (fallback mode)
```bash
# Start nginx without ssl-certs volume to test fallback
docker run --rm \
  --name nginx-test \
  -p 8443:443 \
  $(docker-compose config | grep 'image:' | head -1 | awk '{print $2}' || echo 'freddy-nginx') \
  sh -c '/docker-entrypoint.d/99-init.sh && nginx -g "daemon off;"'
```

**Expected behavior:**
- Entrypoint logs show: "No Let's Encrypt certificates found"
- Falls back to self-signed certificates
- Nginx starts successfully
- Can access https://localhost:8443 (with browser warning)

**Cleanup:**
```bash
docker stop nginx-test
```

### Test with Let's Encrypt directory structure
```bash
# Create a test volume with proper structure
docker volume create ssl-certs-test

# Create test certificates (self-signed for testing)
docker run --rm -v ssl-certs-test:/certs alpine/openssl sh -c "
  mkdir -p /certs/live/7gram.xyz
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /certs/live/7gram.xyz/privkey.pem \
    -out /certs/live/7gram.xyz/fullchain.pem \
    -subj '/C=US/ST=Test/L=Test/O=Test/CN=7gram.xyz'
"

# Test nginx with test certs
docker run --rm \
  --name nginx-test \
  -v ssl-certs-test:/etc/letsencrypt-volume:ro \
  -p 8443:443 \
  $(docker-compose config | grep 'image:' | head -1 | awk '{print $2}' || echo 'freddy-nginx') \
  sh -c '/docker-entrypoint.d/99-init.sh && nginx -g "daemon off;"' &

# Wait for startup
sleep 5

# Test HTTPS connection
curl -k -I https://localhost:8443

# Cleanup
docker stop nginx-test
docker volume rm ssl-certs-test
```

**Expected behavior:**
- Entrypoint logs show: "Found Let's Encrypt certificates"
- Copies certificates from volume
- Validation passes
- Nginx starts successfully
- Curl returns HTTP 200 or 301

## 3. CI/CD Workflow Validation

### Check GitHub Actions secrets
Ensure these secrets are set in your repository:

```bash
# Required secrets checklist:
# ✓ CLOUDFLARE_API_TOKEN
# ✓ CLOUDFLARE_ZONE_ID
# ✓ SSL_EMAIL
# ✓ FREDDY_TAILSCALE_IP
# ✓ SSH_KEY
# ✓ SSH_USER
# ✓ SSH_PORT
# ✓ TAILSCALE_OAUTH_CLIENT_ID
# ✓ TAILSCALE_OAUTH_SECRET
# ✓ DOCKER_USERNAME
# ✓ DOCKER_TOKEN
```

### Dry-run workflow (manual dispatch)
1. Go to GitHub Actions tab
2. Select "🏠 Freddy Deploy" workflow
3. Click "Run workflow"
4. Set options:
   - `skip_deploy`: `true` (don't actually deploy)
   - `update_dns`: `false` (don't change DNS)
   - `force_ssl_regen`: `false`
5. Click "Run workflow"

**Expected behavior:**
- Workflow runs but skips deployment
- SSL generation job should succeed (or skip if recent certs exist)
- No actual server changes

## 4. Production Deployment Testing

### Stage 1: Test DNS update only
1. Go to GitHub Actions
2. Run workflow with:
   - `skip_deploy`: `true`
   - `update_dns`: `true`
   - `force_ssl_regen`: `false`

**Verify:**
```bash
# Check DNS propagation
dig @1.1.1.1 7gram.xyz A
dig @1.1.1.1 photo.7gram.xyz A
dig @1.1.1.1 nc.7gram.xyz A

# Should all point to your FREDDY_TAILSCALE_IP
```

### Stage 2: Test SSL generation
1. Run workflow with:
   - `skip_deploy`: `true`
   - `update_dns`: `false`
   - `force_ssl_regen`: `true`

**Verify on server:**
```bash
# SSH to server
ssh -p $SSH_PORT $SSH_USER@$FREDDY_TAILSCALE_IP

# Check volume exists
docker volume inspect ssl-certs

# Check certificates exist
docker run --rm -v ssl-certs:/certs:ro busybox ls -lah /certs/live/7gram.xyz/

# Verify certificate details
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
  -in /certs/live/7gram.xyz/fullchain.pem -noout -text | head -30

# Check issuer (should be Let's Encrypt)
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
  -in /certs/live/7gram.xyz/fullchain.pem -noout -issuer

# Check expiry
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
  -in /certs/live/7gram.xyz/fullchain.pem -noout -dates
```

**Expected output:**
- Volume exists
- Certificate files present
- Issuer: `Let's Encrypt`
- Valid for 90 days
- Covers `7gram.xyz` and `*.7gram.xyz`

### Stage 3: Full deployment
1. Run workflow with:
   - `skip_deploy`: `false`
   - `update_dns`: `true`
   - `force_ssl_regen`: `true`

**Verify deployment:**
```bash
# On server
docker ps | grep nginx
docker logs nginx

# Check nginx is using correct certs
docker exec nginx ls -lah /etc/nginx/ssl/
docker exec nginx cat /etc/nginx/ssl/fullchain.pem | openssl x509 -noout -subject -issuer

# Test HTTPS locally on server
curl -I https://localhost

# From internet (replace with your domain)
curl -I https://7gram.xyz
curl -I https://photo.7gram.xyz
curl -I https://nc.7gram.xyz
```

**Expected behavior:**
- Nginx container running
- Logs show "Let's Encrypt certificates configured"
- HTTPS returns 200 or 301 (not 502/503)
- Browser shows valid SSL (green lock)
- No certificate errors

## 5. Certificate Validation Tests

### Test certificate/key match
```bash
# On server
docker run --rm -v ssl-certs:/certs:ro alpine/openssl sh -c "
  CERT_MOD=\$(openssl x509 -noout -modulus -in /certs/live/7gram.xyz/fullchain.pem | openssl md5)
  KEY_MOD=\$(openssl rsa -noout -modulus -in /certs/live/7gram.xyz/privkey.pem | openssl md5)
  echo \"Cert MD5: \$CERT_MOD\"
  echo \"Key MD5:  \$KEY_MOD\"
  if [ \"\$CERT_MOD\" = \"\$KEY_MOD\" ]; then
    echo '✅ Certificate and key MATCH'
    exit 0
  else
    echo '❌ Certificate and key DO NOT MATCH'
    exit 1
  fi
"
```

### Test certificate chain
```bash
# Verify certificate chain is complete
docker run --rm -v ssl-certs:/certs:ro alpine/openssl sh -c "
  openssl verify -CAfile /certs/live/7gram.xyz/chain.pem \
    /certs/live/7gram.xyz/cert.pem
"
```

**Expected output:**
```
/certs/live/7gram.xyz/cert.pem: OK
```

### Test certificate expiration
```bash
# Check days until expiration
docker run --rm -v ssl-certs:/certs:ro alpine/openssl sh -c "
  openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -checkend 0 && echo 'Valid' || echo 'Expired'
  openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -checkend 2592000 && echo 'Valid for 30+ days' || echo 'Expires soon'
"
```

### Test TLS connection
```bash
# Test TLS handshake
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null

# Check for specific indicators:
# - "Verify return code: 0 (ok)" = Valid certificate
# - Subject should match your domain
# - Issuer should be "Let's Encrypt"
```

## 6. Browser Testing

### Manual verification
1. Open browser
2. Navigate to `https://7gram.xyz`
3. Click lock icon in address bar
4. View certificate

**Expected details:**
- Issued to: `7gram.xyz`
- Issued by: `Let's Encrypt`
- Valid from: Today's date
- Valid until: ~90 days from now
- Subject Alternative Names: `7gram.xyz`, `*.7gram.xyz`

### Multiple subdomains
Test each subdomain:
- ✅ https://7gram.xyz
- ✅ https://photo.7gram.xyz
- ✅ https://nc.7gram.xyz
- ✅ https://home.7gram.xyz
- ✅ https://abs.7gram.xyz

All should show valid SSL (green lock).

## 7. Automated Health Checks

### Create a test script
```bash
#!/bin/bash
# save as: test-ssl-health.sh

DOMAINS=(
  "7gram.xyz"
  "photo.7gram.xyz"
  "nc.7gram.xyz"
  "home.7gram.xyz"
  "abs.7gram.xyz"
)

echo "Testing SSL certificates for all domains..."
for domain in "${DOMAINS[@]}"; do
  echo ""
  echo "Testing: $domain"
  
  # Test HTTPS connection
  if curl -fsSL -I "https://$domain" -o /dev/null 2>&1; then
    echo "  ✅ HTTPS connection successful"
  else
    echo "  ❌ HTTPS connection failed"
    continue
  fi
  
  # Check certificate validity
  if echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | \
     openssl x509 -noout -checkend 0 2>/dev/null; then
    echo "  ✅ Certificate is valid"
  else
    echo "  ❌ Certificate is invalid or expired"
  fi
  
  # Check issuer
  ISSUER=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | \
           openssl x509 -noout -issuer 2>/dev/null | grep -o "Let's Encrypt")
  if [ -n "$ISSUER" ]; then
    echo "  ✅ Issued by Let's Encrypt"
  else
    echo "  ⚠️  Not issued by Let's Encrypt"
  fi
done

echo ""
echo "SSL health check complete!"
```

**Run it:**
```bash
chmod +x test-ssl-health.sh
./test-ssl-health.sh
```

## 8. Failure Scenario Testing

### Test 1: Missing certificates
```bash
# Remove ssl-certs volume
docker volume rm ssl-certs

# Start nginx
docker-compose up -d nginx

# Check logs
docker logs nginx

# Expected: Should fall back to self-signed certs
# Browser should show warning but nginx should be running
```

### Test 2: Corrupted certificates
```bash
# Create volume with invalid certs
docker volume create ssl-certs
docker run --rm -v ssl-certs:/certs busybox sh -c "
  mkdir -p /certs/live/7gram.xyz
  echo 'invalid cert' > /certs/live/7gram.xyz/fullchain.pem
  echo 'invalid key' > /certs/live/7gram.xyz/privkey.pem
"

# Try to start nginx
docker-compose up -d nginx

# Check logs
docker logs nginx

# Expected: Should fall back to self-signed or fail with clear error
```

### Test 3: Certificate/key mismatch
```bash
# Create mismatched cert/key pair
docker volume create ssl-certs
docker run --rm -v ssl-certs:/certs alpine/openssl sh -c "
  mkdir -p /certs/live/7gram.xyz
  # Generate first pair
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /tmp/key1.pem -out /certs/live/7gram.xyz/fullchain.pem \
    -subj '/CN=test1'
  # Generate second pair (different key)
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /certs/live/7gram.xyz/privkey.pem -out /tmp/cert2.pem \
    -subj '/CN=test2'
"

# Try to start nginx
docker-compose up -d nginx

# Check logs
docker logs nginx

# Expected: Should fail with cert/key mismatch error
```

## 9. Rollback Testing

### Create a backup before changes
```bash
# Backup current working volume
docker run --rm -v ssl-certs:/certs:ro -v $(pwd):/backup busybox \
  tar czf /backup/ssl-certs-backup-$(date +%Y%m%d-%H%M%S).tar.gz /certs
```

### Test rollback
```bash
# If something goes wrong, restore backup
docker run --rm -v ssl-certs:/certs -v $(pwd):/backup busybox \
  tar xzf /backup/ssl-certs-backup-TIMESTAMP.tar.gz -C /

# Restart nginx
docker-compose restart nginx
```

## 10. Monitoring Setup

### Add monitoring for certificate expiration
```bash
# Add to crontab or monitoring system
#!/bin/bash
# check-cert-expiry.sh

EXPIRY_DAYS=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl sh -c "
  openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -enddate | \
  cut -d= -f2 | xargs -I{} date -d {} +%s
  date +%s
" | awk '{if (NR==1) exp=$1; else now=$1} END {print int((exp-now)/86400)}')

echo "Certificate expires in $EXPIRY_DAYS days"

if [ $EXPIRY_DAYS -lt 30 ]; then
  echo "⚠️  Certificate renewal needed soon!"
  # Send alert (email, Discord, etc.)
fi
```

## Testing Checklist

Before deploying to production, ensure:

- [ ] docker-compose.yml syntax valid
- [ ] ssl-certs volume defined
- [ ] nginx mounts ssl-certs correctly
- [ ] Fallback certificates work
- [ ] Let's Encrypt structure recognized
- [ ] Certificate validation works
- [ ] GitHub Actions secrets configured
- [ ] DNS update job works
- [ ] SSL generate job works
- [ ] Deploy job works
- [ ] Nginx starts successfully
- [ ] HTTPS accessible from internet
- [ ] All subdomains work
- [ ] Certificate issuer is Let's Encrypt
- [ ] Certificate expiry is 90 days
- [ ] Browser shows green lock
- [ ] Failure scenarios handled gracefully

## Continuous Monitoring

Set up these ongoing checks:

1. **Certificate expiration alerts** (30 days before)
2. **Weekly renewal checks** (automated via GitHub Actions schedule)
3. **Health checks** (nginx container status)
4. **HTTPS endpoint monitoring** (uptime service)
5. **Certificate validation** (automated daily checks)

## Troubleshooting Common Issues

See [TROUBLESHOOTING_SSL.md](./TROUBLESHOOTING_SSL.md) for detailed troubleshooting guides.
