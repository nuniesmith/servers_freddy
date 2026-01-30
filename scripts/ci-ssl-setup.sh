#!/usr/bin/env bash
# =============================================================================
# CI/CD SSL Certificate Setup Script
# =============================================================================
# Automated Let's Encrypt certificate generation using Cloudflare DNS
# This script is designed for CI/CD pipelines (non-interactive)
#
# Required Environment Variables:
#   - CLOUDFLARE_EMAIL: Your Cloudflare account email
#   - CLOUDFLARE_API_KEY: Cloudflare Global API Key OR
#   - CLOUDFLARE_API_TOKEN: Cloudflare API Token with Zone:DNS:Edit permissions
#   - CERTBOT_EMAIL: Email for Let's Encrypt notifications
#
# Usage:
#   export CLOUDFLARE_EMAIL="user@example.com"
#   export CLOUDFLARE_API_KEY="your-global-api-key"
#   export CERTBOT_EMAIL="user@example.com"
#   ./ci-ssl-setup.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOMAIN="${SSL_DOMAIN:-7gram.xyz}"
CERT_DIR="${SSL_CERT_PATH:-/opt/ssl/7gram.xyz}"
CLOUDFLARE_CREDS="/tmp/cloudflare-ci.ini"
LETSENCRYPT_DIR="/etc/letsencrypt/live/${DOMAIN}"

# Logging
log() {
    local level="$1"; shift
    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC} $*" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $*" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $*" ;;
    esac
}

# Check if running in CI environment
is_ci() {
    [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]
}

