# SSL Certificate Fix Documentation

## Problem Summary

The nginx container was failing to start due to mismatched SSL certificates and private keys. The error showed:

```
[ERROR] Certificate and private key do not match!
[DEBUG] Certificate modulus: MD5(stdin)= baf59ff7f5b05fde6799439b6f31a290
[DEBUG] Private key modulus: MD5(stdin)= d41d8cd98f00b204e9800998ecf8427e
```

The private key MD5 hash `d41d8cd98f00b204e9800998ecf8427e` is literally the hash of an empty string, indicating the private key file was corrupted or empty.

## Root Cause

There was a **mismatch between CI/CD deployment and docker-compose configuration**:

1. **CI/CD Workflow**: Generated certificates in a Docker volume `ssl-certs` with full Let's Encrypt directory structure:
   ```
   ssl-certs (Docker volume)
   └── live/
       └── 7gram.xyz/
           ├── fullchain.pem
           ├── privkey.pem
           ├── cert.pem
           └── chain.pem
   ```

2. **docker-compose.yml**: Expected flat certificate files in a host directory:
   ```yaml
   volumes:
     - /opt/ssl/7gram.xyz:/etc/letsencrypt-volume:ro
   ```
   
   Expected structure:
   ```
   /opt/ssl/7gram.xyz/
   ├── fullchain.pem
   └── privkey.pem
   ```

3. **The Problem**: The files in `/opt/ssl/7gram.xyz` were either:
   - Corrupted symlinks from a manual copy attempt
   - Empty or partial files
   - From a different certificate generation attempt

Meanwhile, valid Let's Encrypt certificates existed in `/etc/letsencrypt/live/7gram.xyz/` on the server but weren't being used by Docker.

## Immediate Fix (Manual)

Run this on the Freddy server as root/sudo:

```bash
# Stop nginx
docker stop nginx 2>/dev/null || true

# Backup corrupted certificates
sudo mkdir -p /opt/ssl/backup
sudo mv /opt/ssl/7gram.xyz /opt/ssl/backup/corrupted-$(date +%Y%m%d-%H%M%S) 2>/dev/null || true

# Copy valid certificates from Let's Encrypt
sudo mkdir -p /opt/ssl/7gram.xyz
sudo cp /etc/letsencrypt/live/7gram.xyz/fullchain.pem /opt/ssl/7gram.xyz/fullchain.pem
sudo cp /etc/letsencrypt/live/7gram.xyz/privkey.pem /opt/ssl/7gram.xyz/privkey.pem

# Set proper permissions
sudo chmod 644 /opt/ssl/7gram.xyz/fullchain.pem
sudo chmod 600 /opt/ssl/7gram.xyz/privkey.pem

# Verify certificates match
echo "Verifying certificates..."
CERT_MOD=$(openssl x509 -noout -modulus -in /opt/ssl/7gram.xyz/fullchain.pem | openssl md5)
KEY_MOD=$(openssl rsa -noout -modulus -in /opt/ssl/7gram.xyz/privkey.pem | openssl md5)
echo "Certificate modulus: $CERT_MOD"
echo "Private key modulus: $KEY_MOD"

if [ "$CERT_MOD" = "$KEY_MOD" ]; then
    echo "✓ SUCCESS! Certificates match correctly"
    cd ~/freddy && docker compose up -d nginx
else
    echo "✗ ERROR: Certificates still don't match"
    exit 1
fi
```

### Or Use the Fix Script

```bash
cd ~/freddy
chmod +x scripts/fix-ssl-certs.sh
sudo ./scripts/fix-ssl-certs.sh
```

The script will:
- ✓ Validate Let's Encrypt certificates are valid
- ✓ Backup any existing corrupted certificates
- ✓ Copy valid certificates to the Docker mount location
- ✓ Verify certificate and private key match
- ✓ Optionally restart nginx

## Long-term Solution (Automated in CI/CD)

The CI/CD workflow (`.github/workflows/ci-cd.yml`) has been updated to automatically copy certificates from the Docker volume to the host directory during deployment:

### What Changed

Added a new step in the `deploy` job's `pre-deploy-command` section that:

1. **Extracts certificates** from the `ssl-certs` Docker volume
2. **Copies them** to `/opt/ssl/7gram.xyz` (the host directory)
3. **Sets proper permissions** (644 for cert, 600 for key)
4. **Verifies** the certificate and key match before proceeding

### Key Code Addition

```yaml
# Copy SSL certificates from Docker volume to host directory
echo "📋 Copying SSL certificates to host directory..."
if [ "$CERT_EXISTS" = "yes" ]; then
  sudo mkdir -p ${{ env.SSL_CERT_PATH }}
  
  # Extract from Docker volume to host
  docker run --rm -v ssl-certs:/certs:ro -v ${{ env.SSL_CERT_PATH }}:/target:rw \
    busybox:latest cp /certs/live/${{ env.DOMAIN }}/fullchain.pem /target/fullchain.pem
  
  docker run --rm -v ssl-certs:/certs:ro -v ${{ env.SSL_CERT_PATH }}:/target:rw \
    busybox:latest cp /certs/live/${{ env.DOMAIN }}/privkey.pem /target/privkey.pem
  
  # Set permissions
  sudo chmod 644 ${{ env.SSL_CERT_PATH }}/fullchain.pem
  sudo chmod 600 ${{ env.SSL_CERT_PATH }}/privkey.pem
  
  # Verify match
  COPIED_CERT_MOD=$(openssl x509 -noout -modulus -in ${{ env.SSL_CERT_PATH }}/fullchain.pem | openssl md5)
  COPIED_KEY_MOD=$(openssl rsa -noout -modulus -in ${{ env.SSL_CERT_PATH }}/privkey.pem | openssl md5)
  
  if [ "$COPIED_CERT_MOD" = "$COPIED_KEY_MOD" ]; then
    echo "✅ Certificates successfully copied"
  else
    echo "❌ ERROR: Certificate mismatch!"
    exit 1
  fi
fi
```

