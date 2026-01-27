# Nextcloud LDAP Integration with Authentik

Guide for integrating Nextcloud with Authentik's LDAP provider for centralized authentication and user provisioning.

## Overview

Nextcloud has robust LDAP/AD integration through its **LDAP user and group backend** app, enabling:
- Single sign-on with Authentik credentials
- Automatic user provisioning
- Group synchronization
- User attribute mapping

**Architecture:**
- Nextcloud on FREDDY connects to Authentik LDAP (localhost)
- LDAPS connection over port 636 (encrypted)
- Automatic user/group synchronization
- Seamless integration with existing local users

## Prerequisites

1. **Authentik LDAP provider configured on FREDDY**
   - See: `freddy/services/authentik/LDAP-SETUP.md`
   - LDAP outpost running on port 636
   - Base DN: `dc=7gram,dc=xyz`
   - Service account: `cn=ldapservice,ou=users,dc=7gram,dc=xyz`

2. **Nextcloud admin access**
   - Admin user with access to Apps management
   - Access to Nextcloud settings

3. **Test LDAP connection**
   ```bash
   # Test from FREDDY (same host)
   ldapsearch -x -H ldaps://localhost:636 \
     -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
     -w '<service-account-password>' \
     -b "dc=7gram,dc=xyz" \
     "(objectClass=user)"
   ```

## Installation Steps

### Step 1: Install LDAP App

1. **Login to Nextcloud as admin**:
   - Navigate to: https://nc.7gram.xyz

2. **Enable LDAP app**:
   - Click: **User icon (top-right)** → **Apps**
   - Search for: **LDAP user and group backend**
   - Click: **Enable**

   Or via command line:
   ```bash
   # Enable LDAP app
   docker compose exec -u www-data nextcloud php occ app:enable user_ldap
   ```

3. **Verify app enabled**:
   - Go to: **Settings** → **Administration** → **LDAP / AD integration**
   - Should see LDAP configuration page

### Step 2: Configure LDAP Server Connection

1. **Access LDAP settings**:
   - **Settings** → **Administration** → **LDAP / AD integration**

2. **Create new LDAP configuration**:
   - Click: **Add Server Configuration** (if first time)

3. **Server tab configuration**:

   **Host:**
   - **Server**: `localhost` or `authentik-ldap-outpost`
   - **Port**: `636`
   - **User DN**: `cn=ldapservice,ou=users,dc=7gram,dc=xyz`
   - **Password**: `<service-account-password>`
   - **Base DN**: `dc=7gram,dc=xyz`

   **Connection Settings:**
   - **Configuration Active**: ✅ **Checked**
   - **Disable Main Server**: ❌ **Unchecked**
   - **Turn off SSL certificate validation**: ❌ **Unchecked** (use valid cert)
   - **Case insensitive LDAP server**: ❌ **Unchecked**

4. **Test connection**:
   - Click: **Test Base DNs**
   - Should show: **Configuration OK**

### Step 3: Configure User Filters

1. **Users tab**:

   **Edit LDAP Query:**
   - Click: **Edit LDAP Query** (to use raw filter)
   - Enter: `(objectClass=user)`
   - Click: **Verify settings and count users**
   - Should show: Number of users found (e.g., "5 users found")

   **User Attributes:**
   - Nextcloud will automatically detect which attributes to use
   - Or manually set:
     - **LDAP Username Attribute**: `uid`
     - **Additional User Attributes**: `cn,mail,displayName,givenName,sn`

2. **Click**: **Continue**

### Step 4: Configure Login Attributes

1. **Login Attributes tab**:

   **LDAP / AD Username:**
   - Select: ✅ **LDAP / AD Username** (uid)
   - Or: ✅ **LDAP / AD Email Address** (mail)

   **Other Attributes:**
   - Can also enable:
     - **LDAP / AD Display Name** (displayName)
   
   This determines what users enter at login (username vs email).

2. **Test login filter**:
   - Enter a test username (e.g., `jordan`)
   - Click: **Verify settings**
   - Should show: **User found and settings verified**

### Step 5: Configure Group Filters