# Check required environment variables
check_env_vars() {
    local missing=()

    if [[ -z "${CLOUDFLARE_EMAIL:-}" ]] && [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        missing+=("CLOUDFLARE_EMAIL (required with Global API Key)")
    fi

    if [[ -z "${CLOUDFLARE_API_KEY:-}" ]] && [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        missing+=("CLOUDFLARE_API_KEY or CLOUDFLARE_API_TOKEN")
    fi

    if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
        missing+=("CERTBOT_EMAIL")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Missing required environment variables:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Example setup:"
        echo "  export CLOUDFLARE_EMAIL='your@email.com'"
        echo "  export CLOUDFLARE_API_KEY='your-cloudflare-global-api-key'"
        echo "  export CERTBOT_EMAIL='your@email.com'"
        echo ""
        echo "Or using API Token (more secure):"
        echo "  export CLOUDFLARE_API_TOKEN='your-cloudflare-api-token'"
        echo "  export CERTBOT_EMAIL='your@email.com'"
        return 1
    fi

    return 0
}

# Install certbot and Cloudflare plugin
install_certbot() {
    log INFO "Checking for certbot..."

    if command -v certbot >/dev/null 2>&1; then
        log INFO "✓ Certbot already installed"
        return 0
    fi

    log INFO "Installing certbot and Cloudflare DNS plugin..."

    # Detect OS and install accordingly
    if [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
        # Fedora/RHEL
        sudo dnf install -y certbot python3-certbot-dns-cloudflare
    elif [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y certbot python3-certbot-dns-cloudflare
    elif command -v snap >/dev/null 2>&1; then
        # Use snap as fallback
        sudo snap install --classic certbot
        sudo snap set certbot trust-plugin-with-root=ok
        sudo snap install certbot-dns-cloudflare
        sudo ln -sf /snap/bin/certbot /usr/bin/certbot || true
    else
        log ERROR "Unable to determine package manager. Please install certbot manually."
        return 1
    fi

    log INFO "✓ Certbot installed successfully"
}

# Create Cloudflare credentials file
create_cloudflare_creds() {
    log INFO "Creating Cloudflare credentials file..."

    if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        # Using API Token (recommended)
        log DEBUG "Using Cloudflare API Token"
        cat > "$CLOUDFLARE_CREDS" <<EOF
# Cloudflare API Token (recommended)
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF
    elif [[ -n "${CLOUDFLARE_API_KEY:-}" ]] && [[ -n "${CLOUDFLARE_EMAIL:-}" ]]; then
        # Using Global API Key
        log DEBUG "Using Cloudflare Global API Key"
        cat > "$CLOUDFLARE_CREDS" <<EOF
# Cloudflare Global API Key
dns_cloudflare_email = ${CLOUDFLARE_EMAIL}
dns_cloudflare_api_key = ${CLOUDFLARE_API_KEY}
EOF
    else
        log ERROR "Neither API Token nor (Email + API Key) provided"
        return 1
    fi

    chmod 600 "$CLOUDFLARE_CREDS"
    log INFO "✓ Cloudflare credentials file created"
}

# Test Cloudflare API connection
test_cloudflare_api() {
    log INFO "Testing Cloudflare API connection..."

    local response
    if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            "https://api.cloudflare.com/client/v4/user/tokens/verify")
    elif [[ -n "${CLOUDFLARE_API_KEY:-}" ]] && [[ -n "${CLOUDFLARE_EMAIL:-}" ]]; then
        response=$(curl -s -w "\n%{http_code}" \
            -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
            -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
            "https://api.cloudflare.com/client/v4/user/tokens/verify")
    else
        return 1
    fi

    local http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" == "200" ]]; then
        log INFO "✓ Cloudflare API connection successful"
        return 0
    else
        log WARN "Cloudflare API test returned code: $http_code"
        log WARN "Proceeding anyway, certbot will validate..."
        return 0
    fi
}

# Check if certificate exists and is valid
check_existing_cert() {
    if [[ ! -f "$CERT_DIR/fullchain.pem" ]]; then
        log INFO "No existing certificate found"
        return 1
    fi

    # Check if certificate is valid for at least 7 days
    if openssl x509 -checkend 604800 -noout -in "$CERT_DIR/fullchain.pem" >/dev/null 2>&1; then
        log INFO "Existing certificate is valid for at least 7 more days"

        # Show expiry info
        local expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.pem" | cut -d= -f2)
        log INFO "Certificate expires: $expiry"
        return 0
    else
        log WARN "Certificate expires within 7 days or is invalid"
        return 1
    fi
}

# Request Let's Encrypt certificate
request_certificate() {
    log INFO "Requesting Let's Encrypt certificate for ${DOMAIN} and *.${DOMAIN}..."

    # Build certbot command
    local certbot_cmd=(
        certbot certonly
        --dns-cloudflare
        --dns-cloudflare-credentials "$CLOUDFLARE_CREDS"
        --dns-cloudflare-propagation-seconds 60
        -d "${DOMAIN}"
        -d "*.${DOMAIN}"
        --agree-tos
        --email "${CERTBOT_EMAIL}"
        --non-interactive
        --expand
    )

    # Add force-renewal if certificate exists but is expiring
    if [[ -f "$LETSENCRYPT_DIR/fullchain.pem" ]]; then
        log INFO "Existing Let's Encrypt certificate found, will attempt renewal if needed"
    fi

    # Run certbot
    if sudo "${certbot_cmd[@]}"; then
        log INFO "✓ Certificate obtained successfully"
        return 0
    else
        log ERROR "Failed to obtain certificate from Let's Encrypt"
        return 1
    fi
}

# Copy certificates to target directory
copy_certificates() {
    log INFO "Copying certificates to ${CERT_DIR}..."

    if [[ ! -d "$LETSENCRYPT_DIR" ]]; then
        log ERROR "Let's Encrypt directory not found: $LETSENCRYPT_DIR"
        return 1
    fi

    if [[ ! -f "$LETSENCRYPT_DIR/fullchain.pem" ]] || [[ ! -f "$LETSENCRYPT_DIR/privkey.pem" ]]; then
        log ERROR "Certificate files not found in $LETSENCRYPT_DIR"
        return 1
    fi

    # Create target directory
    sudo mkdir -p "$CERT_DIR"

    # Copy certificates (follow symlinks)
    sudo cp -L "$LETSENCRYPT_DIR/fullchain.pem" "$CERT_DIR/"
    sudo cp -L "$LETSENCRYPT_DIR/privkey.pem" "$CERT_DIR/"

    # Set proper permissions
    sudo chmod 644 "$CERT_DIR/fullchain.pem"
    sudo chmod 600 "$CERT_DIR/privkey.pem"

    # Try to set ownership to current user (may fail in CI, that's ok)
    sudo chown -R "$(id -u):$(id -g)" "$CERT_DIR" 2>/dev/null || true

    log INFO "✓ Certificates copied successfully"
    log INFO "  Fullchain: $CERT_DIR/fullchain.pem"
    log INFO "  Private key: $CERT_DIR/privkey.pem"
}

# Show certificate information
show_cert_info() {
    if [[ ! -f "$CERT_DIR/fullchain.pem" ]]; then
        log WARN "No certificate found to display"
        return 1
    fi

    log INFO "Certificate Information:"
    echo ""
    openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -issuer -subject -dates 2>/dev/null | sed 's/^/  /'
    echo ""
}

# Generate self-signed fallback certificate
generate_fallback_cert() {
    log WARN "Generating self-signed fallback certificate..."
    log WARN "This is for testing only and will show browser warnings"

    sudo mkdir -p "$CERT_DIR"

    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/privkey.pem" \
        -out "$CERT_DIR/fullchain.pem" \
        -subj "/C=CA/ST=Ontario/L=Toronto/O=Freddy/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN}" 2>/dev/null || {
            log ERROR "Failed to generate self-signed certificate"
            return 1
        }

    sudo chmod 644 "$CERT_DIR/fullchain.pem"
    sudo chmod 600 "$CERT_DIR/privkey.pem"
    sudo chown -R "$(id -u):$(id -g)" "$CERT_DIR" 2>/dev/null || true

    log INFO "✓ Self-signed certificate generated"
}

# Cleanup function
cleanup() {
    if [[ -f "$CLOUDFLARE_CREDS" ]]; then
        rm -f "$CLOUDFLARE_CREDS"
    fi
}

trap cleanup EXIT

# Main execution
main() {
    log INFO "=== CI/CD SSL Certificate Setup ==="
    log INFO "Domain: ${DOMAIN}"
    log INFO "Target directory: ${CERT_DIR}"
    echo ""

    # Check if we already have a valid certificate
    if check_existing_cert; then
        log INFO "✓ Valid certificate already exists, skipping generation"
        show_cert_info
        exit 0
    fi

    # Check environment variables
    if ! check_env_vars; then
        log ERROR "Environment variables not properly configured"
        log INFO "Attempting to generate self-signed fallback certificate..."
        if generate_fallback_cert; then
            show_cert_info
            exit 0
        else
            exit 1
        fi
    fi

    # Install certbot if needed
    if ! install_certbot; then
        log ERROR "Failed to install certbot"
        log INFO "Attempting to generate self-signed fallback certificate..."
        generate_fallback_cert
        exit 1
    fi

    # Create Cloudflare credentials
    if ! create_cloudflare_creds; then
        log ERROR "Failed to create Cloudflare credentials"
        generate_fallback_cert
        exit 1
    fi

    # Test API connection (non-blocking)
    test_cloudflare_api || true

    # Request certificate
    if ! request_certificate; then
        log ERROR "Failed to obtain Let's Encrypt certificate"
        log INFO "Attempting to generate self-signed fallback certificate..."
        generate_fallback_cert
        exit 1
    fi

    # Copy certificates
    if ! copy_certificates; then
        log ERROR "Failed to copy certificates"
        exit 1
    fi

    # Show certificate information
    show_cert_info

    log INFO "=== SSL Certificate Setup Complete ==="
    log INFO "✓ Let's Encrypt certificate installed successfully"
    log INFO "✓ Certificates available at: ${CERT_DIR}"

    # Docker volume mount reminder
    if is_ci; then
        echo ""
        log INFO "📝 Docker Compose volume mapping is configured as:"
        log INFO "   - ${CERT_DIR}:/etc/letsencrypt-volume:ro"
    fi
}

main "$@"
