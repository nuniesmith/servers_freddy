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
# Source: /usr/src/nextcloud-custom-config/*.config.php  (baked into image)
# Target: /var/www/html/config/                          (live config dir)
# =============================================================================

set -e

CONFIG_SRC="/usr/src/nextcloud-custom-config"
CONFIG_DST="/var/www/html/config"

echo "────────────────────────────────────────────────"
echo "📝 Applying custom Nextcloud configuration..."
echo "────────────────────────────────────────────────"

# Ensure the target config directory exists
mkdir -p "$CONFIG_DST"

if [ -d "$CONFIG_SRC" ] && [ "$(ls -A "$CONFIG_SRC"/*.config.php 2>/dev/null)" ]; then
    for src_file in "$CONFIG_SRC"/*.config.php; do
        filename="$(basename "$src_file")"
        dst_file="$CONFIG_DST/$filename"

        # Copy the config override into place
        cp "$src_file" "$dst_file"
        echo "  ✅ Applied: $filename"
    done

    # Ensure www-data owns all config files
    chown -R www-data:www-data "$CONFIG_DST"
    chmod 660 "$CONFIG_DST"/*.config.php 2>/dev/null || true
    chmod 770 "$CONFIG_DST"

    echo "  ✅ Permissions set (www-data:www-data)"
else
    echo "  ⚠️  No custom config files found in $CONFIG_SRC"
fi

echo "────────────────────────────────────────────────"
echo "✅ Custom configuration applied"
echo "────────────────────────────────────────────────"