1. **Groups tab**:

   **Edit LDAP Query:**
   - Click: **Edit LDAP Query**
   - Enter: `(objectClass=group)`
   - Click: **Verify settings and count groups**
   - Should show: Number of groups found

   **Group Attributes:**
   - **Group member association**: `member` (default)
   - Nextcloud auto-detects this

2. **Optional**: Restrict to specific groups
   - To only sync certain groups, use filter like:
   - `(&(objectClass=group)(cn=nextcloud-*))`
   - This would only sync groups starting with "nextcloud-"

### Step 6: Configure Advanced Settings

1. **Advanced tab**:

   **Directory Settings:**
   - **Base User Tree**: `ou=users,dc=7gram,dc=xyz`
   - **Base Group Tree**: `ou=groups,dc=7gram,dc=xyz`
   - **Group-Member association**: `member`
   - **Dynamic Group Member URL**: (leave empty)

   **Special Attributes:**
   - **Email Field**: `mail`
   - **User Display Name Field**: `displayName`
   - **2nd User Display Name Field**: `cn`
   - **User Home Folder Naming Rule**: (leave empty for default)
   - **Quota Field**: (leave empty)
   - **Quota Default**: (leave empty)

   **User Backend:**
   - **Default LDAP User Backend**: Leave as default
   - Allows LDAP users to change passwords via Nextcloud

2. **Click**: **Save**

### Step 7: Configure Expert Settings (Optional)

1. **Expert tab**:

   **Internal Username Attribute:**
   - **Internal Username**: `uid`
   - This is the attribute used internally by Nextcloud

   **Override UUID detection:**
   - Leave empty (auto-detect)

   **Username-LDAP User Mapping:**
   - Shows internal mapping of Nextcloud users to LDAP users
   - Can clear mapping to force re-sync

2. **Connection timeout:**
   - **Timeout**: `15` seconds (default)

3. **Caching:**
   - **Cache Time-To-Live**: `600` seconds (10 minutes)

## Verification and Testing

### Test LDAP User Login

1. **Open incognito/private browser window**
2. **Navigate to**: https://nc.7gram.xyz
3. **Login with LDAP credentials**:
   - Username: `<authentik-username>` (e.g., `jordan`)
   - Password: `<authentik-password>`
4. **Should login successfully**

### Verify User Created

1. **As admin, go to**: **Settings** → **Users**
2. **Should see LDAP users listed**
3. **Backend column**: Shows **LDAP**

### Test Group Synchronization

1. **Create group in Authentik**: `nextcloud-admins`
2. **Add user to group**
3. **In Nextcloud, go to**: **Settings** → **Users**
4. **Filter by Groups**: Should see **nextcloud-admins** group
5. **Users in group**: Should show users from LDAP

### Verify User Attributes

1. **Click on LDAP user**
2. **Check user details**:
   - **Display Name**: Should match `displayName` from LDAP
   - **Email**: Should match `mail` from LDAP
   - **Groups**: Should show LDAP groups

## User Management

### Automatic User Provisioning

When LDAP user logs in for first time:
1. Nextcloud queries LDAP for user
2. Creates local user account automatically
3. Maps user attributes (name, email)
4. Synchronizes group memberships
5. Grants access based on group permissions

### Manual User Synchronization

Force user/group sync:

```bash
# Sync LDAP users and groups
docker compose exec -u www-data nextcloud php occ ldap:update-user-mappings

# Check LDAP configuration
docker compose exec -u www-data nextcloud php occ ldap:show-config

# Test LDAP user search
docker compose exec -u www-data nextcloud php occ ldap:search jordan
```

### Disable LDAP Users

**Option 1: Disable in Authentik**
- Disable user in Authentik
- User can't login to Nextcloud anymore
- User data remains in Nextcloud

**Option 2: Remove from Nextcloud**
- Admin can disable user in Nextcloud
- User remains in LDAP but can't access Nextcloud

### Quota Management via LDAP

Set user quotas via LDAP attribute:

1. **Add custom attribute in Authentik**: `nextcloudQuota`
2. **Set value**: `5 GB`, `10 GB`, `unlimited`, etc.
3. **Configure in Nextcloud**:
   - **Expert** tab → **Quota Field**: `nextcloudQuota`
   - **Quota Default**: `5 GB`
4. **Sync users**: Quotas will be applied

## Migration from Local Users

