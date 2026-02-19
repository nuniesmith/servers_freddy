# Post-Deployment Verification Checklist

## 🎯 Overview

This guide helps you verify that your Freddy deployment was successful after the CI/CD pipeline completes.

## ✅ Immediate Checks (Right After Deployment)

### 1. Container Status

SSH to the server and check all containers:

```bash
ssh actions@<freddy-tailscale-ip>
cd ~/freddy
docker ps
```

**Expected Results:**
- All containers should show "Up" status
- nginx: `healthy`
- photoprism: `healthy` (after ~60 seconds)
- photoprism-postgres: `healthy`
- nextcloud: `healthy` (after ~2-3 minutes)
- nextcloud-postgres: `healthy`
- nextcloud-cron: `Up`
- homeassistant: `healthy`
- audiobookshelf: `healthy`

**⚠️ If Nextcloud shows "Restarting":**
This is NORMAL for the first 2-3 minutes after a database reset. Nextcloud is:
1. Detecting it's not installed
2. Running database migrations
3. Setting up the admin account
4. Installing default apps

Wait 3-5 minutes, then check again.

### 2. Nextcloud Initialization Logs

Check if Nextcloud installed successfully:

```bash
docker logs nextcloud 2>&1 | grep -A 5 "Nextcloud was successfully installed"
```

**Expected Output:**
```
Nextcloud was successfully installed
=> Searching for scripts (*.sh) to run, located in the folder "/docker-entrypoint-hooks.d/post-installation"
...
```

**⚠️ If you see "password authentication failed":**
The database reset didn't work. Check:
1. Was the workflow run with `reset_nextcloud_db` checked?
2. Did the pre-deploy step show "Nextcloud PostgreSQL data reset"?
3. Try manual reset: `./run.sh reset-nextcloud-db`

### 3. Nextcloud OCC Status

Verify Nextcloud is installed and operational:

```bash
./run.sh occ status
```

**Expected Output:**
```
  - installed: true
  - version: 30.0.x.x
  - versionstring: 30.0.x
  - edition: 
  - maintenance: false
  - needsDbUpgrade: false
  - productname: Nextcloud
  - extendedSupport: false
```

### 4. SSL Certificates

Verify certificates are in the Docker volume:

```bash
docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/
```

**Expected Output:**
```
lrwxrwxrwx    1 root     root            33 ... cert.pem -> ../../archive/7gram.xyz/cert1.pem
lrwxrwxrwx    1 root     root            34 ... chain.pem -> ../../archive/7gram.xyz/chain1.pem
lrwxrwxrwx    1 root     root            38 ... fullchain.pem -> ../../archive/7gram.xyz/fullchain1.pem
lrwxrwxrwx    1 root     root            36 ... privkey.pem -> ../../archive/7gram.xyz/privkey1.pem
```

Check certificate expiry:

```bash
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -dates
```

**Expected Output:**
```
notBefore=Feb 19 15:04:32 2025 GMT
notAfter=May 20 15:04:31 2026 GMT
```

## 🌐 Web Access Tests

### 1. Main Dashboard
Visit: **https://7gram.xyz** or **https://freddy.7gram.xyz**
- Should load without SSL warnings
- Should show nginx welcome page or dashboard

### 2. Nextcloud
Visit: **https://nc.7gram.xyz**
- Should redirect to HTTPS
- Should show Nextcloud login page
- Login with credentials from `.env`:
  - Username: `${NEXTCLOUD_ADMIN_USER}` (default: `admin`)
  - Password: `${NEXTCLOUD_ADMIN_PASSWORD}`

**After Login:**
- Dashboard should load
- No database errors
- Storage shows available space

### 3. PhotoPrism
Visit: **https://photo.7gram.xyz**
- Should load PhotoPrism interface
- Login with: `admin` / `${PHOTOPRISM_ADMIN_PASSWORD}`

### 4. Home Assistant
Visit: **https://home.7gram.xyz**
- Should load Home Assistant
- May need initial setup if fresh install

### 5. Audiobookshelf
Visit: **https://abs.7gram.xyz**
- Should load Audiobookshelf interface

## 🔧 Service Health Check

Run the built-in health check:

```bash
./run.sh health
```

