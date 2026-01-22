#!/bin/sh
# =============================================================================
# Secrets Generation Script for FREDDY
# Personal Services Server (Photos, Cloud Storage, Home Automation)
# =============================================================================
#
# Usage:
#   chmod +x generate-secrets.sh
#   sudo ./generate-secrets.sh
#
# This script will:
#   - Generate SSH keys for the actions user
#   - Detect Tailscale IP address
#   - Generate secure passwords for services
#   - Create a credentials file for GitHub Secrets
#   - Output secrets in the format needed for GitHub Actions
#
# =============================================================================

set -e

# Server Configuration
SERVER_NAME="freddy"
SERVER_DESCRIPTION="Personal Services Server"
DOMAIN="7gram.xyz"
SECRET_PREFIX="FREDDY"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Log functions
log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
log_header() {
    printf "\n"
    printf "${BOLD}${CYAN}================================================================================${NC}\n"
    printf "${BOLD}${CYAN}  %s${NC}\n" "$*"
    printf "${BOLD}${CYAN}================================================================================${NC}\n"
    printf "\n"
}

# Function to generate secure password
generate_password() {
    openssl rand -base64 24 | tr -d "=+/" | cut -c1-24
}

# Function to generate hex secret
generate_hex_secret() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

# Check if openssl is available
if ! command -v openssl >/dev/null 2>&1; then
    log_error "OpenSSL is not installed. Please install it first."
    exit 1
fi

ACTIONS_HOME="/home/actions"

# Check if actions user exists
if ! id "actions" >/dev/null 2>&1; then
    log_error "User 'actions' does not exist. Please run setup-prod-server.sh first."
    exit 1
fi

log_header "Secrets Generation for $SERVER_NAME"

log_info "Server: $SERVER_NAME ($SERVER_DESCRIPTION)"
log_info "Domain: $DOMAIN"
log_info "Secret Prefix: ${SECRET_PREFIX}_"
printf "\n"

# =============================================================================
# Step 1: Detect Server Information
# =============================================================================
log_info "Step 1/4: Detecting server information..."

# Get server IP
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
log_info "Server IP: $SERVER_IP"

# Detect Tailscale IP
TAILSCALE_IP=""
if command -v tailscale >/dev/null 2>&1; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [ -n "$TAILSCALE_IP" ]; then
        log_success "Tailscale IP detected: $TAILSCALE_IP"
    else
        log_warn "Tailscale is installed but not connected"
        log_warn "Run 'sudo tailscale up' to connect to your tailnet"
    fi
else
    log_warn "Tailscale not installed"
fi

# Detect SSH port
SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi
log_info "SSH Port: $SSH_PORT"

# Detect hostname
HOSTNAME=$(hostname 2>/dev/null || echo "$SERVER_NAME")
log_info "Hostname: $HOSTNAME"

printf "\n"

# =============================================================================
# Step 2: Generate SSH Keys for Actions User
# =============================================================================
log_info "Step 2/4: Generating SSH keys for 'actions' user..."

SSH_DIR="$ACTIONS_HOME/.ssh"

