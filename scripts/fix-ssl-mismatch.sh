#!/bin/bash
# =============================================================================
# SSL Certificate Mismatch Diagnostic and Fix Script
# =============================================================================
# This script diagnoses and fixes SSL certificate/key mismatch issues for
# the Freddy nginx reverse proxy.
#
# Usage:
#   ./fix-ssl-mismatch.sh [--check-only] [--force]
#
# Options:
#   --check-only    Only check certificates, don't fix anything
#   --force         Force regeneration of certificates
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="7gram.xyz"
CERT_DIR="/opt/ssl/7gram.xyz"
LETSENCRYPT_DIR="/etc/letsencrypt/live/${DOMAIN}"
CHECK_ONLY=0
FORCE=0

# Parse arguments
for arg in "$@"; do
    case $arg in
        --check-only)
            CHECK_ONLY=1
            ;;
        --force)
            FORCE=1
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--check-only] [--force]"
            exit 1
            ;;
    esac
done

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

# Print header
print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Check if running as root or with sudo
check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Compute certificate modulus
get_cert_modulus() {
    local cert_file="$1"
    if [ ! -f "$cert_file" ]; then
        echo "FILE_NOT_FOUND"
        return 1
    fi
    openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5 | awk '{print $2}'
}

# Compute private key modulus
get_key_modulus() {
    local key_file="$1"
    if [ ! -f "$key_file" ]; then
        echo "FILE_NOT_FOUND"
        return 1
    fi

    # Try RSA first
    local modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5 | awk '{print $2}')
    if [ -n "$modulus" ]; then
        echo "$modulus"
        return 0
    fi

    # Try EC
    modulus=$(openssl ec -noout -modulus -in "$key_file" 2>/dev/null | openssl md5 | awk '{print $2}')
    if [ -n "$modulus" ]; then
        echo "$modulus"
        return 0
    fi

    echo "INVALID_KEY"
    return 1
}

# Check certificate validity
check_cert_validity() {
    local cert_file="$1"
    if [ ! -f "$cert_file" ]; then
        echo "missing"
        return 1
    fi

    if ! openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null 2>&1; then
        echo "expired"
        return 1
    fi

    echo "valid"
    return 0
}

# Show certificate info
show_cert_info() {
    local cert_file="$1"
    local label="$2"

    if [ ! -f "$cert_file" ]; then
        log_warn "$label: File not found"
        return
    fi

    log_cert "$label:"
    openssl x509 -in "$cert_file" -noout -issuer -subject -dates 2>/dev/null | sed 's/^/  /' || log_error "  Cannot read certificate"
}

# Check certificates in a directory
check_directory_certs() {
    local dir="$1"
    local label="$2"

    print_header "$label"

    if [ ! -d "$dir" ]; then
        log_error "Directory not found: $dir"
        return 1
    fi

    log_info "Checking: $dir"

    local cert_file="$dir/fullchain.pem"
    local key_file="$dir/privkey.pem"

    # Check if files exist
    if [ ! -f "$cert_file" ]; then
        log_error "Certificate missing: $cert_file"
        return 1
    fi

    if [ ! -f "$key_file" ]; then
        log_error "Private key missing: $key_file"
        return 1
    fi

    log_info "✓ Both files exist"

    # Check certificate validity
    local validity=$(check_cert_validity "$cert_file")
    if [ "$validity" = "valid" ]; then
        log_info "✓ Certificate is valid (not expired)"
    elif [ "$validity" = "expired" ]; then
        log_error "✗ Certificate is EXPIRED"
    else
        log_error "✗ Certificate is invalid or cannot be read"
    fi

    # Show certificate info
    show_cert_info "$cert_file" "Certificate Details"

    # Check if certificate and key match
    local cert_modulus=$(get_cert_modulus "$cert_file")
    local key_modulus=$(get_key_modulus "$key_file")

    log_debug "Certificate modulus: $cert_modulus"
    log_debug "Private key modulus: $key_modulus"

    if [ "$cert_modulus" = "FILE_NOT_FOUND" ]; then
        log_error "✗ Cannot read certificate"
        return 1
    fi

    if [ "$key_modulus" = "FILE_NOT_FOUND" ]; then
        log_error "✗ Cannot read private key"
        return 1
    fi

    if [ "$key_modulus" = "INVALID_KEY" ]; then
        log_error "✗ Private key is invalid or in unsupported format"
        return 1
    fi

    if [ "$cert_modulus" = "$key_modulus" ]; then
        log_info "✓ Certificate and private key MATCH"
        return 0
    else
        log_error "✗ Certificate and private key DO NOT MATCH"
        return 1
    fi
}

