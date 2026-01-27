#!/bin/sh
# =============================================================================
# Freddy Nginx Entrypoint Script
# =============================================================================
# This script runs at container startup to:
# 1. Check if real SSL certificates exist in the Docker volume
# 2. If yes, update symlinks to use real certs
# 3. If no, keep using the fallback self-signed certs
# =============================================================================

# Don't exit on error - we want to continue even if symlinks fail
set +e

echo "=== Freddy Nginx Initialization ==="

DOMAIN="${SSL_DOMAIN:-7gram.xyz}"
TARGET_DIR="/etc/nginx/ssl"
FALLBACK_DIR="$TARGET_DIR/fallback"

# Ensure cert directory exists (for LE)
mkdir -p "/etc/letsencrypt/live/$DOMAIN" 2>/dev/null || true

# Check if real Let's Encrypt certificates exist in the volume
if [ -f "/etc/letsencrypt-volume/live/$DOMAIN/fullchain.pem" ] && \
   [ -f "/etc/letsencrypt-volume/live/$DOMAIN/privkey.pem" ]; then
    echo "✓ Found Let's Encrypt certificates for $DOMAIN"

    # Copy LE certs to target dir
    cp "/etc/letsencrypt-volume/live/$DOMAIN/fullchain.pem" "$TARGET_DIR/fullchain.pem"
    cp "/etc/letsencrypt-volume/live/$DOMAIN/privkey.pem" "$TARGET_DIR/privkey.pem"

    chmod 644 "$TARGET_DIR/fullchain.pem"
    chmod 600 "$TARGET_DIR/privkey.pem"
    chown nginx:nginx "$TARGET_DIR/fullchain.pem" "$TARGET_DIR/privkey.pem"

    echo "✓ SSL certificates configured for production"
else
    echo "⚠ No Let's Encrypt certificates found"
    echo "  Using self-signed fallback certificates"
    echo "  To get real certificates, run: ./run.sh ssl-init"

    # Copy fallback certs to target dir
    cp "$FALLBACK_DIR/fullchain.pem" "$TARGET_DIR/fullchain.pem"
    cp "$FALLBACK_DIR/privkey.pem" "$TARGET_DIR/privkey.pem"

    chmod 644 "$TARGET_DIR/fullchain.pem"
    chmod 600 "$TARGET_DIR/privkey.pem"
    chown nginx:nginx "$TARGET_DIR/fullchain.pem" "$TARGET_DIR/privkey.pem"

    echo "Copied fallback certs: $(ls -la $TARGET_DIR/*.pem)"
fi

# Re-enable exit on error for nginx validation
set -e

# Validate nginx configuration
echo "Validating nginx configuration..."
if nginx -t 2>/dev/null; then
    echo "✓ Nginx configuration is valid"
else
    echo "✗ Nginx configuration error - check logs"
    nginx -t
fi

echo "=== Freddy Nginx Ready ==="
