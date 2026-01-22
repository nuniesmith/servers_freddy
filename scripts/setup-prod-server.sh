#!/bin/sh
# =============================================================================
# Production Server Setup Script for FREDDY
# Personal Services Server (Photos, Cloud Storage, Home Automation)
# =============================================================================
#
# Usage:
#   chmod +x setup-prod-server.sh
#   sudo ./setup-prod-server.sh
#
# This script will:
#   - Detect the Linux distribution
#   - Install minimal production packages
#   - Install Docker and container runtime
#   - Install/configure nginx reverse proxy dependencies
#   - Apply security hardening
#   - Create/configure 'actions' user for CI/CD (SSH key only)
#   - Setup SSH with secure configuration
#   - Configure firewall for web services
#   - Setup SSL certificate directories
#   - Optionally run generate-secrets.sh automatically
#
# Services hosted on Freddy:
#   - nginx (reverse proxy for all 7gram.xyz services)
#   - PhotoPrism (photo management)
#   - Nextcloud (cloud storage)
#   - Home Assistant (home automation)
#   - Audiobookshelf (audiobooks/podcasts)
#
# =============================================================================

set -e

# Server Configuration
SERVER_NAME="freddy"
SERVER_DESCRIPTION="Personal Services Server"
DOMAIN="7gram.xyz"
PROJECT_PATH="/home/actions/freddy"

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

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

# =============================================================================
# Detect OS Distribution
# =============================================================================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_NAME="$PRETTY_NAME"
        DISTRO_VERSION="$VERSION_ID"

        case "$ID" in
            ubuntu|debian|pop|linuxmint|elementary|zorin)
                DISTRO_FAMILY="debian"
                PKG_MANAGER="apt"
                ;;
            fedora|rhel|centos|rocky|alma|nobara)
                DISTRO_FAMILY="fedora"
                PKG_MANAGER="dnf"
                if ! command -v dnf >/dev/null 2>&1; then
                    PKG_MANAGER="yum"
                fi
                ;;
            arch|manjaro|endeavouros|garuda|artix)
                DISTRO_FAMILY="arch"
                PKG_MANAGER="pacman"
                ;;
            *)
                case "$ID_LIKE" in
                    *debian*|*ubuntu*)
                        DISTRO_FAMILY="debian"
                        PKG_MANAGER="apt"
                        ;;
                    *fedora*|*rhel*)
                        DISTRO_FAMILY="fedora"
                        PKG_MANAGER="dnf"
                        ;;
                    *arch*)
                        DISTRO_FAMILY="arch"
                        PKG_MANAGER="pacman"
                        ;;
                    *)
                        DISTRO_FAMILY="unknown"
                        PKG_MANAGER="unknown"
                        ;;
                esac
                ;;
        esac
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

# =============================================================================
# Package Installation Functions
# =============================================================================
install_packages_debian() {
    log_info "Installing packages using apt..."
    apt-get update
    apt-get install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        jq \
        vim-tiny \
        htop \
        net-tools \
        openssh-server \
        openssl \
        sudo \
        fail2ban \
        ufw \
        logrotate \
        unattended-upgrades \
        certbot \
        dnsutils

    dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true
}

install_packages_fedora() {
    log_info "Installing packages using $PKG_MANAGER..."
    $PKG_MANAGER install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg2 \
        jq \
        vim-minimal \
        htop \
        net-tools \
        openssh-server \
        openssl \
        sudo \
        fail2ban \
        firewalld \
        logrotate \
        dnf-automatic \
        certbot \
        bind-utils

    systemctl enable --now dnf-automatic-install.timer 2>/dev/null || true
}

install_packages_arch() {
    log_info "Installing packages using pacman..."
    pacman -Syu --noconfirm
    pacman -S --noconfirm --needed \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        jq \
        vim \
        htop \
        net-tools \
        openssh \
        openssl \
        sudo \
        fail2ban \
        ufw \
        logrotate \
        certbot \
        bind
}

install_packages() {
    case "$DISTRO_FAMILY" in
        debian) install_packages_debian ;;
        fedora) install_packages_fedora ;;
        arch) install_packages_arch ;;
        *)
            log_error "Unsupported distribution family: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
}

# =============================================================================
# Docker Installation Functions
# =============================================================================
install_docker_debian() {
    log_info "Installing Docker on Debian/Ubuntu..."

    if command -v docker >/dev/null 2>&1; then
        log_warn "Docker is already installed ($(docker --version))"
        return
    fi

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$DISTRO_ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO_ID \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log_success "Docker installed successfully"
}

