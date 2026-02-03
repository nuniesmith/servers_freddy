# SSL Certificate Setup - Quick Reference

## ✅ Changes Made

### 1. docker-compose.yml
- ✅ Added `ssl-certs` named volume
- ✅ Updated nginx to mount `ssl-certs` volume instead of host path `/opt/ssl/7gram.xyz`

### 2. docker/nginx/entrypoint.sh
- ✅ Enhanced to check both Let's Encrypt directory structure and flat structure
- ✅ Better error messages and validation

### 3. .github/workflows/ci-cd.yml
- ✅ Removed `SSL_CERT_PATH` environment variable
- ✅ Removed host filesystem certificate operations
- ✅ Added strict pre-deployment validation (fails if certs missing/invalid)
- ✅ Simplified cleanup to only manage Docker volumes

## 🔄 Certificate Flow

```
┌──────────────┐       ┌─────────────┐       ┌─────────┐
│   Certbot    │──────▶│ ssl-certs   │──────▶│  Nginx  │
│  (CI/CD)     │ write │   volume    │ read  │ (mount) │
└──────────────┘       └─────────────┘       └─────────┘
                             │
                             │ Shared Docker Volume
                             ▼
                  /certs/live/7gram.xyz/
                      ├── fullchain.pem
                      └── privkey.pem
```

## 🚀 How It Works

### During CI/CD:
1. **ssl-generate job** creates certificates via certbot
2. Certificates stored in Docker volume `ssl-certs`
3. **deploy job** validates certs exist and match
4. Nginx container starts with volume mounted read-only

### During Nginx Startup:
1. Entrypoint checks `/etc/letsencrypt-volume/live/7gram.xyz/`
2. Copies certificates to `/etc/nginx/ssl/`
3. Validates cert/key match
4. Tests nginx config
5. Starts nginx

### Fallback:
- If no Let's Encrypt certs found, uses self-signed fallback
- Nginx always starts (may show browser warnings if self-signed)

## 📝 Testing Checklist

Before deploying to production:

- [ ] Verify `ssl-certs` volume defined in docker-compose.yml
- [ ] Verify nginx mounts `ssl-certs:/etc/letsencrypt-volume:ro`
- [ ] Check CI/CD has required secrets:
  - `CLOUDFLARE_API_TOKEN`
  - `SSL_EMAIL`
  - `FREDDY_TAILSCALE_IP`
  - `SSH_KEY`, `SSH_USER`, `SSH_PORT`
  - `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_SECRET`
- [ ] Test deployment workflow
- [ ] Check nginx logs after startup
- [ ] Verify HTTPS works: `curl -I https://7gram.xyz`

## 🐛 Quick Debugging

### Check if certs exist in volume:
```bash
docker run --rm -v ssl-certs:/certs:ro busybox ls -lah /certs/live/7gram.xyz/
```

### View certificate info:
```bash
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
  -in /certs/live/7gram.xyz/fullchain.pem -noout -text | head -20
```

### Check nginx is using correct certs:
```bash
docker exec nginx ls -lah /etc/nginx/ssl/
docker exec nginx cat /etc/nginx/ssl/fullchain.pem | openssl x509 -noout -subject -issuer
```

### Force fresh certificate generation:
1. Go to GitHub Actions
2. Run workflow manually
3. Enable "Force SSL certificate regeneration"

## 🎯 Key Benefits

✅ **No host filesystem dependency** - Fully portable
✅ **Simpler workflow** - One volume, one mount
✅ **Better security** - Read-only mount, no sudo needed  
✅ **Atomic operations** - No file copy race conditions
✅ **Clear validation** - Deployment fails early if certs invalid
✅ **Self-healing** - Falls back to self-signed if needed

## 🔗 Related Documentation

- [SSL_DOCKER_VOLUME_STRATEGY.md](./SSL_DOCKER_VOLUME_STRATEGY.md) - Complete architecture guide
- [SSL_SETUP.md](./SSL_SETUP.md) - Manual setup instructions
- [TROUBLESHOOTING_SSL.md](./TROUBLESHOOTING_SSL.md) - Common issues
