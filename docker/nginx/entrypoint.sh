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
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
FALLBACK_DIR="/etc/nginx/ssl/fallback"

# Ensure cert directory exists
mkdir -p "$CERT_DIR" 2>/dev/null || true

# Check if real Let's Encrypt certificates exist in the volume
if [ -f "/etc/letsencrypt-volume/live/$DOMAIN/fullchain.pem" ] && \
   [ -f "/etc/letsencrypt-volume/live/$DOMAIN/privkey.pem" ]; then
    echo "✓ Found Let's Encrypt certificates for $DOMAIN"

    # Update symlinks to point to real certs
    # Force remove existing files/symlinks (handles both files and symlinks)
    for cert_file in fullchain.pem privkey.pem chain.pem cert.pem; do
        target="$CERT_DIR/$cert_file"
        if [ -e "$target" ] || [ -L "$target" ]; then
            rm -f "$target" 2>/dev/null || true
        fi
    done

    # Create new symlinks with force flag
    ln -sf "/etc/letsencrypt-volume/live/$DOMAIN/fullchain.pem" "$CERT_DIR/fullchain.pem" 2>/dev/null || \
        cp "/etc/letsencrypt-volume/live/$DOMAIN/fullchain.pem" "$CERT_DIR/fullchain.pem"
    ln -sf "/etc/letsencrypt-volume/live/$DOMAIN/privkey.pem" "$CERT_DIR/privkey.pem" 2>/dev/null || \
        cp "/etc/letsencrypt-volume/live/$DOMAIN/privkey.pem" "$CERT_DIR/privkey.pem"

    # Also link chain.pem and cert.pem if they exist
    [ -f "/etc/letsencrypt-volume/live/$DOMAIN/chain.pem" ] && \
        (ln -sf "/etc/letsencrypt-volume/live/$DOMAIN/chain.pem" "$CERT_DIR/chain.pem" 2>/dev/null || true)
    [ -f "/etc/letsencrypt-volume/live/$DOMAIN/cert.pem" ] && \
        (ln -sf "/etc/letsencrypt-volume/live/$DOMAIN/cert.pem" "$CERT_DIR/cert.pem" 2>/dev/null || true)

    echo "✓ SSL certificates configured for production"
else
    echo "⚠ No Let's Encrypt certificates found"
    echo "  Using self-signed fallback certificates"
    echo "  To get real certificates, run: ./run.sh ssl-init"

    # Ensure fallback certs are linked
    for cert_file in fullchain.pem privkey.pem; do
        target="$CERT_DIR/$cert_file"
        if [ -e "$target" ] || [ -L "$target" ]; then
            rm -f "$target" 2>/dev/null || true
        fi
    done

    ln -sf "$FALLBACK_DIR/fullchain.pem" "$CERT_DIR/fullchain.pem" 2>/dev/null || \
        cp "$FALLBACK_DIR/fullchain.pem" "$CERT_DIR/fullchain.pem"
    ln -sf "$FALLBACK_DIR/privkey.pem" "$CERT_DIR/privkey.pem" 2>/dev/null || \
        cp "$FALLBACK_DIR/privkey.pem" "$CERT_DIR/privkey.pem"
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