install_docker_fedora() {
    log_info "Installing Docker on Fedora/RHEL..."

    if command -v docker >/dev/null 2>&1; then
        log_warn "Docker is already installed ($(docker --version))"
        return
    fi

    $PKG_MANAGER config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || true

    if [ "$DISTRO_ID" = "rhel" ] || [ "$DISTRO_ID" = "centos" ] || [ "$DISTRO_ID" = "rocky" ] || [ "$DISTRO_ID" = "alma" ]; then
        $PKG_MANAGER config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || true
    fi

    $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log_success "Docker installed successfully"
}

install_docker_arch() {
    log_info "Installing Docker on Arch Linux..."

    if command -v docker >/dev/null 2>&1; then
        log_warn "Docker is already installed ($(docker --version))"
        return
    fi

    pacman -S --noconfirm docker docker-compose docker-buildx

    systemctl enable docker
    systemctl start docker

    log_success "Docker installed successfully"
}

install_docker() {
    case "$DISTRO_FAMILY" in
        debian) install_docker_debian ;;
        fedora) install_docker_fedora ;;
        arch) install_docker_arch ;;
        *)
            log_error "Unsupported distribution for Docker: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
}

# =============================================================================
# Docker Security Hardening
# =============================================================================
harden_docker() {
    log_info "Applying Docker security hardening..."

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true,
    "storage-driver": "overlay2"
}
EOF

    systemctl restart docker 2>/dev/null || true

    log_success "Docker security hardening applied"
}

# =============================================================================
# Tailscale Installation
# =============================================================================
install_tailscale() {
    if command -v tailscale >/dev/null 2>&1; then
        log_warn "Tailscale is already installed"
        return
    fi

    log_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log_success "Tailscale installed"
}

# =============================================================================
# User Setup
# =============================================================================
setup_users() {
    log_info "Setting up users..."

    REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"

    # Create actions user for CI/CD
    if id "actions" >/dev/null 2>&1; then
        log_warn "User 'actions' already exists"
    else
        useradd -m -s /bin/bash -c "GitHub Actions CI/CD User" actions
        log_success "User 'actions' created"
    fi

    # Add actions to docker group
    usermod -aG docker actions
    log_success "User 'actions' added to docker group"

    # Configure the user who ran sudo
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        if id "$REAL_USER" >/dev/null 2>&1; then
            if ! groups "$REAL_USER" | grep -q docker; then
                usermod -aG docker "$REAL_USER"
                log_success "User '$REAL_USER' added to docker group"
            fi
        fi
    fi

    # Disable password login for actions (SSH key only)
    passwd -l actions 2>/dev/null || true
    log_info "Password login disabled for 'actions' user (SSH key only)"

    # Set secure umask
    echo "umask 027" >> /home/actions/.bashrc
}

# =============================================================================
# SSH Security Hardening
# =============================================================================
setup_ssh() {
    log_info "Setting up SSH with security hardening..."

    ACTIONS_HOME="/home/actions"
    SSH_DIR="$ACTIONS_HOME/.ssh"

    sudo -u actions mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    sudo -u actions touch "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"

    if [ ! -f /etc/ssh/sshd_config.bak ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    fi

    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-freddy-hardening.conf <<'EOF'
# Freddy Server SSH Hardening

# Disable root login
PermitRootLogin no

# Disable password authentication (use keys only)
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Disable empty passwords
PermitEmptyPasswords no

# Limit authentication attempts
MaxAuthTries 3
MaxSessions 5

# Set login grace time
LoginGraceTime 30

# Disable X11 forwarding
X11Forwarding no

# Use only Protocol 2
Protocol 2

# Strong ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# Strong MACs only
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Strong key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Log level
LogLevel VERBOSE

# Client alive settings
ClientAliveInterval 300
ClientAliveCountMax 2

# Allow actions and jordan users
AllowUsers actions jordan
EOF

    case "$DISTRO_FAMILY" in
        debian|fedora)
            systemctl enable sshd 2>/dev/null || systemctl enable ssh 2>/dev/null || true
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
            ;;
        arch)
            systemctl enable sshd
            systemctl restart sshd
            ;;
    esac

    log_success "SSH hardening applied"
}

