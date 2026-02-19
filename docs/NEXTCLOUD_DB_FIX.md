# Nextcloud Database Password Authentication Fix

## Problem

Nextcloud is failing to connect to PostgreSQL with the error:

```
FATAL: password authentication failed for user "nextcloud"
```

This occurs when the PostgreSQL database was initialized with different credentials than what's currently configured in the environment variables.

## Root Cause

PostgreSQL only uses the `POSTGRES_PASSWORD` environment variable during **initial database creation**. Once the database exists, the password is stored in PostgreSQL's internal data and the environment variable is ignored.

This mismatch happens when:
1. The database volume already exists from a previous deployment
2. Environment variables (`.env` file) were changed but the database wasn't reset
3. Fresh code was deployed but old database volume persists

## Solutions

### Option A: Reset Database via GitHub Actions (Recommended for CI/CD)

Trigger a deployment with the database reset flag:

1. Go to **Actions** → **Freddy Deploy** → **Run workflow**
2. Check the box: **"Reset Nextcloud PostgreSQL database"**
3. Click **Run workflow**

This will:
- Stop Nextcloud containers
- Delete PostgreSQL data
- Restart services with fresh database using current credentials

**⚠️ Warning:** This deletes all Nextcloud database data (users, shares, settings). User files in `/mnt/1tb/nextcloud/data` are preserved.

### Option B: Manual Reset via Server (SSH)

SSH into the Freddy server and run:

```bash
cd ~/freddy
./run.sh reset-nextcloud-db
```

Follow the prompts to confirm the reset.

### Option C: Manual Reset (Advanced)

If you prefer manual steps:

```bash
# 1. Stop containers
cd ~/freddy
docker stop nextcloud nextcloud-cron nextcloud-postgres
docker rm nextcloud nextcloud-cron nextcloud-postgres

# 2. Delete PostgreSQL data
sudo rm -rf /mnt/1tb/nextcloud/postgres/*

# 3. Restart services
./run.sh start
```

## Verification

After resetting the database:

1. **Check container status:**
   ```bash
   docker ps
   ```
   All containers should show "Up" status

2. **Check Nextcloud logs:**
   ```bash
   docker logs nextcloud
   ```
   Should see: "Starting nextcloud installation" → "Nextcloud was successfully installed"

3. **Verify Nextcloud works:**
   ```bash
   ./run.sh occ status
   ```
   Should show: "installed: true"

4. **Access Nextcloud:**
   - Visit: https://nc.7gram.xyz
   - Login with credentials from `.env`:
     - Username: `${NEXTCLOUD_ADMIN_USER}` (default: `admin`)
     - Password: `${NEXTCLOUD_ADMIN_PASSWORD}`

## Prevention

To avoid this issue in the future:

1. **Keep environment variables consistent** - Don't change database passwords after initial deployment
2. **Document credential changes** - If you must change passwords, also reset the database
3. **Use GitHub Actions reset flag** - Always available when deploying after credential changes

## Technical Details

### Environment Variables Used

The following variables control Nextcloud database authentication:

```bash
# In .env file:
NEXTCLOUD_DB_NAME=nextcloud          # Database name
NEXTCLOUD_DB_USER=nextcloud          # Database username  
NEXTCLOUD_DB_PASSWORD=changeme       # Database password (MUST match what's in PostgreSQL)
NEXTCLOUD_ADMIN_USER=admin           # Nextcloud admin username
NEXTCLOUD_ADMIN_PASSWORD=changeme    # Nextcloud admin password
```

### Docker Compose Configuration

From `docker-compose.yml`:

```yaml
nextcloud:
  environment:
    - POSTGRES_HOST=nextcloud-postgres
    - POSTGRES_DB=${NEXTCLOUD_DB_NAME:-nextcloud}
    - POSTGRES_USER=${NEXTCLOUD_DB_USER:-nextcloud}
    - POSTGRES_PASSWORD=${NEXTCLOUD_DB_PASSWORD:-changeme}

nextcloud-postgres:
  environment:
    - POSTGRES_DB=${NEXTCLOUD_DB_NAME:-nextcloud}
    - POSTGRES_USER=${NEXTCLOUD_DB_USER:-nextcloud}
    - POSTGRES_PASSWORD=${NEXTCLOUD_DB_PASSWORD:-changeme}
```

Both services must use the **exact same** credentials.

## FAQ

### Q: Will I lose my files?

**A:** No. User files stored in `/mnt/1tb/nextcloud/data` are **not affected**. Only the database (users, shares, app settings) is reset.

### Q: Do I need to re-upload files?

**A:** No. Files remain on disk. However, you'll need to:
1. Create users again (or use admin account)
2. Reconfigure shares and permissions
3. Run file scan: `./run.sh occ files:scan --all`

### Q: Can I change the password without losing data?

**A:** Yes, but it requires connecting to PostgreSQL and running SQL commands:

```bash
docker exec -it nextcloud-postgres psql -U nextcloud -d nextcloud -c \
  "ALTER USER nextcloud WITH PASSWORD 'new_password_here';"
```

Then update `.env` to match and restart containers.

### Q: How do I backup before resetting?

**A:** Export the database:

```bash
docker exec nextcloud-postgres pg_dump -U nextcloud nextcloud > nextcloud_backup.sql
```

To restore later:

```bash
cat nextcloud_backup.sql | docker exec -i nextcloud-postgres psql -U nextcloud -d nextcloud
```

## Related Files

- Workflow: `.github/workflows/ci-cd.yml` (contains database reset logic)
- Management script: `run.sh` (contains `reset-nextcloud-db` command)
- Docker Compose: `docker-compose.yml` (defines services and environment)
- Environment: `.env` (contains credentials - not in git)

## Support

If issues persist after database reset:

1. Check environment variables are loaded:
   ```bash
   docker exec nextcloud env | grep POSTGRES
   ```

2. Check PostgreSQL is healthy:
   ```bash
   docker exec nextcloud-postgres pg_isready -U nextcloud
   ```

3. View detailed Nextcloud initialization logs:
   ```bash
   docker logs nextcloud 2>&1 | grep -A 20 "Starting nextcloud installation"
   ```

4. Verify database credentials match:
   ```bash
   # In .env file
   echo $NEXTCLOUD_DB_PASSWORD
   
   # What Nextcloud sees
   docker exec nextcloud env | grep POSTGRES_PASSWORD
   ```

If all else fails, check the main troubleshooting docs or contact the team.