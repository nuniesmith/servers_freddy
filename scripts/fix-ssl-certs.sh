#!/bin/bash
# =============================================================================
# Fix SSL Certificates Script
# =============================================================================
# This script fixes corrupted SSL certificates by copying valid certificates
# from Let's Encrypt to the Docker volume mount location.
#
# Usage:
#   sudo ./fix-ssl-certs.sh
#
# What it does:
#   1. Validates Let's Encrypt certificates exist and are valid
#   2. Backs up corrupted certificates (if any)
#   3. Copies valid certificates to the Docker volume mount location
#   4. Verifies certificate and private key match
#   5. Optionally restarts the nginx container
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="${DOMAIN:-7gram.xyz}"
LETSENCRYPT_DIR="/etc/letsencrypt/live/$DOMAIN"
TARGET_DIR="/opt/ssl/$DOMAIN"
BACKUP_DIR="/opt/ssl/backup-$(date +%Y%m%d-%H%M%S)"

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Validate Let's Encrypt certificates exist
validate_source_certs() {
    log_info "Validating source certificates in $LETSENCRYPT_DIR..."

    if [ ! -d "$LETSENCRYPT_DIR" ]; then
        log_error "Let's Encrypt directory not found: $LETSENCRYPT_DIR"
        log_error "Have you run certbot to generate certificates?"
        return 1
    fi

    if [ ! -f "$LETSENCRYPT_DIR/fullchain.pem" ]; then
        log_error "Certificate not found: $LETSENCRYPT_DIR/fullchain.pem"
        return 1
    fi

    if [ ! -f "$LETSENCRYPT_DIR/privkey.pem" ]; then
        log_error "Private key not found: $LETSENCRYPT_DIR/privkey.pem"
        return 1
    fi

    # Check if certificate is valid
    if ! openssl x509 -in "$LETSENCRYPT_DIR/fullchain.pem" -noout -text >/dev/null 2>&1; then
        log_error "Certificate is not valid or corrupted"
        return 1
    fi

    # Check if private key is valid
    if ! openssl rsa -in "$LETSENCRYPT_DIR/privkey.pem" -check -noout >/dev/null 2>&1; then
        log_error "Private key is not valid or corrupted"
        return 1
    fi

    # Verify certificate and private key match
    local cert_modulus=$(openssl x509 -noout -modulus -in "$LETSENCRYPT_DIR/fullchain.pem" 2>/dev/null | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$LETSENCRYPT_DIR/privkey.pem" 2>/dev/null | openssl md5)

    log_debug "Source cert modulus: $cert_modulus"
    log_debug "Source key modulus:  $key_modulus"

    if [ "$cert_modulus" != "$key_modulus" ]; then
        log_error "Source certificate and private key do not match!"
        log_error "This means the Let's Encrypt certificates themselves are corrupted."
        log_error "You need to regenerate them with certbot."
        return 1
    fi

    # Show certificate details
    local issuer=$(openssl x509 -in "$LETSENCRYPT_DIR/fullchain.pem" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local expiry=$(openssl x509 -in "$LETSENCRYPT_DIR/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    local subject=$(openssl x509 -in "$LETSENCRYPT_DIR/fullchain.pem" -noout -subject 2>/dev/null | sed 's/subject=//')

    log_success "✓ Source certificates are valid"
    echo ""
    echo "Certificate Details:"
    echo "  Subject: $subject"
    echo "  Issuer:  $issuer"
    echo "  Expires: $expiry"
    echo ""

    return 0
}

# Backup existing certificates if they exist
backup_existing_certs() {
    if [ -d "$TARGET_DIR" ]; then
        log_info "Backing up existing certificates to $BACKUP_DIR..."
        mkdir -p "$BACKUP_DIR"
        cp -r "$TARGET_DIR/"* "$BACKUP_DIR/" 2>/dev/null || true
        log_success "✓ Backup created"
    else
        log_info "No existing certificates to backup"
    fi
}

# Copy certificates to target directory
copy_certificates() {
    log_info "Copying certificates to $TARGET_DIR..."

    # Create target directory if it doesn't exist
    mkdir -p "$TARGET_DIR"

    # Copy certificates
    cp "$LETSENCRYPT_DIR/fullchain.pem" "$TARGET_DIR/fullchain.pem"
    cp "$LETSENCRYPT_DIR/privkey.pem" "$TARGET_DIR/privkey.pem"

    # Set proper permissions
    chmod 644 "$TARGET_DIR/fullchain.pem"
    chmod 600 "$TARGET_DIR/privkey.pem"

    # Set ownership (nginx typically runs as www-data or nginx user)
    # We'll keep it as root since Docker will handle it
    chown root:root "$TARGET_DIR/fullchain.pem"
    chown root:root "$TARGET_DIR/privkey.pem"

    log_success "✓ Certificates copied"
}

# Verify copied certificates
verify_target_certs() {
    log_info "Verifying copied certificates..."

    # Check files exist
    if [ ! -f "$TARGET_DIR/fullchain.pem" ] || [ ! -f "$TARGET_DIR/privkey.pem" ]; then
        log_error "Certificate files not found in target directory"
        return 1
    fi

    # Verify certificate and private key match
    local cert_modulus=$(openssl x509 -noout -modulus -in "$TARGET_DIR/fullchain.pem" 2>/dev/null | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$TARGET_DIR/privkey.pem" 2>/dev/null | openssl md5)

    log_debug "Target cert modulus: $cert_modulus"
    log_debug "Target key modulus:  $key_modulus"

    if [ "$cert_modulus" != "$key_modulus" ]; then
        log_error "Copied certificate and private key do not match!"
        log_error "Something went wrong during the copy process."
        return 1
    fi

    log_success "✓ Certificate and key match correctly"

    # Show file details
    echo ""
    log_info "Target certificate files:"
    ls -lh "$TARGET_DIR/fullchain.pem" "$TARGET_DIR/privkey.pem"
    echo ""

    return 0
}

# Restart nginx container
restart_nginx() {
    log_info "Checking if nginx container is running..."

    if docker ps --format '{{.Names}}' | grep -q "^nginx$"; then
        log_info "Restarting nginx container..."
        docker restart nginx
        log_success "✓ Nginx container restarted"

        # Wait a moment for nginx to start
        sleep 3

        # Check if nginx is healthy
        if docker ps --filter "name=nginx" --filter "health=healthy" --format '{{.Names}}' | grep -q "nginx"; then
            log_success "✓ Nginx is running and healthy"
        else
            log_warn "Nginx restarted but health check not yet passed"
            log_info "Check logs with: docker logs nginx"
        fi
    else
        log_warn "Nginx container is not running"
        log_info "Start it with: docker compose up -d nginx"
    fi
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    log_info "🔧 SSL Certificate Fix Script"
    echo "=========================================="
    echo "Domain: $DOMAIN"
    echo "Source: $LETSENCRYPT_DIR"
    echo "Target: $TARGET_DIR"
    echo "=========================================="
    echo ""

    # Check root privileges
    check_root

    # Validate source certificates
    if ! validate_source_certs; then
        log_error "Source certificate validation failed"
        exit 1
    fi

    # Backup existing certificates
    backup_existing_certs

    # Copy certificates
    if ! copy_certificates; then
        log_error "Failed to copy certificates"
        exit 1
    fi

    # Verify copied certificates
    if ! verify_target_certs; then
        log_error "Target certificate verification failed"
        exit 1
    fi

    echo ""
    echo "=========================================="
    log_success "🎉 SSL Certificates Fixed Successfully!"
    echo "=========================================="
    echo ""

    # Ask about restarting nginx
    read -p "Do you want to restart the nginx container now? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restart_nginx
    else
        log_info "Skipping nginx restart"
        log_info "Remember to restart nginx when ready: docker restart nginx"
    fi

    echo ""
    log_success "✓ Done!"
    echo ""
}

# Run main function
main