# =============================================================================
# Firewall Setup (Web Server Configuration)
# =============================================================================
setup_firewall() {
    log_info "Setting up firewall for web services..."

    case "$DISTRO_FAMILY" in
        debian|arch)
            if command -v ufw >/dev/null 2>&1; then
                ufw --force reset
                ufw default deny incoming
                ufw default allow outgoing

                # SSH
                ufw allow ssh

                # HTTP/HTTPS (nginx reverse proxy)
                ufw allow 80/tcp
                ufw allow 443/tcp

                # Tailscale (allow all traffic from Tailscale network)
                ufw allow in on tailscale0

                ufw --force enable
                log_success "UFW firewall configured for web services"
            fi
            ;;
        fedora)
            if command -v firewall-cmd >/dev/null 2>&1; then
                systemctl enable firewalld
                systemctl start firewalld

                firewall-cmd --permanent --add-service=ssh
                firewall-cmd --permanent --add-service=http
                firewall-cmd --permanent --add-service=https

                # Trust Tailscale interface
                firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 2>/dev/null || true

                firewall-cmd --reload
                log_success "Firewalld configured for web services"
            fi
            ;;
    esac
}

# =============================================================================
# Fail2ban Setup
# =============================================================================
setup_fail2ban() {
    log_info "Configuring fail2ban..."

    if command -v fail2ban-client >/dev/null 2>&1; then
        cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400
EOF

        if [ "$DISTRO_FAMILY" = "fedora" ]; then
            sed -i 's|/var/log/auth.log|/var/log/secure|g' /etc/fail2ban/jail.local
        fi

        systemctl enable fail2ban
        systemctl restart fail2ban

        log_success "Fail2ban configured"
    fi
}

# =============================================================================
# System Hardening
# =============================================================================
apply_system_hardening() {
    log_info "Applying system hardening..."

    cat > /etc/sysctl.d/99-freddy-hardening.conf <<'EOF'
# Freddy Server Hardening

# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Increase system file descriptor limit
fs.file-max = 65535

# Increase inotify limits for Docker and file sync
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Virtual memory tuning
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
EOF

    sysctl --system 2>/dev/null || sysctl -p /etc/sysctl.d/99-freddy-hardening.conf

    chmod 600 /etc/shadow 2>/dev/null || true
    chmod 600 /etc/gshadow 2>/dev/null || true
    chmod 644 /etc/passwd
    chmod 644 /etc/group

    echo "* hard core 0" >> /etc/security/limits.conf

    log_success "System hardening applied"
}

# =============================================================================
# Directory Setup for Freddy
# =============================================================================
setup_directories() {
    log_info "Creating Freddy directories..."

    ACTIONS_HOME="/home/actions"

    # Main project directory
    sudo -u actions mkdir -p "$ACTIONS_HOME/freddy"

    # Log and data directories
    sudo -u actions mkdir -p "$ACTIONS_HOME/logs"
    sudo -u actions mkdir -p "$ACTIONS_HOME/backups"
    sudo -u actions mkdir -p "$ACTIONS_HOME/.config"

    # SSL certificate directory (system-wide)
    mkdir -p /opt/ssl/7gram.xyz
    chown -R actions:actions /opt/ssl
    chmod 750 /opt/ssl
    chmod 750 /opt/ssl/7gram.xyz

    # Data directories for services (adjust paths as needed)
    mkdir -p /mnt/1tb/photos/originals
    mkdir -p /mnt/1tb/photoprism/storage
    mkdir -p /mnt/1tb/photoprism/postgres
    mkdir -p /mnt/1tb/nextcloud/config
    mkdir -p /mnt/1tb/nextcloud/data
    mkdir -p /mnt/1tb/nextcloud/postgres
    mkdir -p /mnt/1tb/homeassistant
    mkdir -p /mnt/1tb/nginx/config

    # Set ownership (if /mnt/1tb exists)
    if [ -d /mnt/1tb ]; then
        chown -R actions:actions /mnt/1tb 2>/dev/null || true
    fi

    # Set permissions
    chmod 750 "$ACTIONS_HOME"
    chmod 700 "$ACTIONS_HOME/logs"
    chmod 700 "$ACTIONS_HOME/backups"
    chmod 700 "$ACTIONS_HOME/.config"

    log_success "Directories created"
    log_info "Project path: $ACTIONS_HOME/freddy"
    log_info "SSL certificates: /opt/ssl/7gram.xyz"
}

