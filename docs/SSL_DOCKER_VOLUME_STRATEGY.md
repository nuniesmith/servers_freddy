# SSL Certificate Docker Volume Strategy

## Overview

This document describes how SSL certificates are managed across the CI/CD pipeline and runtime containers for the Freddy project.

## Architecture

### ✅ New Approach: Shared Docker Named Volume

```
┌─────────────────────────────────────────────────────────────┐
│                    CI/CD Pipeline                           │
│                                                             │
│  1. dns-update job: Update Cloudflare DNS                  │
│                                                             │
│  2. ssl-generate job:                                      │
│     └─> certbot generates certs via Cloudflare DNS         │
│     └─> Stores in Docker volume: ssl-certs                 │
│         /certs/live/7gram.xyz/fullchain.pem                │
│         /certs/live/7gram.xyz/privkey.pem                  │
│                                                             │
│  3. deploy job:                                            │
│     └─> Validates certs exist in ssl-certs volume          │
│     └─> Starts nginx with volume mounted                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Docker Volume: ssl-certs
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Runtime (nginx)                          │
│                                                             │
│  nginx container:                                          │
│    volumes:                                                │
│      - ssl-certs:/etc/letsencrypt-volume:ro               │
│                                                             │
│  entrypoint.sh:                                            │
│    1. Checks /etc/letsencrypt-volume/live/7gram.xyz/      │
│    2. Copies certs to /etc/nginx/ssl/                     │
│    3. Falls back to self-signed if missing                │
│    4. Validates nginx config                              │
│    5. Starts nginx                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### ❌ Old Approach (Deprecated)

The previous approach used host filesystem paths:
- CI/CD copied certs to `/opt/ssl/7gram.xyz` on the host
- docker-compose.yml mounted host path into container
- Multiple copy operations introduced failure points
- Required sudo permissions for file operations

## Benefits of Docker Volume Approach

### 1. **Portability**
   - No dependency on host filesystem paths
   - Works identically on any Docker host
   - Easier to migrate or replicate environment

### 2. **Simplicity**
   - Single source of truth: `ssl-certs` volume
   - No intermediate file copies
   - Fewer permission issues

### 3. **Security**
   - Certificates never touch host filesystem
   - Volume permissions managed by Docker
   - Read-only mount in nginx prevents accidental modification

### 4. **Reliability**
   - Atomic volume operations
   - Certificates available immediately after generation
   - No race conditions between copy operations

## File Changes

### 1. docker-compose.yml

**Added:**
```yaml
volumes:
    ssl-certs:
        driver: local
```

**Changed nginx service:**
```yaml
nginx:
    volumes:
        - ssl-certs:/etc/letsencrypt-volume:ro  # Changed from host path
```

### 2. docker/nginx/entrypoint.sh

**Enhanced certificate detection:**
- Now checks both Let's Encrypt standard structure (`live/DOMAIN/`)
- Falls back to flat structure for compatibility
- Better error messages and debugging output

### 3. .github/workflows/ci-cd.yml

**Removed:**
- `SSL_CERT_PATH` environment variable
- Host filesystem certificate cleanup operations
- Certificate copy from volume to host operations

**Enhanced:**
- Pre-deployment validation ensures certs exist before nginx starts
- Certificate mismatch detection prevents corrupted deployments
- Cleaner error handling with explicit failure modes

## Workflow Sequence

### Certificate Generation (CI/CD)

1. **DNS Update Job**
   - Updates Cloudflare DNS records
   - Ensures domain points to server

2. **SSL Generate Job**
   ```bash
   # Cleanup phase
   docker volume rm ssl-certs  # Force fresh start
   
   # Generation phase
   certbot certonly --dns-cloudflare \
     --email $EMAIL \
     --domain 7gram.xyz \
     --domain '*.7gram.xyz'
   
   # Deployment phase
   # Action deploys certs to Docker volume: ssl-certs
   ```

3. **Deploy Job - Pre-deploy**
   ```bash
   # Validate certificates exist
   docker run --rm -v ssl-certs:/certs:ro busybox \
     test -f /certs/live/7gram.xyz/fullchain.pem
   
   # Verify cert/key match
   CERT_MOD=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl \
     x509 -noout -modulus -in /certs/live/7gram.xyz/fullchain.pem | openssl md5)
   KEY_MOD=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl \
     rsa -noout -modulus -in /certs/live/7gram.xyz/privkey.pem | openssl md5)
   
   # Must match or deployment fails
   [ "$CERT_MOD" = "$KEY_MOD" ] || exit 1
   ```

4. **Deploy Job - Deploy**
   ```bash
   # Start nginx with volume mounted
   docker compose up -d nginx
   ```

### Nginx Startup (Container Runtime)

1. **Entrypoint Execution**
   ```bash
   # Check for certs in volume
   if [ -f /etc/letsencrypt-volume/live/7gram.xyz/fullchain.pem ]; then
     # Copy to nginx SSL directory
     cp /etc/letsencrypt-volume/live/7gram.xyz/fullchain.pem \
        /etc/nginx/ssl/fullchain.pem
     cp /etc/letsencrypt-volume/live/7gram.xyz/privkey.pem \
        /etc/nginx/ssl/privkey.pem
   else
     # Use self-signed fallback
     cp /etc/nginx/ssl/fallback/fullchain.pem \
        /etc/nginx/ssl/fullchain.pem
     cp /etc/nginx/ssl/fallback/privkey.pem \
        /etc/nginx/ssl/privkey.pem
   fi
   ```

2. **Certificate Validation**
   ```bash
   # Verify cert/key match
   openssl x509 -noout -modulus -in /etc/nginx/ssl/fullchain.pem | openssl md5
   openssl rsa -noout -modulus -in /etc/nginx/ssl/privkey.pem | openssl md5
   # Must match or container fails to start
   ```

3. **Nginx Config Validation**
   ```bash
   nginx -t  # Test configuration
   ```

4. **Nginx Start**
   ```bash
   nginx -g "daemon off;"
   ```

## Certificate Lifecycle

### Initial Deployment
1. No `ssl-certs` volume exists
2. CI/CD creates volume and generates certificates
3. Nginx starts with Let's Encrypt certificates

### Certificate Renewal (Weekly via Schedule)
1. Existing `ssl-certs` volume remains
2. Certbot checks expiration, renews if needed
3. Updated certificates placed in volume
4. Nginx reload picks up new certificates (or restart)

### Force Regeneration (Manual)
1. Workflow dispatch with `force_ssl_regen: true`
2. Deletes `ssl-certs` volume
3. Generates fresh certificates
4. Nginx restarts with new certificates

### Development/Fallback
1. If certbot fails or volume is missing
2. Nginx uses self-signed certificates from Dockerfile
3. Service remains available (with browser warnings)

## Debugging

### Check if certificates exist in volume
```bash
docker run --rm -v ssl-certs:/certs:ro busybox ls -lah /certs/live/7gram.xyz/
```

### Inspect certificate details
```bash
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
  -in /certs/live/7gram.xyz/fullchain.pem -noout -text