# Copy certificates from Let's Encrypt to target directory
copy_certificates() {
    log_info "Copying certificates from Let's Encrypt to $CERT_DIR..."

    # Ensure target directory exists
    mkdir -p "$CERT_DIR"

    # Copy certificates (follow symlinks with -L)
    cp -L "$LETSENCRYPT_DIR/fullchain.pem" "$CERT_DIR/"
    cp -L "$LETSENCRYPT_DIR/privkey.pem" "$CERT_DIR/"

    # Set proper permissions
    chmod 644 "$CERT_DIR/fullchain.pem"
    chmod 600 "$CERT_DIR/privkey.pem"

    # Try to set ownership to actions user if it exists
    if id "actions" >/dev/null 2>&1; then
        chown actions:actions "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"
    fi

    log_info "✓ Certificates copied successfully"
}

# Restart nginx container
restart_nginx() {
    log_info "Restarting nginx container..."

    if docker ps -a --format '{{.Names}}' | grep -q '^nginx$'; then
        docker restart nginx
        log_info "✓ Nginx container restarted"

        # Wait a few seconds and check status
        sleep 3
        if docker ps --format '{{.Names}}\t{{.Status}}' | grep '^nginx' | grep -q 'Up'; then
            log_info "✓ Nginx container is running"
        else
            log_error "✗ Nginx container is not running"
            log_info "Check logs with: docker logs nginx"
        fi
    else
        log_warn "Nginx container not found"
        log_info "Start it with: docker-compose up -d nginx"
    fi
}

# Main function
main() {
    print_header "🔍 SSL Certificate Mismatch Diagnostic"

    check_permissions

    log_info "Domain: $DOMAIN"
    log_info "Mode: $([ $CHECK_ONLY -eq 1 ] && echo 'CHECK ONLY' || echo 'CHECK AND FIX')"

    # Check Let's Encrypt certificates
    local le_status=0
    check_directory_certs "$LETSENCRYPT_DIR" "Let's Encrypt Certificates" || le_status=$?

    # Check target directory certificates
    local target_status=0
    check_directory_certs "$CERT_DIR" "Target Directory Certificates" || target_status=$?

    # Summary
    print_header "📋 Summary"

    if [ $le_status -eq 0 ]; then
        log_info "✓ Let's Encrypt certificates are valid and matched"
    else
        log_error "✗ Let's Encrypt certificates have issues"
    fi

    if [ $target_status -eq 0 ]; then
        log_info "✓ Target directory certificates are valid and matched"
    else
        log_error "✗ Target directory certificates have issues"
    fi

    # Determine action
    if [ $CHECK_ONLY -eq 1 ]; then
        print_header "✅ Check Complete"
        exit 0
    fi

    # Fix logic
    if [ $le_status -eq 0 ] && [ $target_status -ne 0 ]; then
        print_header "🔧 Fixing Certificate Mismatch"
        log_info "Let's Encrypt certificates are good, but target directory has issues"
        log_info "Copying Let's Encrypt certificates to target directory..."

        if copy_certificates; then
            log_info "✓ Certificates copied successfully"

            # Verify the fix
            print_header "🔍 Verifying Fix"
            if check_directory_certs "$CERT_DIR" "Target Directory Certificates (After Fix)"; then
                log_info "✓ Fix successful! Certificates now match."
                restart_nginx
            else
                log_error "✗ Fix failed! Certificates still don't match."
                exit 1
            fi
        else
            log_error "Failed to copy certificates"
            exit 1
        fi
    elif [ $le_status -ne 0 ]; then
        log_error "Let's Encrypt certificates have issues"
        log_error "You need to regenerate Let's Encrypt certificates first"
        log_info ""
        log_info "Options:"
        log_info "  1. Run CI/CD pipeline to regenerate certificates"
        log_info "  2. Run locally: ./run.sh ssl-init"
        log_info "  3. Use certbot manually to generate new certificates"
        exit 1
    else
        log_info "All certificates are valid and matched - no fix needed!"
    fi

    print_header "✅ Complete"
}

# Run main function
main