## Verification

### 1. Check Certificate Files Exist

```bash
ls -lh /opt/ssl/7gram.xyz/
```

Expected output:
```
-rw-r--r-- 1 root root 2.8K Jan 27 22:35 fullchain.pem
-rw------- 1 root root 1.7K Jan 27 22:35 privkey.pem
```

**Note**: privkey.pem should be >1KB. If it's 241 bytes or less, it's corrupted!

### 2. Verify Certificate and Key Match

```bash
CERT_MOD=$(openssl x509 -noout -modulus -in /opt/ssl/7gram.xyz/fullchain.pem | openssl md5)
KEY_MOD=$(openssl rsa -noout -modulus -in /opt/ssl/7gram.xyz/privkey.pem | openssl md5)
echo "Cert: $CERT_MOD"
echo "Key:  $KEY_MOD"
```

Both MD5 hashes **must be identical**.

### 3. Check Certificate Details

```bash
openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -text | grep -A2 "Issuer:"
openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -dates
```

Should show:
- Issuer: Let's Encrypt
- Valid dates that haven't expired

### 4. Check Nginx Container

```bash
docker logs nginx --tail 50
```

Should show:
```
[INFO] ✓ Let's Encrypt certificates configured for production
[INFO] ✓ Certificate verification passed
[INFO] ✓ Nginx is ready to start
```

### 5. Test HTTPS Access

```bash
curl -I https://7gram.xyz/health
```

Should return `200 OK` without certificate errors.

## Common Issues

### Issue: "Private key modulus is empty hash"

**Symptom**: `MD5(stdin)= d41d8cd98f00b204e9800998ecf8427e` (empty string hash)

**Cause**: Private key file is empty or corrupted

**Fix**: Run the manual fix script to copy valid certificates

### Issue: "Certificate files not found in volume"

**Symptom**: Docker volume `ssl-certs` doesn't exist or is empty

**Cause**: SSL generation job didn't run or failed

**Fix**: 
1. Trigger workflow with `force_ssl_regen: true`
2. Or run certbot manually on the server
3. Then run the fix script

### Issue: "Permission denied reading private key"

**Symptom**: nginx can't read `/etc/letsencrypt-volume/privkey.pem`

**Cause**: Wrong file permissions

**Fix**:
```bash
sudo chmod 644 /opt/ssl/7gram.xyz/fullchain.pem
sudo chmod 600 /opt/ssl/7gram.xyz/privkey.pem
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ CI/CD Workflow (ssl-generate job)                          │
│                                                             │
│ 1. Generate certs with certbot                             │
│ 2. Store in Docker volume: ssl-certs                       │
│    Structure: /certs/live/7gram.xyz/fullchain.pem         │
│                                     /privkey.pem           │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ CI/CD Workflow (deploy job)                                │
│                                                             │
│ 3. Copy from Docker volume to host:                        │
│    docker run -v ssl-certs:/certs:ro \                     │
│               -v /opt/ssl/7gram.xyz:/target:rw \           │
│               busybox cp /certs/live/.../fullchain.pem ... │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Host Filesystem                                             │
│                                                             │
│ /opt/ssl/7gram.xyz/                                        │
│ ├── fullchain.pem (644)                                    │
│ └── privkey.pem (600)                                      │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼ (docker-compose.yml mount)
┌─────────────────────────────────────────────────────────────┐
│ Nginx Container                                             │
│                                                             │
│ Volume mount:                                               │
│   /opt/ssl/7gram.xyz → /etc/letsencrypt-volume:ro         │
│                                                             │
│ Entrypoint copies to:                                      │
│   /etc/nginx/ssl/fullchain.pem                             │
│   /etc/nginx/ssl/privkey.pem                               │
│                                                             │
│ Nginx config uses:                                         │
│   ssl_certificate /etc/nginx/ssl/fullchain.pem;           │
│   ssl_certificate_key /etc/nginx/ssl/privkey.pem;         │
└─────────────────────────────────────────────────────────────┘
```

## Future Improvements

1. **Consolidate certificate storage**: Use either Docker volumes OR host directories, not both
2. **Add certificate expiry monitoring**: Alert before certificates expire
3. **Automated renewal**: Set up certbot renewal cron job on the server
4. **Health check enhancement**: Add SSL certificate expiry to nginx health endpoint

## References

- Nginx entrypoint script: `docker/nginx/entrypoint.sh`
- Docker compose: `docker-compose.yml`
- CI/CD workflow: `.github/workflows/ci-cd.yml`
- Fix script: `scripts/fix-ssl-certs.sh`