# =============================================================================
# Environment Template for Freddy
# =============================================================================
create_env_template() {
    log_info "Creating .env template..."

    ACTIONS_HOME="/home/actions"
    ENV_FILE="$ACTIONS_HOME/freddy/.env.example"

    sudo -u actions mkdir -p "$ACTIONS_HOME/freddy"

    sudo -u actions tee "$ENV_FILE" > /dev/null <<'EOF'
# =============================================================================
# Freddy Server Environment Variables
# Personal Services Server (7gram.xyz)
# =============================================================================
# Copy this file to .env and fill in the values

# =============================================================================
# GENERAL
# =============================================================================
TZ=America/Toronto
PUID=1000
PGID=1000

# =============================================================================
# PHOTOPRISM
# =============================================================================
PHOTOPRISM_ADMIN_PASSWORD=changeme
PHOTOPRISM_DB_NAME=photoprism
PHOTOPRISM_DB_USER=photoprism
PHOTOPRISM_DB_PASSWORD=changeme

# =============================================================================
# NEXTCLOUD
# =============================================================================
NEXTCLOUD_DB_NAME=nextcloud
NEXTCLOUD_DB_USER=nextcloud
NEXTCLOUD_DB_PASSWORD=changeme

# =============================================================================
# PATHS
# =============================================================================
MEDIA_PATH_AUDIOBOOKS=/mnt/1tb/audiobooks

# =============================================================================
# SSL (managed by CI/CD)
# =============================================================================
SSL_EMAIL=your-email@example.com
SSL_DOMAIN=7gram.xyz
EOF

    chmod 600 "$ENV_FILE"
    chown actions:actions "$ENV_FILE"

    log_success ".env template created at $ENV_FILE"
}

# =============================================================================
# Logrotate Configuration
# =============================================================================
setup_logrotate() {
    log_info "Configuring log rotation..."

    cat > /etc/logrotate.d/freddy <<'EOF'
/home/actions/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 actions actions
    sharedscripts
}

/home/actions/freddy/services/nginx/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 actions actions
    sharedscripts
    postrotate
        docker exec nginx nginx -s reload 2>/dev/null || true
    endscript
}
EOF

    log_success "Log rotation configured"
}

