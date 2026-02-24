#!/bin/bash
# =============================================================================
# Nextcloud Before-Starting Hook: Apply Custom Configuration
# =============================================================================
# This hook runs on every container start (before Apache launches) and copies
# custom Nextcloud config overrides from the build-time staging directory into
# the live config directory.
#
# Why a hook instead of a direct COPY in the Dockerfile?
#   The official entrypoint may overwrite /var/www/html/config/ during
#   installation or upgrades.  By applying our overrides in before-starting,
#   they always take effect regardless of what the base entrypoint did.
#
# Permission handling:
#   Depending on the Nextcloud image version and whether this is a fresh
#   install or an existing one, this hook may run as root OR as www-data.
#   We detect the current user and use the appropriate copy strategy:
#     - root:     cp + chown
#     - www-data: try cp, fall back to sudo cp if the target file is
#                 owned by root from a previous run
#   The Dockerfile installs sudo with NOPASSWD for www-data, so the
#   fallback always works.
#
# Source: /usr/src/nextcloud-custom-config/*.config.php  (baked into image)
# Target: /var/www/html/config/                          (live config dir)
# =============================================================================

set -e

CONFIG_SRC="/usr/src/nextcloud-custom-config"
CONFIG_DST="/var/www/html/config"

echo "────────────────────────────────────────────────"
echo "📝 Applying custom Nextcloud configuration..."
echo "────────────────────────────────────────────────"

CURRENT_UID="$(id -u)"
CURRENT_USER="$(id -un 2>/dev/null || echo "uid-${CURRENT_UID}")"
echo "  ℹ️  Running as: ${CURRENT_USER} (UID ${CURRENT_UID})"

# Ensure the target config directory exists
if [ "${CURRENT_UID}" -eq 0 ]; then
    mkdir -p "$CONFIG_DST"
else
    # As www-data, try mkdir; fall back to sudo
    mkdir -p "$CONFIG_DST" 2>/dev/null || sudo mkdir -p "$CONFIG_DST"
fi

# copy_file src dst — copy a single file, handling permission issues
copy_file() {
    local src="$1"
    local dst="$2"

    if [ "${CURRENT_UID}" -eq 0 ]; then
        # Running as root — straightforward copy
        cp -f "$src" "$dst"
    else
        # Running as www-data — try direct copy first
        if cp -f "$src" "$dst" 2>/dev/null; then
            : # success
        else
            # Direct copy failed (target likely owned by root from a prior run).
            # Use sudo to overwrite, then fix ownership so future runs work
            # without sudo.
            sudo cp -f "$src" "$dst"
            sudo chown www-data:www-data "$dst"
        fi
    fi
}

# fix_permissions — ensure www-data owns the config directory and files
fix_permissions() {
    if [ "${CURRENT_UID}" -eq 0 ]; then
        chown -R www-data:www-data "$CONFIG_DST"
        chmod 770 "$CONFIG_DST"
        chmod 660 "$CONFIG_DST"/*.config.php 2>/dev/null || true
    else
        sudo chown -R www-data:www-data "$CONFIG_DST"
        sudo chmod 770 "$CONFIG_DST"
        sudo chmod 660 "$CONFIG_DST"/*.config.php 2>/dev/null || true
    fi
}

if [ -d "$CONFIG_SRC" ] && [ "$(ls -A "$CONFIG_SRC"/*.config.php 2>/dev/null)" ]; then
    for src_file in "$CONFIG_SRC"/*.config.php; do
        filename="$(basename "$src_file")"
        dst_file="$CONFIG_DST/$filename"

        copy_file "$src_file" "$dst_file"
        echo "  ✅ Applied: $filename"
    done

    fix_permissions
    echo "  ✅ Permissions set (www-data:www-data)"
else
    echo "  ⚠️  No custom config files found in $CONFIG_SRC"
fi

echo "────────────────────────────────────────────────"
echo "✅ Custom configuration applied"
echo "────────────────────────────────────────────────"
