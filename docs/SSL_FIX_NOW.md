# 🚨 IMMEDIATE SSL FIX - Nginx Restarting Issue

**Current Problem:** Your nginx container is stuck in a restart loop with error:
```
[ERROR] Certificate and private key do not match!
```

## ✅ Quick Fix (5 minutes)

SSH into your Freddy server and run:

```bash
# 1. Run the automated fix script
sudo ~/freddy/scripts/fix-ssl-mismatch.sh

# That's it! The script will:
# - Diagnose the issue
# - Copy good certificates from Let's Encrypt
# - Restart nginx
# - Verify it's working
```

### If that doesn't work...

```bash
# 2. Manual fix - copy certificates directly
sudo su
cd /opt/ssl/7gram.xyz

# Backup current certs
cp fullchain.pem fullchain.pem.backup
cp privkey.pem privkey.pem.backup

# Copy from Let's Encrypt (with -L to follow symlinks)
cp -L /etc/letsencrypt/live/7gram.xyz/fullchain.pem .
cp -L /etc/letsencrypt/live/7gram.xyz/privkey.pem .

# Set permissions
chmod 644 fullchain.pem
chmod 600 privkey.pem
chown actions:actions fullchain.pem privkey.pem

# Restart nginx
docker restart nginx

# Check status
sleep 5
docker ps | grep nginx
```

## 🔍 Verify It's Fixed

```bash
# Nginx should show "Up" (not "Restarting")
docker ps | grep nginx

# Should output something like:
# nginx    Up 10 seconds (healthy)   0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
```

## 🧪 Test It Works

```bash
# From the server
curl -k https://localhost/health

# Should return: OK

# From your browser
# Visit: https://7gram.xyz/
```

## 📊 What Was The Problem?

The certificate file (`fullchain.pem`) and private key file (`privkey.pem`) in `/opt/ssl/7gram.xyz/` didn't match. This happens when:
- Certificates were regenerated but files got mixed up
- One file was updated but not the other
- Manual file operations copied from different sources

## 🛡️ Prevention

Moving forward:
1. **Always use the GitHub Actions workflow** to update certificates
2. **Never manually copy certificate files** unless absolutely necessary
3. **Use the fix script** if you need to manually fix: `~/freddy/scripts/fix-ssl-mismatch.sh`

## 🔧 Alternative: Regenerate Everything

If the quick fix doesn't work, regenerate certificates from scratch:

### Option A: Via GitHub Actions (Recommended)

1. Go to: https://github.com/YOUR_USERNAME/servers_freddy/actions
2. Click "🏠 Freddy Deploy"
3. Click "Run workflow"
4. Check "Update DNS records"
5. Click "Run workflow"

Wait 5-10 minutes for deployment to complete.

### Option B: Locally on Server

```bash
cd ~/freddy
./run.sh ssl-init --force
```

## 🆘 Still Not Working?

Run the diagnostic to see detailed info:

```bash
sudo ~/freddy/scripts/fix-ssl-mismatch.sh --check-only
```

This will show you exactly what's wrong with the certificates.

### Common Issues:

**Issue:** Let's Encrypt certificates also don't match
```bash
# Solution: Regenerate with certbot
cd ~/freddy
./run.sh ssl-init --force
```

**Issue:** Permissions denied
```bash
# Solution: Fix permissions
sudo chown -R actions:actions /opt/ssl/7gram.xyz
sudo chmod 750 /opt/ssl/7gram.xyz
sudo chmod 644 /opt/ssl/7gram.xyz/fullchain.pem
sudo chmod 600 /opt/ssl/7gram.xyz/privkey.pem
```

**Issue:** Files don't exist in Let's Encrypt directory
```bash
# Solution: Check if certbot has any certs
sudo ls -la /etc/letsencrypt/live/

# If empty, regenerate via CI/CD or:
cd ~/freddy
./run.sh ssl-init --force
```

## 📝 What Changed?

We've improved the nginx entrypoint script to provide better diagnostics:
- More detailed error messages
- Certificate matching verification
- Shows where the mismatch is occurring
- Provides debugging information

## 📚 More Info

- Full troubleshooting guide: [`docs/TROUBLESHOOTING_SSL.md`](TROUBLESHOOTING_SSL.md)
- SSL setup guide: [`docs/SSL_SETUP.md`](SSL_SETUP.md)
- Deployment guide: [`docs/DEPLOYMENT_SUMMARY.md`](DEPLOYMENT_SUMMARY.md)

---

**Need Help?** Check the nginx logs: `docker logs nginx`