**Expected Output:**
```
🏥 Freddy Health Check
✓ nginx: healthy
✓ photoprism: healthy
✓ nextcloud: healthy
✓ nextcloud-cron: running (no health check)
✓ homeassistant: healthy
✓ audiobookshelf: healthy
✓ photoprism-postgres: healthy
✓ nextcloud-postgres: healthy
```

## 📂 Nextcloud-Specific Checks (After Database Reset)

### 1. File Scan

If you had existing files, rescan them:

```bash
./run.sh occ files:scan --all
```

This re-indexes files that were preserved in `/mnt/1tb/nextcloud/data`.

### 2. Background Jobs

Verify cron is configured:

```bash
./run.sh occ config:system:get maintenance_window_start
./run.sh occ background:cron
```

### 3. Trusted Domains

Verify trusted domains are set:

```bash
./run.sh occ config:system:get trusted_domains
```

**Expected Output:**
```
0: nc.7gram.xyz
1: localhost
2: nextcloud
```

### 4. Preview Generators

Check preview providers are configured:

```bash
./run.sh occ config:system:get enabledPreviewProviders
```

## 🚨 Troubleshooting

### Nextcloud Keeps Restarting

**Check logs:**
```bash
docker logs nextcloud --tail 100
```

**Common issues:**
1. **Database password mismatch:** Reset didn't work - try manual reset
2. **Disk space full:** Check `df -h /mnt/1tb`
3. **Permissions issue:** Check ownership: `ls -la /mnt/1tb/nextcloud/`

**Fix permissions:**
```bash
docker run --rm -v /mnt/1tb:/mnt busybox chown -R 33:33 /mnt/nextcloud/html /mnt/nextcloud/data
```

### SSL Certificate Issues

**Check nginx logs:**
```bash
docker logs nginx
```

**Verify certificate file permissions:**
```bash
docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/
```

**Test nginx config:**
```bash
docker exec nginx nginx -t
```

### Database Connection Issues

**Check PostgreSQL:**
```bash
docker exec nextcloud-postgres pg_isready -U nextcloud
```

**Verify credentials match:**
```bash
# What Nextcloud sees
docker exec nextcloud env | grep POSTGRES

# What database expects
docker exec nextcloud-postgres env | grep POSTGRES
```

These should match!

## 📊 Performance Checks

### Disk Usage

```bash
df -h /mnt/1tb
```

Ensure you have sufficient space.

### Memory Usage

```bash
free -h
docker stats --no-stream
```

### Container Resource Usage

```bash
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

## 🔄 If Issues Persist

1. **Check full deployment logs** in GitHub Actions
2. **Review service logs:**
   ```bash
   ./run.sh logs nextcloud
   ./run.sh logs nginx
   ./run.sh logs photoprism
   ```
3. **Restart specific service:**
   ```bash
   ./run.sh restart nextcloud
   ```
4. **Full restart:**
   ```bash
   ./run.sh restart
   ```
5. **Nuclear option (reset everything):**
   ```bash
   ./run.sh stop
   # Back up important data first!
   ./run.sh reset-nextcloud-db
   ./run.sh start
   ```

## ✅ Success Indicators

Your deployment is successful when:

- [ ] All containers show "Up" and "healthy" status
- [ ] `./run.sh occ status` shows `installed: true`
- [ ] https://nc.7gram.xyz loads and you can login
- [ ] https://photo.7gram.xyz loads
- [ ] https://home.7gram.xyz loads
- [ ] https://abs.7gram.xyz loads
- [ ] No SSL certificate warnings in browser
- [ ] Nextcloud has no database errors
- [ ] All services respond within reasonable time

## 📚 Additional Resources

- Full deployment guide: `docs/QUICK_FIX.md`
- Nextcloud troubleshooting: `docs/NEXTCLOUD_DB_FIX.md`
- Service management: `./run.sh help`
- CI/CD workflow: `.github/workflows/ci-cd.yml`

## 🎉 Congratulations!

If all checks pass, your Freddy server is successfully deployed and running!

**Next steps:**
- Configure Nextcloud apps and settings
- Set up Home Assistant automations
- Import photos to PhotoPrism
- Add audiobooks to Audiobookshelf
- Set up automated backups