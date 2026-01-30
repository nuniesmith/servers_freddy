# 🚀 Deployment Checklist - Nginx SSL Fix

## Pre-Deployment Checks

### GitHub Secrets Configuration
- [ ] `CLOUDFLARE_EMAIL` secret is set
- [ ] `CLOUDFLARE_API_KEY` or `CLOUDFLARE_API_TOKEN` secret is set
- [ ] `CERTBOT_EMAIL` secret is set (optional, defaults to CLOUDFLARE_EMAIL)
- [ ] All other required secrets are present (SSH_KEY, TAILSCALE_*, etc.)

**Verify:** Go to https://github.com/your-username/servers_freddy/settings/secrets/actions

### Local Testing
- [ ] Build nginx image successfully: `docker build -f docker/nginx/Dockerfile -t freddy-nginx:test .`
- [ ] Run test container: `docker run --rm -d --name nginx-test -p 8080:80 -p 8443:443 freddy-nginx:test`
- [ ] HTTP health check works: `curl http://localhost:8080/health` → Returns "OK"
- [ ] HTTPS health check works: `curl -k https://localhost:8443/health` → Returns "OK"
- [ ] HTTP redirects to HTTPS: `curl -I http://localhost:8080/` → Returns 301
- [ ] Dashboard loads: `curl -k https://localhost:8443/` → Returns HTML
- [ ] No errors in logs: `docker logs nginx-test` → Look for "✓ Nginx is ready"
- [ ] Cleanup test container: `docker stop nginx-test`

### Code Review
- [ ] `scripts/ci-ssl-setup.sh` is executable (chmod +x)
- [ ] `docker/nginx/entrypoint.sh` is executable (chmod +x)
- [ ] All file paths use correct syntax (services/ not ../services/)
- [ ] No syntax errors in nginx configs
- [ ] No merge conflicts

## Deployment

### Commit and Push
- [ ] All changes staged: `git add .`
- [ ] Meaningful commit message created
- [ ] Committed: `git commit -m "..."`
- [ ] Pushed to main: `git push origin main`

### Monitor CI/CD Pipeline
- [ ] GitHub Actions workflow triggered
- [ ] DNS update job completes successfully
- [ ] SSL certificate check/generation completes
- [ ] Deployment job completes successfully
- [ ] Health checks pass
- [ ] No errors in workflow logs

**Watch:** https://github.com/your-username/servers_freddy/actions

## Post-Deployment Verification

### Server-Side Checks (SSH to server)
- [ ] SSL certificates exist: `ls -la /opt/ssl/7gram.xyz/`
- [ ] Certificates are Let's Encrypt: `openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -issuer`
- [ ] Certificate not expired: `openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -dates`
- [ ] Nginx container is running: `docker ps | grep nginx`
- [ ] Nginx container is healthy: `docker ps` → STATUS should show "healthy"
- [ ] No errors in nginx logs: `docker logs nginx | tail -50`

### Local Testing from Server
- [ ] HTTP health works: `curl http://localhost/health` → "OK"
- [ ] HTTPS health works: `curl -k https://localhost/health` → "OK"
- [ ] HTTP redirects: `curl -I http://localhost/` → 301 to HTTPS
- [ ] Services are up: `cd ~/freddy && ./run.sh status`

### External Testing (from your local machine)
- [ ] Root domain loads: `curl https://7gram.xyz` → Dashboard HTML
- [ ] No SSL warnings in browser when visiting https://7gram.xyz
- [ ] PhotoPrism accessible: `curl -I https://photo.7gram.xyz` → Not 500
- [ ] Nextcloud accessible: `curl -I https://nc.7gram.xyz` → Not 500
- [ ] Home Assistant accessible: `curl -I https://home.7gram.xyz` → Not 500
- [ ] Audiobookshelf accessible: `curl -I https://audiobook.7gram.xyz` → Not 500
- [ ] SSL certificate valid: Browser shows secure lock icon

### SSL Verification
- [ ] Certificate issuer is Let's Encrypt: `echo | openssl s_client -connect 7gram.xyz:443 2>/dev/null | openssl x509 -noout -issuer`
- [ ] Certificate covers wildcards: `echo | openssl s_client -connect photo.7gram.xyz:443 2>/dev/null | openssl x509 -noout -text | grep DNS`
- [ ] Certificate valid for 90 days: Check expiry date
- [ ] No browser warnings on any subdomain

## Troubleshooting Quick Reference

### If SSL certificates not generated:
```bash
ssh freddy
cd ~/freddy
sudo ./scripts/cert-manager.sh request
./run.sh restart nginx
```

### If nginx won't start:
```bash
docker logs nginx
docker exec nginx nginx -t
./run.sh restart nginx
```

### If still getting 500 errors:
```bash
docker logs nginx | grep error
docker logs photoprism
docker logs nextcloud
./run.sh health
```

### Emergency rollback:
```bash
cd ~/freddy
./run.sh stop
git reset --hard HEAD~1
./run.sh start
```

## Success Criteria

All items below should be TRUE:

- ✅ Nginx container is running and healthy
- ✅ Let's Encrypt certificates are installed (not self-signed)
- ✅ All services accessible via HTTPS without browser warnings
- ✅ HTTP properly redirects to HTTPS
- ✅ No 500 errors on any service
- ✅ Health checks passing
- ✅ Certificate renewal timer is active: `sudo systemctl status freddy-cert-renewal.timer`

## Documentation

- [ ] Read `docs/SSL_SETUP.md` for detailed SSL information
- [ ] Read `docs/DEPLOYMENT_SUMMARY.md` for what changed
- [ ] Bookmark certificate manager: `scripts/cert-manager.sh`
- [ ] Note automatic renewal runs twice daily

---

**Deployment Date:** ________________

**Deployed By:** ________________

**Result:** ⬜ Success  ⬜ Partial  ⬜ Failed

**Notes:**