# =============================================================================
# Main Setup Flow
# =============================================================================
main() {
    log_header "Freddy Server Setup - Personal Services"

    log_info "Server: $SERVER_NAME"
    log_info "Description: $SERVER_DESCRIPTION"
    log_info "Domain: $DOMAIN"
    printf "\n"

    detect_distro

    log_info "Detected OS: $DISTRO_NAME"
    log_info "Distribution Family: $DISTRO_FAMILY"
    log_info "Package Manager: $PKG_MANAGER"
    log_info "Architecture: $(uname -m)"
    printf "\n"

    if [ "$DISTRO_FAMILY" = "unknown" ]; then
        log_error "Unsupported distribution: $DISTRO_ID"
        exit 1
    fi

    # Step 1: Install packages
    log_info "Step 1/10: Installing packages..."
    install_packages
    log_success "Packages installed"
    printf "\n"

    # Step 2: Install Docker
    log_info "Step 2/10: Installing Docker..."
    install_docker
    docker --version
    docker compose version 2>/dev/null || true
    printf "\n"

    # Step 3: Harden Docker
    log_info "Step 3/10: Hardening Docker..."
    harden_docker
    printf "\n"

    # Step 4: Install Tailscale
    log_info "Step 4/10: Checking Tailscale..."
    if command -v tailscale >/dev/null 2>&1; then
        log_success "Tailscale already installed"
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "Not connected")
        log_info "Tailscale IP: $TAILSCALE_IP"
    else
        printf "Install Tailscale? (Y/n) "
        read -r reply
        if [ "$reply" != "n" ] && [ "$reply" != "N" ]; then
            install_tailscale
        fi
    fi
    printf "\n"

    # Step 5: Setup users
    log_info "Step 5/10: Setting up users..."
    setup_users
    printf "\n"

    # Step 6: Setup SSH
    log_info "Step 6/10: Setting up SSH..."
    setup_ssh
    printf "\n"

    # Step 7: Setup firewall
    log_info "Step 7/10: Configuring firewall..."
    setup_firewall
    printf "\n"

    # Step 8: Setup fail2ban
    log_info "Step 8/10: Configuring fail2ban..."
    setup_fail2ban
    printf "\n"

    # Step 9: Apply system hardening
    log_info "Step 9/10: Applying system hardening..."
    apply_system_hardening
    printf "\n"

    # Step 10: Create directories and configuration
    log_info "Step 10/10: Creating directories and configuration..."
    setup_directories
    create_env_template
    setup_logrotate
    printf "\n"

    # Run generate-secrets.sh if available
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    GENERATE_SECRETS_SCRIPT="$SCRIPT_DIR/generate-secrets.sh"

    if [ -f "$GENERATE_SECRETS_SCRIPT" ]; then
        printf "Generate secrets now? (Y/n) "
        read -r reply
        if [ "$reply" != "n" ] && [ "$reply" != "N" ]; then
            log_info "Running generate-secrets.sh..."
            chmod +x "$GENERATE_SECRETS_SCRIPT"
            "$GENERATE_SECRETS_SCRIPT"
        fi
    fi

    # =============================================================================
    # Summary
    # =============================================================================
    log_header "Freddy Server Setup Complete!"

    log_info "System Information:"
    printf "  Server: %s (%s)\n" "$SERVER_NAME" "$SERVER_DESCRIPTION"
    printf "  OS: %s\n" "$DISTRO_NAME"
    printf "  Architecture: %s\n" "$(uname -m)"
    printf "  CPU: %s cores\n" "$(nproc)"
    printf "  RAM: %s\n" "$(free -h | awk '/^Mem:/ {print $2}')"
    printf "  Disk: %s available\n" "$(df -h / | awk 'NR==2 {print $4}')"
    printf "\n"

    log_info "Services to be deployed:"
    printf "  • nginx (reverse proxy for %s)\n" "$DOMAIN"
    printf "  • PhotoPrism (photo.%s)\n" "$DOMAIN"
    printf "  • Nextcloud (nc.%s)\n" "$DOMAIN"
    printf "  • Home Assistant (home.%s)\n" "$DOMAIN"
    printf "  • Audiobookshelf (audiobook.%s)\n" "$DOMAIN"
    printf "\n"

    log_info "Security Features Applied:"
    printf "  ✓ SSH hardened (key-only authentication)\n"
    printf "  ✓ Firewall configured (HTTP/HTTPS/SSH)\n"
    printf "  ✓ Fail2ban protecting SSH and nginx\n"
    printf "  ✓ Docker security hardened\n"
    printf "  ✓ Kernel security parameters set\n"
    printf "\n"

    log_header "Next Steps"

    printf "${BOLD}${GREEN}1. Connect to Tailscale:${NC}\n"
    printf "   ${CYAN}sudo tailscale up${NC}\n\n"

    printf "${BOLD}${GREEN}2. Generate secrets:${NC}\n"
    printf "   ${CYAN}sudo ./generate-secrets.sh${NC}\n\n"

    printf "${BOLD}${GREEN}3. Clone the freddy repository:${NC}\n"
    printf "   ${CYAN}cd /home/actions && git clone git@github.com:nuniesmith/freddy.git${NC}\n\n"

    printf "${BOLD}${GREEN}4. Configure environment:${NC}\n"
    printf "   ${CYAN}cp /home/actions/freddy/.env.example /home/actions/freddy/.env${NC}\n"
    printf "   ${CYAN}nano /home/actions/freddy/.env${NC}\n\n"

    printf "${BOLD}${GREEN}5. Get Tailscale IP (for GitHub secrets):${NC}\n"
    printf "   ${CYAN}tailscale ip -4${NC}\n\n"

    printf "${BOLD}${GREEN}6. Test SSH connection (from remote):${NC}\n"
    printf "   ${CYAN}ssh actions@FREDDY_TAILSCALE_IP${NC}\n\n"

    log_header "GitHub Secrets Required"

    printf "Add these secrets to nuniesmith/freddy repository:\n\n"
    printf "  ${YELLOW}FREDDY_TAILSCALE_IP${NC}     - Tailscale IP address\n"
    printf "  ${YELLOW}SSH_KEY${NC}                 - SSH private key for actions user\n"
    printf "  ${YELLOW}SSH_USER${NC}                - actions\n"
    printf "  ${YELLOW}SSH_PORT${NC}                - 22\n"
    printf "  ${YELLOW}CLOUDFLARE_API_TOKEN${NC}    - Cloudflare API token\n"
    printf "  ${YELLOW}CLOUDFLARE_ZONE_ID${NC}      - Cloudflare zone ID for %s\n" "$DOMAIN"
    printf "  ${YELLOW}SSL_EMAIL${NC}               - Email for Let's Encrypt\n"
    printf "\n"

    log_success "Freddy server is ready!"
    printf "\n"
}

main "$@"