```

### Verify certificate/key match
```bash
CERT_MOD=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl \
  x509 -noout -modulus -in /certs/live/7gram.xyz/fullchain.pem | openssl md5)
KEY_MOD=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl \
  rsa -noout -modulus -in /certs/live/7gram.xyz/privkey.pem | openssl md5)
echo "Cert: $CERT_MOD"
echo "Key:  $KEY_MOD"
```

### Check nginx container logs
```bash
docker logs nginx
```

### Inspect nginx SSL configuration
```bash
docker exec nginx ls -lah /etc/nginx/ssl/
docker exec nginx openssl x509 -in /etc/nginx/ssl/fullchain.pem -noout -text
```

## Troubleshooting

### Problem: Nginx fails to start with SSL errors

**Symptoms:**
```
nginx: [emerg] cannot load certificate "/etc/nginx/ssl/fullchain.pem"
```

**Solution:**
1. Check if certificates exist in volume:
   ```bash
   docker run --rm -v ssl-certs:/certs:ro busybox ls -lah /certs/live/7gram.xyz/
   ```

2. If missing, trigger certificate regeneration:
   ```bash
   # Via GitHub Actions workflow_dispatch with force_ssl_regen: true
   ```

3. Check entrypoint logs:
   ```bash
   docker logs nginx 2>&1 | grep -A 20 "Nginx Initialization"
   ```

### Problem: Certificate/key mismatch

**Symptoms:**
```
❌ ERROR: Certificate and private key do not match!
```

**Solution:**
1. Force regeneration (deletes volume and recreates):
   - Go to GitHub Actions
   - Run workflow with `force_ssl_regen: true`

2. If issue persists, check certbot logs in ssl-generate job

### Problem: Self-signed certificate in use

**Symptoms:**
- Browser shows "Your connection is not private"
- Certificate issuer is "Freddy" not "Let's Encrypt"

**Solution:**
1. Check if Let's Encrypt certs exist:
   ```bash
   docker run --rm -v ssl-certs:/certs:ro busybox ls -lah /certs/live/7gram.xyz/
   ```

2. If missing, check CI/CD logs for certbot failures
3. Verify Cloudflare API credentials are set correctly
4. Ensure DNS propagation completed before certbot ran

## Migration from Old Approach

If you have existing certificates in `/opt/ssl/7gram.xyz`:

1. **Optional: Copy to Docker volume**
   ```bash
   # Create volume if it doesn't exist
   docker volume create ssl-certs
   
   # Create Let's Encrypt directory structure
   docker run --rm -v ssl-certs:/certs busybox mkdir -p /certs/live/7gram.xyz
   
   # Copy certificates
   docker run --rm \
     -v ssl-certs:/certs \
     -v /opt/ssl/7gram.xyz:/source:ro \
     busybox sh -c "
       cp /source/fullchain.pem /certs/live/7gram.xyz/fullchain.pem
       cp /source/privkey.pem /certs/live/7gram.xyz/privkey.pem
     "
   ```

2. **Or: Let CI/CD regenerate fresh certificates**
   - Simply deploy - CI/CD will generate new certificates
   - No manual migration needed

3. **Clean up old host paths (optional)**
   ```bash
   sudo rm -rf /opt/ssl/7gram.xyz
   ```

## Security Considerations

1. **Read-only mount**: Nginx mounts volume as `:ro` to prevent accidental modification
2. **Volume isolation**: Certificates only accessible to containers with volume mounted
3. **No host exposure**: Certificates never written to host filesystem
4. **Proper permissions**: Docker manages ownership/permissions automatically
5. **Minimal attack surface**: Only entrypoint script has write access during startup

## Backup & Recovery

### Backup certificates
```bash
docker run --rm -v ssl-certs:/certs:ro -v $(pwd):/backup busybox \
  tar czf /backup/ssl-certs-backup-$(date +%Y%m%d).tar.gz /certs
```

### Restore certificates
```bash
docker run --rm -v ssl-certs:/certs -v $(pwd):/backup busybox \
  tar xzf /backup/ssl-certs-backup-YYYYMMDD.tar.gz -C /
```

### Verify backup
```bash
tar tzf ssl-certs-backup-*.tar.gz
```

## References

- Docker Volumes: https://docs.docker.com/storage/volumes/
- Let's Encrypt: https://letsencrypt.org/docs/
- Certbot: https://certbot.eff.org/docs/
- Nginx SSL: https://nginx.org/en/docs/http/configuring_https_servers.html