# Ensure .ssh directory exists
sudo -u actions mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$SSH_DIR/id_ed25519" ]; then
    log_warn "SSH key already exists for actions user"
    printf "Do you want to regenerate it? This will invalidate the old key. (y/N) "
    read -r reply
    if [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
        sudo -u actions rm -f "$SSH_DIR/id_ed25519" "$SSH_DIR/id_ed25519.pub"
    else
        log_info "Using existing SSH key"
    fi
fi

if [ ! -f "$SSH_DIR/id_ed25519" ]; then
    sudo -u actions ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "actions@$HOSTNAME-$(date +%Y%m%d)"
    chmod 600 "$SSH_DIR/id_ed25519"
    chmod 644 "$SSH_DIR/id_ed25519.pub"
    log_success "SSH key generated"
fi

# Add public key to authorized_keys
if [ ! -f "$SSH_DIR/authorized_keys" ]; then
    sudo -u actions touch "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"
fi

PUB_KEY=$(cat "$SSH_DIR/id_ed25519.pub")
if ! grep -qF "$PUB_KEY" "$SSH_DIR/authorized_keys" 2>/dev/null; then
    echo "$PUB_KEY" >> "$SSH_DIR/authorized_keys"
    log_success "Public key added to authorized_keys"
else
    log_info "Public key already in authorized_keys"
fi

printf "\n"

# =============================================================================
# Step 3: Generate Application Secrets
# =============================================================================
log_info "Step 3/4: Generating application secrets..."

# PhotoPrism secrets
PHOTOPRISM_ADMIN_PASSWORD=$(generate_password)
PHOTOPRISM_DB_PASSWORD=$(generate_password)

# Nextcloud secrets
NEXTCLOUD_DB_PASSWORD=$(generate_password)
NEXTCLOUD_ADMIN_PASSWORD=$(generate_password)

# General secrets
SESSION_SECRET=$(generate_hex_secret 32)
ENCRYPTION_KEY=$(generate_hex_secret 32)

log_success "Application secrets generated"
printf "\n"

# =============================================================================
# Step 4: Output Credentials
# =============================================================================
log_info "Step 4/4: Saving credentials..."

# Read SSH keys
SSH_PRIVATE_KEY=$(cat "$SSH_DIR/id_ed25519")
SSH_PUBLIC_KEY=$(cat "$SSH_DIR/id_ed25519.pub")

# Create credentials file
CREDENTIALS_FILE="/tmp/${SERVER_NAME}_credentials_$(date +%s).txt"
touch "$CREDENTIALS_FILE"
chmod 600 "$CREDENTIALS_FILE"

cat > "$CREDENTIALS_FILE" <<EOF
# =============================================================================
# $SERVER_NAME Server Credentials
# Generated: $(date)
# Hostname: $HOSTNAME
# Server IP: $SERVER_IP
# Tailscale IP: ${TAILSCALE_IP:-Not configured}
# SSH Port: $SSH_PORT
# Domain: $DOMAIN
# =============================================================================

# =============================================================================
# GITHUB SECRETS - Copy these to your repository
# Repository: nuniesmith/freddy
# URL: https://github.com/nuniesmith/freddy/settings/secrets/actions
# =============================================================================

# -----------------------------------------------------------------------------
# SSH & DEPLOYMENT (Required for CI/CD)
# -----------------------------------------------------------------------------

# Secret Name: ${SECRET_PREFIX}_TAILSCALE_IP
# Description: Tailscale IP address for SSH connections
${SECRET_PREFIX}_TAILSCALE_IP=${TAILSCALE_IP:-CONFIGURE_TAILSCALE_FIRST}

# Secret Name: SSH_KEY
# Description: SSH private key (copy entire block including BEGIN/END lines)
SSH_KEY:
$SSH_PRIVATE_KEY

# Secret Name: SSH_USER
SSH_USER=actions

# Secret Name: SSH_PORT
SSH_PORT=$SSH_PORT

# -----------------------------------------------------------------------------
# CLOUDFLARE (Required for DNS and SSL)
# -----------------------------------------------------------------------------

# Secret Name: CLOUDFLARE_API_TOKEN
# Description: Get from Cloudflare Dashboard > My Profile > API Tokens
# Permissions needed: Zone:DNS:Edit for $DOMAIN
CLOUDFLARE_API_TOKEN=YOUR_CLOUDFLARE_API_TOKEN

# Secret Name: CLOUDFLARE_ZONE_ID
# Description: Found in Cloudflare Dashboard > $DOMAIN > Overview (right sidebar)
CLOUDFLARE_ZONE_ID=YOUR_ZONE_ID

# Secret Name: SSL_EMAIL
# Description: Email for Let's Encrypt certificate notifications
SSL_EMAIL=your-email@example.com

# -----------------------------------------------------------------------------
# TAILSCALE (Required for CI/CD network access)
# -----------------------------------------------------------------------------

# Secret Name: TAILSCALE_OAUTH_CLIENT_ID
# Description: Create at https://login.tailscale.com/admin/settings/oauth
TAILSCALE_OAUTH_CLIENT_ID=YOUR_OAUTH_CLIENT_ID

# Secret Name: TAILSCALE_OAUTH_SECRET
TAILSCALE_OAUTH_SECRET=YOUR_OAUTH_SECRET

# -----------------------------------------------------------------------------
# APPLICATION SECRETS (For .env file on server)
# -----------------------------------------------------------------------------

# PhotoPrism
PHOTOPRISM_ADMIN_PASSWORD=$PHOTOPRISM_ADMIN_PASSWORD
PHOTOPRISM_DB_PASSWORD=$PHOTOPRISM_DB_PASSWORD

# Nextcloud
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
NEXTCLOUD_DB_PASSWORD=$NEXTCLOUD_DB_PASSWORD

# General
SESSION_SECRET=$SESSION_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY

# =============================================================================
# SSH PUBLIC KEY (Reference - add to other servers if needed)
# =============================================================================
$SSH_PUBLIC_KEY

# =============================================================================
# QUICK REFERENCE
# =============================================================================
#
# GitHub Secrets to add:
#   - ${SECRET_PREFIX}_TAILSCALE_IP    = ${TAILSCALE_IP:-YOUR_TAILSCALE_IP}
#   - SSH_KEY                          = (entire private key above)
#   - SSH_USER                         = actions
#   - SSH_PORT                         = $SSH_PORT
#   - CLOUDFLARE_API_TOKEN             = (from Cloudflare)
#   - CLOUDFLARE_ZONE_ID               = (from Cloudflare)
#   - SSL_EMAIL                        = (your email)
#   - TAILSCALE_OAUTH_CLIENT_ID        = (from Tailscale)
#   - TAILSCALE_OAUTH_SECRET           = (from Tailscale)
#
# Test SSH connection:
#   ssh -p $SSH_PORT actions@${TAILSCALE_IP:-TAILSCALE_IP}
#
# =============================================================================
EOF

log_success "Credentials saved to: $CREDENTIALS_FILE"
printf "\n"

# =============================================================================
# Display Summary
# =============================================================================
log_header "Credentials Generated Successfully!"

printf "${BOLD}${YELLOW}⚠  IMPORTANT: Secure the credentials file${NC}\n"
printf "   Location: ${CYAN}%s${NC}\n\n" "$CREDENTIALS_FILE"

printf "${BOLD}${GREEN}View credentials:${NC}\n"
printf "   ${CYAN}cat %s${NC}\n\n" "$CREDENTIALS_FILE"

log_header "GitHub Secrets Setup"

printf "${BOLD}1. Go to your GitHub repository settings:${NC}\n"
printf "   ${CYAN}https://github.com/nuniesmith/freddy/settings/secrets/actions${NC}\n\n"

printf "${BOLD}2. Add these REQUIRED secrets:${NC}\n\n"

printf "   ${YELLOW}${SECRET_PREFIX}_TAILSCALE_IP${NC}\n"
printf "   Value: ${CYAN}%s${NC}\n\n" "${TAILSCALE_IP:-⚠️ CONFIGURE TAILSCALE FIRST}"

printf "   ${YELLOW}SSH_KEY${NC}\n"
printf "   Value: (entire private key from credentials file)\n\n"

printf "   ${YELLOW}SSH_USER${NC}\n"
printf "   Value: ${CYAN}actions${NC}\n\n"

printf "   ${YELLOW}SSH_PORT${NC}\n"
printf "   Value: ${CYAN}%s${NC}\n\n" "$SSH_PORT"

printf "   ${YELLOW}CLOUDFLARE_API_TOKEN${NC}\n"
printf "   Value: (from Cloudflare Dashboard)\n\n"

printf "   ${YELLOW}CLOUDFLARE_ZONE_ID${NC}\n"
printf "   Value: (from Cloudflare Dashboard)\n\n"

printf "   ${YELLOW}SSL_EMAIL${NC}\n"
printf "   Value: (your email for Let's Encrypt)\n\n"

printf "   ${YELLOW}TAILSCALE_OAUTH_CLIENT_ID${NC}\n"
printf "   Value: (from Tailscale Admin Console)\n\n"

printf "   ${YELLOW}TAILSCALE_OAUTH_SECRET${NC}\n"
printf "   Value: (from Tailscale Admin Console)\n\n"

log_header "Quick Commands"

printf "View full credentials file:\n"
printf "   ${CYAN}cat %s${NC}\n\n" "$CREDENTIALS_FILE"

printf "View SSH private key:\n"
printf "   ${CYAN}cat %s/.ssh/id_ed25519${NC}\n\n" "$ACTIONS_HOME"

printf "View SSH public key:\n"
printf "   ${CYAN}cat %s/.ssh/id_ed25519.pub${NC}\n\n" "$ACTIONS_HOME"

printf "Get Tailscale IP:\n"
printf "   ${CYAN}tailscale ip -4${NC}\n\n"

printf "Test SSH connection (from another machine):\n"
printf "   ${CYAN}ssh -p %s actions@%s${NC}\n\n" "$SSH_PORT" "${TAILSCALE_IP:-TAILSCALE_IP}"

log_header "Environment File Setup"

printf "Copy application secrets to .env file:\n"
printf "   ${CYAN}nano /home/actions/freddy/.env${NC}\n\n"

printf "Add these values:\n"
printf "   PHOTOPRISM_ADMIN_PASSWORD=%s\n" "$PHOTOPRISM_ADMIN_PASSWORD"
printf "   PHOTOPRISM_DB_PASSWORD=%s\n" "$PHOTOPRISM_DB_PASSWORD"
printf "   NEXTCLOUD_DB_PASSWORD=%s\n" "$NEXTCLOUD_DB_PASSWORD"
printf "\n"

log_header "Security Best Practices"

printf "${YELLOW}✓${NC} Keep the credentials file secure\n"
printf "${YELLOW}✓${NC} Delete the credentials file after copying to GitHub Secrets:\n"
printf "   ${CYAN}sudo rm %s${NC}\n" "$CREDENTIALS_FILE"
printf "${YELLOW}✓${NC} Never commit secrets to version control\n"
printf "${YELLOW}✓${NC} Rotate secrets periodically\n"
printf "${YELLOW}✓${NC} Use strong, unique passwords for each service\n"
printf "\n"

log_success "Secrets generation complete for $SERVER_NAME!"
printf "\n"

exit 0
