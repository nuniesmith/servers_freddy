#!/bin/sh
# =============================================================================
# Freddy Nginx Entrypoint Script
# =============================================================================
# This script runs at container startup to:
# 1. Check if real SSL certificates exist in the Docker volume
# 2. Copy certificates to the nginx SSL directory
# 3. Fall back to self-signed certificates if Let's Encrypt certs unavailable
# 4. Validate nginx configuration
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*"
}

log_cert() {
    echo -e "${CYAN}[CERT]${NC} $*"
}

# Configuration
DOMAIN="${SSL_DOMAIN:-7gram.xyz}"
TARGET_DIR="/etc/nginx/ssl"
FALLBACK_DIR="$TARGET_DIR/fallback"
VOLUME_DIR="/etc/letsencrypt-volume"

echo ""
echo "=========================================="
log_info "🚀 Freddy Nginx Initialization"
echo "=========================================="
log_debug "Domain: $DOMAIN"
log_debug "Target SSL directory: $TARGET_DIR"
log_debug "Volume mount: $VOLUME_DIR"
echo ""

# Ensure target directory exists
mkdir -p "$TARGET_DIR" 2>/dev/null || true

# Check if Let's Encrypt certificates exist in the mounted volume
check_letsencrypt_certs() {
    log_debug "Checking for certificates in $VOLUME_DIR"
    log_debug "Volume contents:"
    ls -lah "$VOLUME_DIR" 2>/dev/null | sed 's/^/  /' || log_warn "Cannot list volume directory"

    # Check in Let's Encrypt standard location first (from certbot)
    if [ -f "$VOLUME_DIR/live/$DOMAIN/fullchain.pem" ] && [ -f "$VOLUME_DIR/live/$DOMAIN/privkey.pem" ]; then
        # Verify the certificates are valid
        if openssl x509 -in "$VOLUME_DIR/live/$DOMAIN/fullchain.pem" -noout -checkend 0 >/dev/null 2>&1; then
            log_debug "✓ Certificate files found in live/$DOMAIN/ and valid"
            return 0
        else
            log_warn "Certificate file exists in live/$DOMAIN/ but is expired or invalid"
            return 1
        fi
    # Fallback to flat structure (legacy support)
    elif [ -f "$VOLUME_DIR/fullchain.pem" ] && [ -f "$VOLUME_DIR/privkey.pem" ]; then
        # Verify the certificates are valid
        if openssl x509 -in "$VOLUME_DIR/fullchain.pem" -noout -checkend 0 >/dev/null 2>&1; then
            log_debug "✓ Certificate files found at root level and valid"
            return 0
        else
            log_warn "Certificate file exists but is expired or invalid"
            return 1
        fi
    fi
    log_debug "Certificate files not found in volume"
    return 1
}