### Strategy 1: Keep Both (Recommended)

- Keep existing local users as-is
- Add LDAP authentication for new users
- Gradually migrate local users to LDAP

**Pros:**
- No disruption to existing users
- Gradual migration
- Rollback easy

**Cons:**
- Two authentication methods

### Strategy 2: Migrate to LDAP Only

1. **Create matching LDAP users in Authentik**:
   - Use same usernames as local users
   - Preserve user home folders

2. **Merge local users with LDAP users**:
   ```bash
   # Map local user to LDAP user (requires matching usernames)
   docker compose exec -u www-data nextcloud php occ ldap:set-user-mapping <local-username> <ldap-username>
   ```

3. **Verify user data preserved**:
   - Files, shares, settings should remain

4. **Disable local authentication** (optional):
   - Admin → Settings → Apps
   - Disable local user backend

### Test Migration

1. Create test LDAP user in Authentik
2. Login to Nextcloud as LDAP user
3. Upload files, create shares
4. Verify everything works
5. Proceed with full migration

## Group-Based Access Control

### Restrict Nextcloud Access

**Option 1: LDAP Group Filter**

Only sync specific groups:
```
# Groups tab filter
(&(objectClass=group)(cn=nextcloud-users))
```

Only users in `nextcloud-users` group will sync.

**Option 2: Nextcloud Group Restriction**

1. **Admin Settings** → **Basic settings**
2. **Enable**: **Limit to groups**
3. **Select groups**: `nextcloud-users`, `nextcloud-admins`
4. Only users in these groups can login

### Admin Privileges via LDAP Group

Grant admin rights based on LDAP group:

1. **Create group in Authentik**: `nextcloud-admins`
2. **Add users to group**
3. **In Nextcloud**:
   - **Settings** → **Users**
   - **Select user**
   - **Add to group**: `admin`
   - Or configure auto-mapping

**Auto-mapping LDAP group to admin:**
- Not directly supported in Nextcloud
- Workaround: Use app like **Group Backend** or manual mapping

## Troubleshooting

### LDAP Connection Failed

**Symptom**: "Can't connect to LDAP server"

**Diagnosis:**
```bash
# Test LDAP from Nextcloud container
docker compose exec nextcloud nc -zv localhost 636

# Test LDAP bind
docker compose exec nextcloud ldapsearch -x -H ldaps://localhost:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz"
```

**Solutions:**
- Verify LDAP outpost running: `docker ps | grep ldap`
- Check Nextcloud can reach LDAP host
- Verify firewall allows port 636
- Check DNS resolution: `docker compose exec nextcloud nslookup authentik-ldap-outpost`

### No Users Found

**Symptom**: "0 users found" when testing filter

**Common causes:**
- Wrong base DN
- Search filter doesn't match any users
- Service account lacks read permissions

**Solutions:**
- Verify base DN: `dc=7gram,dc=xyz`
- Test search filter manually:
  ```bash
  ldapsearch -x -H ldaps://localhost:636 \
    -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
    -w '<password>' \
    -b "dc=7gram,dc=xyz" \
    "(objectClass=user)"
  ```
- Ensure service account has read permissions in Authentik

### User Login Failed

**Symptom**: LDAP user can't login, "Wrong username or password"

**Diagnosis:**
```bash
# Test user authentication
docker compose exec -u www-data nextcloud php occ ldap:search <username>

# Check LDAP logs
docker compose logs authentik-ldap-outpost | grep -i error
```

**Common causes:**
- Wrong username format (should match login attribute)
- User doesn't exist in LDAP
- User disabled in Authentik
- Login attributes misconfigured

**Solutions:**
- Verify user exists: Check Authentik → Directory → Users
- Test login with exact username (case-sensitive)
- Check login attributes configuration in LDAP settings
- Verify user not disabled in Authentik

### SSL Certificate Errors

**Symptom**: "SSL certificate validation failed"

**Options:**
1. **Use valid certificate** (recommended):
   - Configure valid SSL cert in Authentik LDAP outpost

2. **Disable certificate validation** (testing only):
   - LDAP settings → **Turn off SSL certificate validation**: ✅ **Check**
   - Only for testing/dev environments

### User Attributes Not Syncing

**Symptom**: User email or display name empty

