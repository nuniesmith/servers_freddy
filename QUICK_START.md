# 🚀 Quick Start Guide - Deploy Immediately

Get your Freddy server up and running with SSL certificates in under 10 minutes.

## ✅ Pre-Flight Check (2 minutes)

### 1. Verify GitHub Secrets

Go to: `https://github.com/YOUR_USERNAME/servers_freddy/settings/secrets/actions`

**Required secrets:**
- [ ] `CLOUDFLARE_EMAIL` - Your Cloudflare account email
- [ ] `CLOUDFLARE_API_KEY` - Get from [Cloudflare Dashboard → API Tokens](https://dash.cloudflare.com/profile/api-tokens)
- [ ] `FREDDY_TAILSCALE_IP` - Your server's Tailscale IP
- [ ] `SSH_KEY` - SSH private key for server access
- [ ] `SSH_USER` - SSH username (default: actions)

**Optional:**
- [ ] `CERTBOT_EMAIL` - Defaults to CLOUDFLARE_EMAIL if not set

### 2. Test Locally (2 minutes)

```bash
cd ~/github/servers_freddy

# Build nginx
docker build -f docker/nginx/Dockerfile -t freddy-nginx:test .

# Test it
docker run --rm -d --name nginx-test -p 8080:80 -p 8443:443 freddy-nginx:test
sleep 2
curl http://localhost:8080/health  # Should return: OK
curl -k https://localhost:8443/health  # Should return: OK

# Cleanup
docker stop nginx-test
```

**✅ If both health checks return "OK", you're ready to deploy!**

## 🚀 Deploy (3 minutes)

### Push to Main Branch

```bash
cd ~/github/servers_freddy

# Stage all changes
git add .

# Commit with descriptive message
git commit -m "Fix nginx SSL certificate management

- Add automated SSL certificate generation with Cloudflare DNS
- Improve nginx configuration and error handling
- Add health check endpoints
- Fix HTTP to HTTPS redirects
- Add comprehensive SSL documentation"

# Push to trigger deployment
git push origin main
```

### Watch Deployment

1. Go to: `https://github.com/YOUR_USERNAME/servers_freddy/actions`
2. Click on the latest workflow run
3. Watch these stages:
   - ✅ DNS Update (updates Cloudflare records)
   - ✅ Deploy (generates SSL certs, deploys services)
   - ✅ Health Checks (verifies all services)

**Expected time:** 5-10 minutes

## ✅ Verify Deployment (3 minutes)

### Quick Checks

```bash
# From your local machine
curl https://7gram.xyz
# Should return: Freddy Server dashboard HTML

curl -I https://photo.7gram.xyz
curl -I https://nc.7gram.xyz
curl -I https://home.7gram.xyz
curl -I https://abs.7gram.xyz
# All should return: 200 OK or 302 (not 500!)
```

### Server Checks (SSH to server)

```bash
ssh your-server

# Check certificates exist
ls -la /opt/ssl/7gram.xyz/
# Should show: fullchain.pem, privkey.pem

# Check nginx is healthy
docker ps | grep nginx
# Should show: (healthy)

# Check certificate issuer
openssl x509 -in /opt/ssl/7gram.xyz/fullchain.pem -noout -issuer
# Should show: Let's Encrypt

# Check service status
cd ~/freddy
./run.sh health
# Should show all services healthy
```

## 🎉 Success Indicators

You know everything is working when:

✅ No browser SSL warnings on https://7gram.xyz  
✅ All services return 200/302 (not 500)  
✅ Certificate issuer is "Let's Encrypt"  
✅ Nginx container shows "healthy" status  
✅ All services pass health checks  

## 🐛 Quick Troubleshooting

### Issue: "Self-signed certificate warning in browser"

**Fix:**
```bash
ssh your-server
cd ~/freddy
sudo ./scripts/cert-manager.sh upgrade
./run.sh restart nginx
```

### Issue: "Still getting 500 errors"

**Check:**
```bash
# View nginx logs
docker logs nginx | tail -50

# Check backend service logs
docker logs photoprism
docker logs nextcloud

# Verify all services running
docker ps
```

### Issue: "CI/CD deployment failed"

**Common causes:**
1. Missing GitHub secrets → Add them in repository settings
2. Invalid Cloudflare API key → Verify at dash.cloudflare.com
3. SSH connection failed → Check SSH_KEY and server accessibility

**View logs:** Go to GitHub Actions and check the failed step

## 📚 Next Steps

After successful deployment:

1. **Set up automatic renewal monitoring:**
   ```bash
   sudo systemctl status freddy-cert-renewal.timer
   ```

2. **Read full documentation:**
   - [SSL Setup Guide](docs/SSL_SETUP.md) - Complete SSL management
   - [Deployment Summary](docs/DEPLOYMENT_SUMMARY.md) - What changed
   - [Deployment Checklist](DEPLOYMENT_CHECKLIST.md) - Detailed verification

3. **Bookmark useful commands:**
   ```bash
   ./scripts/cert-manager.sh check    # Check certificate status
   ./run.sh health                     # Check service health
   docker logs nginx                   # View nginx logs
   ```

## 🆘 Need Help?

- **SSL Issues:** See [docs/SSL_SETUP.md](docs/SSL_SETUP.md#troubleshooting)
- **Deployment Issues:** See [docs/DEPLOYMENT_SUMMARY.md](docs/DEPLOYMENT_SUMMARY.md#troubleshooting)
- **Service Issues:** Check service logs with `docker logs [service_name]`

---

**Total Time:** ~10 minutes from start to verified deployment

**What You Get:**
- ✅ Automated Let's Encrypt SSL certificates
- ✅ Wildcard domain coverage (*.7gram.xyz)
- ✅ Auto-renewal every 90 days
- ✅ HTTP → HTTPS redirects
- ✅ All services secured with HTTPS
- ✅ No more 500 errors!