# Copy Let's Encrypt certificates
copy_letsencrypt_certs() {
    log_cert "Found Let's Encrypt certificates"
    log_info "Copying certificates from volume..."

    # Determine source path (try Let's Encrypt standard location first)
    local SOURCE_CERT=""
    local SOURCE_KEY=""
    
    if [ -f "$VOLUME_DIR/live/$DOMAIN/fullchain.pem" ]; then
        SOURCE_CERT="$VOLUME_DIR/live/$DOMAIN/fullchain.pem"
        SOURCE_KEY="$VOLUME_DIR/live/$DOMAIN/privkey.pem"
        log_debug "Using Let's Encrypt directory structure"
    else
        SOURCE_CERT="$VOLUME_DIR/fullchain.pem"
        SOURCE_KEY="$VOLUME_DIR/privkey.pem"
        log_debug "Using flat directory structure"
    fi

    cp "$SOURCE_CERT" "$TARGET_DIR/fullchain.pem"
    cp "$SOURCE_KEY" "$TARGET_DIR/privkey.pem"

    # Set proper permissions
    chmod 644 "$TARGET_DIR/fullchain.pem"
    chmod 600 "$TARGET_DIR/privkey.pem"
    chown nginx:nginx "$TARGET_DIR/fullchain.pem" "$TARGET_DIR/privkey.pem"

    # Show certificate info
    local issuer=$(openssl x509 -in "$TARGET_DIR/fullchain.pem" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local expiry=$(openssl x509 -in "$TARGET_DIR/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')

    log_cert "Certificate issuer: $issuer"
    log_cert "Certificate expires: $expiry"
    log_info "✓ Let's Encrypt certificates configured for production"
}

# Copy fallback self-signed certificates
copy_fallback_certs() {
    log_warn "No Let's Encrypt certificates found in volume"
    log_warn "Using self-signed fallback certificates"
    log_warn "⚠️  Browsers will show security warnings"
    echo ""
    log_info "To obtain real certificates, ensure:"
    log_info "  1. Cloudflare DNS is properly configured"
    log_info "  2. CI/CD secrets are set (CLOUDFLARE_API_KEY, etc.)"
    log_info "  3. The ci-ssl-setup.sh script runs during deployment"
    echo ""

    if [ ! -f "$FALLBACK_DIR/fullchain.pem" ] || [ ! -f "$FALLBACK_DIR/privkey.pem" ]; then
        log_error "Fallback certificates missing! This should not happen."
        log_error "Attempting to generate fallback certificates..."

        mkdir -p "$FALLBACK_DIR"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$FALLBACK_DIR/privkey.pem" \
            -out "$FALLBACK_DIR/fullchain.pem" \
            -subj "/C=CA/ST=Ontario/L=Toronto/O=Freddy/CN=$DOMAIN" \
            -addext "subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN" 2>/dev/null || {
                log_error "Failed to generate fallback certificates"
                exit 1
            }

        chmod 644 "$FALLBACK_DIR/fullchain.pem"
        chmod 600 "$FALLBACK_DIR/privkey.pem"
    fi

    cp "$FALLBACK_DIR/fullchain.pem" "$TARGET_DIR/fullchain.pem"
    cp "$FALLBACK_DIR/privkey.pem" "$TARGET_DIR/privkey.pem"

    chmod 644 "$TARGET_DIR/fullchain.pem"
    chmod 600 "$TARGET_DIR/privkey.pem"
    chown nginx:nginx "$TARGET_DIR/fullchain.pem" "$TARGET_DIR/privkey.pem"

    log_info "✓ Fallback certificates configured"
}

# Main certificate setup logic
setup_certificates() {
    if check_letsencrypt_certs; then
        copy_letsencrypt_certs
    else
        copy_fallback_certs
    fi
}

# Verify certificates are readable
verify_certificates() {
    log_info "Verifying certificate setup..."

    if [ ! -f "$TARGET_DIR/fullchain.pem" ]; then
        log_error "Certificate file missing: $TARGET_DIR/fullchain.pem"
        return 1
    fi

    if [ ! -f "$TARGET_DIR/privkey.pem" ]; then
        log_error "Private key missing: $TARGET_DIR/privkey.pem"
        return 1
    fi

    # Check if certificate is valid
    if ! openssl x509 -in "$TARGET_DIR/fullchain.pem" -noout -text >/dev/null 2>&1; then
        log_error "Certificate is not valid"
        return 1
    fi

    # Check if private key matches certificate
    log_debug "Computing certificate modulus..."
    local cert_modulus=$(openssl x509 -noout -modulus -in "$TARGET_DIR/fullchain.pem" 2>/dev/null | openssl md5)
    local cert_modulus_exit=$?

    log_debug "Computing private key modulus..."
    local key_modulus=$(openssl rsa -noout -modulus -in "$TARGET_DIR/privkey.pem" 2>/dev/null | openssl md5)
    local key_modulus_exit=$?

    log_debug "Certificate modulus (exit=$cert_modulus_exit): $cert_modulus"
    log_debug "Private key modulus (exit=$key_modulus_exit): $key_modulus"

    if [ $cert_modulus_exit -ne 0 ]; then
        log_error "Failed to compute certificate modulus"
        return 1
    fi

    if [ $key_modulus_exit -ne 0 ]; then
        log_error "Failed to compute private key modulus"
        log_debug "Attempting to read key with different formats..."
        # Try EC key
        key_modulus=$(openssl ec -noout -modulus -in "$TARGET_DIR/privkey.pem" 2>/dev/null | openssl md5)
        if [ $? -eq 0 ]; then
            log_debug "Private key is EC format: $key_modulus"
        else
            log_error "Could not read private key in RSA or EC format"
            return 1
        fi
    fi

    if [ "$cert_modulus" != "$key_modulus" ]; then
        log_error "Certificate and private key do not match!"
        log_error "This usually means:"
        log_error "  1. The wrong certificate/key pair is mounted"
        log_error "  2. Files were copied from different sources"
        log_error "  3. Certificate was regenerated but key wasn't"
        log_debug "Checking source files in volume..."
        if [ -f "$VOLUME_DIR/fullchain.pem" ] && [ -f "$VOLUME_DIR/privkey.pem" ]; then
            local vol_cert_modulus=$(openssl x509 -noout -modulus -in "$VOLUME_DIR/fullchain.pem" 2>/dev/null | openssl md5)
            local vol_key_modulus=$(openssl rsa -noout -modulus -in "$VOLUME_DIR/privkey.pem" 2>/dev/null | openssl md5)
            log_debug "Volume cert modulus: $vol_cert_modulus"
            log_debug "Volume key modulus: $vol_key_modulus"
            if [ "$vol_cert_modulus" != "$vol_key_modulus" ]; then
                log_error "✗ Mismatch is in the SOURCE files in $VOLUME_DIR"
                log_error "  The mounted certificate files themselves don't match!"
            else
                log_error "✗ Mismatch occurred during copy"
            fi
        fi
        return 1
    fi

    log_info "✓ Certificate verification passed"
    return 0
}

# Validate nginx configuration
validate_nginx_config() {
    log_info "Validating nginx configuration..."

    if nginx -t 2>&1 | grep -q "successful"; then
        log_info "✓ Nginx configuration is valid"
        return 0
    else
        log_error "Nginx configuration validation failed:"
        nginx -t 2>&1 | sed 's/^/  /'
        return 1
    fi
}

# Show startup summary
show_summary() {
    echo ""
    echo "=========================================="
    log_info "📋 Nginx Startup Summary"
    echo "=========================================="
    log_info "Domain: $DOMAIN"
    log_info "SSL Directory: $TARGET_DIR"

    if [ -f "$TARGET_DIR/fullchain.pem" ]; then
        local cert_type="Unknown"
        if openssl x509 -in "$TARGET_DIR/fullchain.pem" -noout -issuer 2>/dev/null | grep -qi "Let's Encrypt"; then
            cert_type="Let's Encrypt (Production)"
        elif openssl x509 -in "$TARGET_DIR/fullchain.pem" -noout -issuer 2>/dev/null | grep -qi "$DOMAIN"; then
            cert_type="Self-Signed (Development)"
        fi
        log_info "Certificate Type: $cert_type"
    fi

    log_info "HTTP Port: 80 (redirects to HTTPS)"
    log_info "HTTPS Port: 443"
    log_info "Health Check: http://localhost/health"
    echo "=========================================="
    log_info "✓ Nginx is ready to start"
    echo "=========================================="
    echo ""
}

# Main execution
main() {
    # Setup certificates
    setup_certificates || {
        log_error "Certificate setup failed"
        exit 1
    }

    # Verify certificates
    verify_certificates || {
        log_error "Certificate verification failed"
        exit 1
    }

    # Validate nginx configuration
    validate_nginx_config || {
        log_error "Nginx configuration validation failed"
        exit 1
    }

    # Show summary
    show_summary
}

# Run main function
main

# Exit successfully to allow nginx to start
exit 0