**Diagnosis:**
```bash
# Check user attributes from LDAP
ldapsearch -x -H ldaps://localhost:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(uid=jordan)" \
  uid cn mail displayName
```

**Solutions:**
- Verify attributes exist in Authentik user profile
- Configure attribute mapping in LDAP Advanced tab:
  - **Email Field**: `mail`
  - **User Display Name Field**: `displayName`
- Force user re-sync:
  ```bash
  docker compose exec -u www-data nextcloud php occ ldap:update-user-mappings
  ```

## Command-Line Management

### Useful occ Commands

```bash
# Show LDAP configuration
docker compose exec -u www-data nextcloud php occ ldap:show-config

# Test LDAP connectivity
docker compose exec -u www-data nextcloud php occ ldap:test-config

# Search for LDAP user
docker compose exec -u www-data nextcloud php occ ldap:search jordan

# Force user/group sync
docker compose exec -u www-data nextcloud php occ ldap:update-user-mappings

# Show user details
docker compose exec -u www-data nextcloud php occ user:info jordan

# Check LDAP backend status
docker compose exec -u www-data nextcloud php occ ldap:check-user jordan

# Clear LDAP cache
docker compose exec -u www-data nextcloud php occ ldap:invalidate-cache
```

### Debugging LDAP Issues

Enable LDAP debug logging:

```bash
# Enable debug logging
docker compose exec -u www-data nextcloud php occ config:system:set loglevel --value=0

# View logs
docker compose exec -u www-data nextcloud tail -f /var/www/html/data/nextcloud.log | grep -i ldap

# Disable debug logging (set back to warnings)
docker compose exec -u www-data nextcloud php occ config:system:set loglevel --value=2
```

## Security Considerations

### Use LDAPS (Port 636)

Always use encrypted LDAPS:
- Protects credentials in transit
- Prevents packet sniffing
- Required for production

### Service Account Permissions

LDAP service account should have:
- **Read-only** access to users and groups
- **No write** permissions
- **No admin** privileges

### Credential Storage

Bind password stored in Nextcloud database:
- Encrypted at rest
- Protect database backups
- Rotate password periodically

### User Session Management

- LDAP authentication doesn't affect session timeout
- Configure session lifetime in Nextcloud settings
- Consider enabling two-factor authentication

## Performance Optimization

### LDAP Caching

Nextcloud caches LDAP results:
- **Cache TTL**: 600 seconds (default)
- Reduces LDAP queries
- Configure in **Expert** tab

### Scheduled User Sync

Run periodic user sync via cron:

```bash
# Add to crontab
0 */6 * * * docker compose exec -u www-data nextcloud php occ ldap:update-user-mappings
```

Sync every 6 hours to keep users/groups updated.

### Pagination for Large Directories

For many users/groups (>1000):

1. **Expert** tab → **Enable pagination**: ✅ **Check**
2. **Page size**: `500`
3. Improves performance with large LDAP directories

## Quick Reference

### LDAP Configuration Summary

```
Server: localhost (or authentik-ldap-outpost)
Port: 636
Secure: Yes (LDAPS)
Bind DN: cn=ldapservice,ou=users,dc=7gram,dc=xyz
Base DN: dc=7gram,dc=xyz
User Filter: (objectClass=user)
Group Filter: (objectClass=group)
Username Attribute: uid
Login Attribute: uid or mail
Email Attribute: mail
Display Name: displayName
Auto-create users: Yes
```

### Testing Checklist

- [ ] LDAP app installed and enabled
- [ ] Server connection configured and tested
- [ ] User filter configured (users found)
- [ ] Group filter configured (groups found)
- [ ] Login attributes configured
- [ ] Test LDAP user can login
- [ ] User created in Nextcloud
- [ ] User attributes populated (name, email)
- [ ] Groups synchronized
- [ ] User can access files/apps
- [ ] LDAP logs show no errors

---

**Document Version**: 1.0  
**Last Updated**: October 20, 2025  
**Status**: Ready for deployment  
**Related**: `freddy/services/authentik/LDAP-SETUP.md`, `sullivan/services/emby/LDAP-INTEGRATION.md`, `sullivan/services/jellyfin/LDAP-INTEGRATION.md`
