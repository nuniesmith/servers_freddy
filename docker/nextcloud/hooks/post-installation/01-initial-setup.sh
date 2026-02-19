#!/bin/bash
# =============================================================================
# Nextcloud Post-Installation Hook: Initial Setup
# =============================================================================
# This hook runs ONCE after Nextcloud is installed for the first time.
# It configures sensible defaults via occ commands that only need to run once
# (persistent settings stored in the database).
#
# The official entrypoint calls scripts in post-installation/ only after a
# fresh install, NOT on subsequent starts or upgrades.
# =============================================================================

set -e

OCC="sudo -E -u www-data php /var/www/html/occ"

echo "────────────────────────────────────────────────"
echo "⚙️  Running post-installation setup..."
echo "────────────────────────────────────────────────"

# ── Background jobs: use cron instead of AJAX ────────────────────────────────
# The nextcloud-cron sidecar container handles this via /cron.sh
echo "  → Setting background jobs to cron..."
$OCC background:cron || echo "  ⚠️  Failed to set background job mode (non-fatal)"

# ── Set default phone region ─────────────────────────────────────────────────
echo "  → Setting default phone region to CA..."
$OCC config:system:set default_phone_region --value="CA" || true

# ── Disable unnecessary default apps ─────────────────────────────────────────
echo "  → Disabling unnecessary default apps..."
for app in weather_status survey_client firstrunwizard recommendations; do
    $OCC app:disable "$app" 2>/dev/null && echo "    ✅ Disabled: $app" || echo "    ⏭️  Skipped: $app (not installed or already disabled)"
done

# ── Enable useful apps if available ──────────────────────────────────────────
echo "  → Enabling useful apps..."
for app in admin_audit files_external; do
    $OCC app:enable "$app" 2>/dev/null && echo "    ✅ Enabled: $app" || echo "    ⏭️  Skipped: $app (not available)"
done

# ── Configure preview generation ─────────────────────────────────────────────
echo "  → Configuring preview providers..."
$OCC config:system:set enabledPreviewProviders 0 --value="OC\\Preview\\PNG" || true
$OCC config:system:set enabledPreviewProviders 1 --value="OC\\Preview\\JPEG" || true
$OCC config:system:set enabledPreviewProviders 2 --value="OC\\Preview\\GIF" || true
$OCC config:system:set enabledPreviewProviders 3 --value="OC\\Preview\\BMP" || true
$OCC config:system:set enabledPreviewProviders 4 --value="OC\\Preview\\SVG" || true
$OCC config:system:set enabledPreviewProviders 5 --value="OC\\Preview\\HEIC" || true
$OCC config:system:set enabledPreviewProviders 6 --value="OC\\Preview\\MP4" || true
$OCC config:system:set enabledPreviewProviders 7 --value="OC\\Preview\\MKV" || true
$OCC config:system:set enabledPreviewProviders 8 --value="OC\\Preview\\Movie" || true
$OCC config:system:set enabledPreviewProviders 9 --value="OC\\Preview\\MP3" || true
$OCC config:system:set enabledPreviewProviders 10 --value="OC\\Preview\\TXT" || true
$OCC config:system:set enabledPreviewProviders 11 --value="OC\\Preview\\MarkDown" || true
$OCC config:system:set enabledPreviewProviders 12 --value="OC\\Preview\\PDF" || true

# ── Set preview limits ───────────────────────────────────────────────────────
echo "  → Setting preview dimensions..."
$OCC config:system:set preview_max_x --value="2048" || true
$OCC config:system:set preview_max_y --value="2048" || true

# ── Maintenance window (run heavy tasks at 4 AM UTC) ─────────────────────────
echo "  → Setting maintenance window..."
$OCC config:system:set maintenance_window_start --type=integer --value="4" || true

# ── Run initial file scan ────────────────────────────────────────────────────
echo "  → Running initial file scan..."
$OCC files:scan --all 2>/dev/null || echo "  ⚠️  File scan skipped (no users yet, this is normal)"

# ── Add missing database indices ─────────────────────────────────────────────
echo "  → Adding missing database indices..."
$OCC db:add-missing-indices 2>/dev/null || echo "  ⚠️  Index update skipped (non-fatal)"

# ── Convert filecache bigint columns ─────────────────────────────────────────
echo "  → Converting bigint columns..."
$OCC db:convert-filecache-bigint --no-interaction 2>/dev/null || echo "  ⚠️  Bigint conversion skipped (non-fatal)"

echo ""
echo "────────────────────────────────────────────────"
echo "✅ Post-installation setup complete"
echo "────────────────────────────────────────────────"
