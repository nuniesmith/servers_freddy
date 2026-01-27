# Nextcloud Sync Exclusions Guide

## Overview
This guide explains how to configure the Nextcloud desktop client to skip syncing specific files and directories using ignore patterns. This is particularly useful for excluding development artifacts, build directories, and temporary files.

## Quick Start

### Method 1: Using the Desktop Client GUI (Recommended)
1. Open the Nextcloud desktop client
2. Click your account avatar or settings icon (system tray/menu bar)
3. Go to **Settings** → **General** tab
4. Click **Edit Ignored Files**
5. Add your custom patterns (one per line) at the bottom
6. Save and restart the client or force a sync

### Method 2: Manual File Editing
Directly edit the `sync-exclude.lst` file in your client's configuration directory:

**Linux:**
```bash
nano ~/.config/Nextcloud/sync-exclude.lst
```

**Windows:**
```cmd
notepad %APPDATA%\Nextcloud\sync-exclude.lst
```

**macOS:**
```bash
nano ~/Library/Application\ Support/Nextcloud/sync-exclude.lst
```

After editing, restart the Nextcloud client or force a re-sync.

## Recommended Patterns

### Essential Development Exclusions
Add these patterns to skip common development artifacts:

```
# Git internals
.git/objects/*

# Python virtual environments
.venv/
venv/

# Rust build artifacts
target/
.cargo/

# Node.js dependencies
node_modules/
```

### Pattern Syntax
- `*` - Matches any characters (e.g., `*.log` matches all log files)
- `?` - Matches a single character
- `/` at end - Matches directories (e.g., `target/` matches any target directory)
- Patterns are **case-sensitive**
- Patterns match recursively at any depth in your sync tree

### Broader Matching
If basic patterns don't work (due to nested paths), try:
- `*/.git/objects/*` - Matches .git/objects in any subdirectory
- `*/target/` - Matches target directory at any level
- `*/.venv/` - Matches .venv anywhere in the tree

## Common Use Cases

### Syncing Home Directory
If syncing your entire home directory, be specific with paths:
```
.local/share/Trash/
.cache/
.mozilla/
.thunderbird/
Downloads/
```

**Warning:** Avoid syncing entire home directory if possible - use selective sync folders instead.

### Development Projects
For code repositories with heavy build artifacts:
```
# Language-specific
__pycache__/
*.pyc
target/
node_modules/
.gradle/
build/

# IDE files
.idea/
.vscode/
*.swp
```

### Large Media Projects
```
*.iso
*.dmg
*.vmdk
*.vdi
Thumbs.db
.DS_Store
```

## Testing Your Patterns

1. **Start small:** Test patterns on a non-critical sync folder first
2. **Check status:** Ignored items show a warning icon in your file manager
3. **Verify:** Use the client's activity log to confirm files are skipped
4. **Iterate:** Adjust patterns if they don't match as expected

## Alternative: Selective Sync

Instead of using ignore patterns, you can configure **selective sync** to only include specific folders:

1. Open Nextcloud client settings
2. Go to **Account** → **Folder Sync Connection**
3. Click **Add Folder**
4. Choose specific subdirectories to sync
5. Uncheck unwanted top-level folders

This bypasses unwanted content entirely without pattern matching.

## Troubleshooting

### Patterns Not Applying
- **Update client:** Older versions have bugs with ignore lists
- **Restart required:** Changes may not apply until client restart
- **Check syntax:** Ensure no typos or invalid wildcards
- **Path separators:** Use `/` even on Windows (client handles conversion)

### Hidden Files Not Syncing
1. Go to Settings → **Advanced**
2. Enable **Sync hidden files** if needed
3. Then use ignore patterns to exclude specific hidden items

### Global vs. User Config
- **Don't edit:** Installation directory's `sync-exclude.lst` (system-wide)
- **Do edit:** User config directory's `sync-exclude.lst` (your custom patterns)
- Mixing the two can cause conflicts

## Server-Side Exclusions (Advanced)

While this guide focuses on client-side exclusions, server administrators can also configure `.user.ini` or `.htaccess` rules to prevent certain files from being uploaded. However, this is not recommended for personal use cases.

## Reference Files

- `sync-exclude.lst` - Template file with common patterns (in this directory)
- See Nextcloud desktop client documentation for pattern syntax updates

## Tips

- The client already ignores many temp files by default (`~*`, `.tmp`, lock files)
- Prefix patterns with specific paths to avoid over-matching
- Test on a small folder before applying to large sync trees
- Monitor sync activity log after adding new patterns
- Keep a backup of your working `sync-exclude.lst`

## Example Workflow

```bash
# 1. Backup current config
cp ~/.config/Nextcloud/sync-exclude.lst ~/.config/Nextcloud/sync-exclude.lst.backup

# 2. Edit the file
nano ~/.config/Nextcloud/sync-exclude.lst

# 3. Add your patterns at the bottom:
# .venv/
# target/
# .git/objects/*

# 4. Save and restart Nextcloud client
killall nextcloud  # or use GUI to quit
nextcloud &        # restart

# 5. Verify in activity log that patterns are working
```

## Additional Resources

- [Nextcloud Desktop Client Manual](https://docs.nextcloud.com/desktop/latest/)
- [Pattern Syntax Reference](https://docs.nextcloud.com/desktop/latest/advancedusage.html#ignored-files)
- Check your client version for feature compatibility

---

**Last Updated:** October 2025  
**For:** Nextcloud Server (Docker) at freddy
