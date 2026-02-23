#!/usr/bin/env bash
#
# ============================================================================
# FREDDY - Personal & Authentication Services Management Script
# ============================================================================
# Simple wrapper for managing Freddy's Docker services
# Services: nginx, photoprism, nextcloud, homeassistant, audiobookshelf
#
# Usage:
#   ./run.sh start [prod]    # Start all services (pull images first in prod)
#   ./run.sh stop            # Stop all services
#   ./run.sh restart         # Restart all services
#   ./run.sh status          # Show service status
#   ./run.sh logs [service]  # View logs (optionally for specific service)
#   ./run.sh pull            # Pull latest images
#   ./run.sh health          # Check service health
#   ./run.sh clean           # Clean up unused Docker resources
#   ./run.sh occ <args>      # Run Nextcloud occ command as www-data
#   ./run.sh scan [path]     # Rescan Nextcloud files (all or specific path)
#   ./run.sh reset-nextcloud-db  # Reset Nextcloud PostgreSQL database (fixes auth issues)
#   ./run.sh setup-env       # Generate .env file with defaults (for CI/CD)
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Docker Compose file
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

# Docker compose command
if [ -f "$ENV_FILE" ]; then
    DC="docker compose --env-file $ENV_FILE"
else
    DC="docker compose"
fi

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running"
        exit 1
    fi

    if ! docker compose version > /dev/null 2>&1; then
        print_error "Docker Compose V2 is not available"
        exit 1
    fi
}

check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "docker-compose.yml not found in $SCRIPT_DIR"
        exit 1
    fi
}

# ============================================================================
# Command Functions
# ============================================================================

cmd_start() {
    local mode=$1
    shift || true

    print_header "🏠 Starting Freddy Services"

    # Load environment if exists
    if [ -f "$ENV_FILE" ]; then
        set -a && source "$ENV_FILE" && set +a
        print_success "Environment loaded from .env"
    else
        print_warning "No .env file found, using defaults"
    fi

    # Pull images first in prod mode
    if [ "$mode" = "prod" ]; then
        print_info "Pulling latest images..."
        $DC -f "$COMPOSE_FILE" pull --ignore-pull-failures 2>&1 || true
        print_success "Images pulled"

        print_info "Building custom images..."
        $DC -f "$COMPOSE_FILE" build --parallel 2>&1 || true
        print_success "Images built"
    fi

    # Start services
    print_info "Starting containers..."
    $DC -f "$COMPOSE_FILE" up -d "$@"

    print_success "Services started"

    # Wait a moment for containers to initialize
    sleep 5

    # Show status
    cmd_status

    echo ""
    print_success "Freddy is ready!"
    echo ""
    print_info "Access points (Freddy services):"
    echo "  Dashboard:      https://7gram.xyz (or https://freddy.7gram.xyz)"
    echo "  PhotoPrism:     https://photo.7gram.xyz"
    echo "  Nextcloud:      https://nc.7gram.xyz"
    echo "  Home Assistant: https://home.7gram.xyz"
    echo "  Audiobookshelf: https://abs.7gram.xyz"
    echo ""
    print_info "View logs: ./run.sh logs [service]"
    print_info "Check health: ./run.sh health"
}

cmd_stop() {
    print_header "🛑 Stopping Freddy Services"

    $DC -f "$COMPOSE_FILE" down --remove-orphans "$@"

    print_success "Services stopped"
}

cmd_restart() {
    local service=$1

    if [ -n "$service" ]; then
        print_header "🔄 Restarting $service"
        $DC -f "$COMPOSE_FILE" restart "$service"
    else
        print_header "🔄 Restarting All Freddy Services"
        $DC -f "$COMPOSE_FILE" restart
    fi

    print_success "Restart complete"
}

cmd_status() {
    print_header "📊 Freddy Service Status"
    $DC -f "$COMPOSE_FILE" ps
}

cmd_logs() {
    local service=$1

    if [ -n "$service" ]; then
        $DC -f "$COMPOSE_FILE" logs -f "$service"
    else
        $DC -f "$COMPOSE_FILE" logs -f
    fi
}

cmd_pull() {
    print_header "📥 Pulling Latest Images"

    $DC -f "$COMPOSE_FILE" pull

    print_success "Images updated"
    print_info "Run './run.sh restart' to apply updates"
}

cmd_health() {
    print_header "🏥 Freddy Health Check"

    local services=("nginx" "photoprism" "nextcloud" "nextcloud-cron" "homeassistant" "audiobookshelf" "photoprism-postgres" "nextcloud-postgres")

    for service in "${services[@]}"; do
        local status=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "no-healthcheck")
        local running=$(docker inspect --format='{{.State.Running}}' "$service" 2>/dev/null || echo "false")

        if [ "$running" = "true" ]; then
            if [ "$status" = "healthy" ]; then
                print_success "$service: healthy"
            elif [ "$status" = "unhealthy" ]; then
                print_error "$service: unhealthy"
            elif [ "$status" = "starting" ]; then
                print_warning "$service: starting"
            else
                print_info "$service: running (no health check)"
            fi
        else
            print_error "$service: not running"
        fi
    done

    echo ""
    print_info "Disk usage:"
    df -h / | tail -1 | awk '{print "  Used: "$3" / "$2" ("$5" used)"}'

    echo ""
    print_info "Memory usage:"
    free -h | awk '/^Mem:/ {print "  Used: "$3" / "$2}'
}

cmd_clean() {
    print_header "🧹 Cleaning Docker Resources"

    echo "This will remove:"
    echo "  - Stopped containers"
    echo "  - Unused networks"
    echo "  - Dangling images"
    echo "  - Build cache"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removing stopped containers..."
        docker container prune -f

        print_info "Removing unused networks..."
        docker network prune -f

        print_info "Removing dangling images..."
        docker image prune -f

        print_info "Removing build cache..."
        docker builder prune -f

        print_success "Cleanup complete"

        echo ""
        print_info "Disk space recovered:"
        df -h / | tail -1 | awk '{print "  Available: "$4}'
    else
        print_info "Cancelled"
    fi
}

cmd_shell() {
    local service=$1

    if [ -z "$service" ]; then
        print_error "Service name required"
        print_info "Usage: ./run.sh shell <service>"
        print_info "Example: ./run.sh shell photoprism"
        exit 1
    fi

    print_info "Opening shell in $service..."
    $DC -f "$COMPOSE_FILE" exec "$service" /bin/sh || $DC -f "$COMPOSE_FILE" exec "$service" /bin/bash
}

cmd_update() {
    print_header "🔄 Updating Freddy Services"

    print_info "Pulling latest images..."
    $DC -f "$COMPOSE_FILE" pull

    print_info "Recreating containers with new images..."
    $DC -f "$COMPOSE_FILE" up -d --remove-orphans

    print_info "Cleaning up old images..."
    docker image prune -f

    print_success "Update complete"

    # Show status
    cmd_status
}

cmd_ssl_init() {
    local force=$1
    print_header "🔐 Initializing SSL Certificates"

    # Certificate directory
    CERT_DIR="/opt/ssl/7gram.xyz"
    DOMAIN="7gram.xyz"

    # Create directory
    sudo mkdir -p "$CERT_DIR" 2>/dev/null || true

    # Check if certs already exist and are valid LE certs
    if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
        # Check if it's a Let's Encrypt cert
        if openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -issuer 2>/dev/null | grep -q "Let's Encrypt"; then
            # Check if expires within 30 days
            if openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -checkend $((30*24*60*60)) >/dev/null 2>&1; then
                # Expires within 30 days, need new cert
                print_info "Existing LE certificate expires soon. Regenerating..."
            else
                # Valid LE cert, skip unless --force
                if [ "$force" != "--force" ]; then
                    print_warning "Valid Let's Encrypt certificates already exist"
                    print_info "Run './run.sh ssl-init --force' to force regeneration or './run.sh ssl-renew' for renewal"
                    return 0
                else
                    print_info "Force regenerating certificates..."
                fi
            fi
        else
            print_warning "Existing certificate is not from Let's Encrypt. Regenerating with LE..."
        fi
    fi

    # Check if Cloudflare creds exist
    CRED_FILE="/etc/letsencrypt/cloudflare.ini"
    if [ ! -f "$CRED_FILE" ]; then
        print_info "Setting up Cloudflare DNS credentials..."

        # Prompt for credentials
        read -p "Cloudflare Email: " CF_EMAIL
        read -p "Cloudflare Global API Key: " CF_API_KEY
        read -p "Your Email Address: " EMAIL

        # Create Cloudflare credentials
        sudo tee "$CRED_FILE" > /dev/null <<EOF
# Cloudflare API credentials
dns_cloudflare_email = $CF_EMAIL
dns_cloudflare_api_key = $CF_API_KEY
EOF
        sudo chmod 600 "$CRED_FILE"
    else
        print_info "Using existing Cloudflare credentials"
        # Extract email from creds file
        EMAIL=$(grep "dns_cloudflare_email" "$CRED_FILE" | cut -d'=' -f2 | tr -d ' ')
        if [ -z "$EMAIL" ]; then
            EMAIL="noreply@7gram.xyz"  # fallback
        fi
    fi

    print_info "Generating wildcard SSL certificate for $DOMAIN..."

    # Install certbot if needed
    if ! command -v certbot >/dev/null 2>&1; then
        print_info "Installing certbot..."
        sudo apt update
        sudo apt install -y certbot python3-pip
    fi
    if ! certbot plugins 2>/dev/null | grep -q dns-cloudflare; then
        print_info "Installing certbot dns-cloudflare plugin..."
        sudo apt install -y python3-certbot-dns-cloudflare
    fi

    # Generate certificate (force renewal if already exists)
    CERTBOT_ARGS=""
    if [ "$force" = "--force" ]; then
        CERTBOT_ARGS="--force-renewal"
    fi

    if sudo certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CRED_FILE" \
        $CERTBOT_ARGS \
        -d "$DOMAIN" \
        -d "*.$DOMAIN" \
        --agree-tos \
        --email "$EMAIL" \
        --non-interactive; then

        print_info "Copying certificates to $CERT_DIR..."

        # Copy certificates
        sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERT_DIR/"
        sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$CERT_DIR/"

        # Set permissions
        sudo chmod 644 "$CERT_DIR/fullchain.pem"
        sudo chmod 600 "$CERT_DIR/privkey.pem"

        print_success "SSL certificates initialized"

        # Reload nginx if running
        if docker ps | grep -q nginx; then
            print_info "Reloading nginx..."
            docker compose exec -T nginx nginx -s reload 2>/dev/null || print_warning "Could not reload nginx"
        fi

    else
        print_error "SSL certificate generation failed"
        return 1
    fi
}

cmd_occ() {
    if [ $# -eq 0 ]; then
        print_error "No occ command specified"
        echo ""
        print_info "Usage: ./run.sh occ <command> [args...]"
        echo ""
        echo "  Common commands:"
        echo "    ./run.sh occ status                    # Show Nextcloud status"
        echo "    ./run.sh occ files:scan --all          # Rescan all files"
        echo "    ./run.sh occ files:scan -p <user>      # Rescan specific user"
        echo "    ./run.sh occ maintenance:mode --on     # Enable maintenance mode"
        echo "    ./run.sh occ maintenance:mode --off    # Disable maintenance mode"
        echo "    ./run.sh occ app:list                  # List installed apps"
        echo "    ./run.sh occ db:add-missing-indices    # Add missing DB indices"
        echo "    ./run.sh occ config:list               # Show configuration"
        echo "    ./run.sh occ user:list                 # List users"
        exit 1
    fi

    print_info "Running: occ $*"
    docker exec -u www-data nextcloud php /var/www/html/occ "$@"
}

cmd_scan() {
    local path="${1:---all}"

    print_header "📂 Nextcloud File Scan"

    # Check if nextcloud container is running
    if ! docker ps --format '{{.Names}}' | grep -q '^nextcloud$'; then
        print_error "Nextcloud container is not running"
        print_info "Start services first: ./run.sh start"
        exit 1
    fi

    if [ "$path" = "--all" ] || [ "$path" = "all" ]; then
        print_info "Scanning all user files..."
        docker exec -u www-data nextcloud php /var/www/html/occ files:scan --all
    else
        print_info "Scanning path: $path"
        docker exec -u www-data nextcloud php /var/www/html/occ files:scan --path="$path"
    fi

    print_success "File scan complete"
}

cmd_reset_nextcloud_db() {
    print_header "🔄 Reset Nextcloud Installation"

    echo ""
    print_warning "⚠️  WARNING: This will perform a FULL Nextcloud reset!"
    echo ""
    echo "This operation will:"
    echo "  1. Stop Nextcloud and its database containers"
    echo "  2. Delete all PostgreSQL data      (/mnt/1tb/nextcloud/postgres)"
    echo "  3. Delete Nextcloud app files       (/mnt/1tb/nextcloud/html)"
    echo "  4. Delete Nextcloud config          (/mnt/1tb/nextcloud/config)"
    echo "  5. Re-extract fresh app files from the Docker image on next start"
    echo "  6. Reinitialize the database with current .env credentials"
    echo ""
    echo "This is useful when:"
    echo "  - You get 'Configuration was not read or initialized correctly'"
    echo "  - You have a password authentication error"
    echo "  - Database credentials don't match environment variables"
    echo "  - You want a completely fresh Nextcloud installation"
    echo ""
    print_warning "User files in /mnt/1tb/nextcloud/data will NOT be affected"
    echo ""
    read -p "Type 'YES' to confirm full reset: " -r
    echo

    if [[ $REPLY != "YES" ]]; then
        print_info "Cancelled - no changes made"
        return 0
    fi

    print_info "Stopping Nextcloud containers..."
    docker stop nextcloud nextcloud-cron nextcloud-postgres 2>/dev/null || true
    docker rm nextcloud nextcloud-cron nextcloud-postgres 2>/dev/null || true

    print_info "Removing PostgreSQL data..."
    if docker run --rm -v /mnt/1tb:/mnt busybox sh -c "rm -rf /mnt/nextcloud/postgres/*"; then
        print_success "PostgreSQL data removed"
    else
        print_error "Failed to remove PostgreSQL data"
        print_info "You may need to run: sudo rm -rf /mnt/1tb/nextcloud/postgres/*"
        return 1
    fi

    print_info "Removing Nextcloud config (stale config.php)..."
    if docker run --rm -v /mnt/1tb:/mnt busybox sh -c "rm -rf /mnt/nextcloud/config/*"; then
        print_success "Config removed"
    else
        print_error "Failed to remove config"
        print_info "You may need to run: sudo rm -rf /mnt/1tb/nextcloud/config/*"
        return 1
    fi

    print_info "Removing Nextcloud app files (will be re-extracted from image)..."
    if docker run --rm -v /mnt/1tb:/mnt busybox sh -c "rm -rf /mnt/nextcloud/html/*"; then
        print_success "App files removed"
    else
        print_error "Failed to remove app files"
        print_info "You may need to run: sudo rm -rf /mnt/1tb/nextcloud/html/*"
        return 1
    fi

    # Re-create directories with correct ownership (www-data = UID 33)
    print_info "Re-creating directories with correct ownership..."
    docker run --rm -v /mnt/1tb:/mnt busybox sh -c "\
        mkdir -p /mnt/nextcloud/html /mnt/nextcloud/config /mnt/nextcloud/data /mnt/nextcloud/postgres \
        && chown -R 33:33 /mnt/nextcloud/html /mnt/nextcloud/config /mnt/nextcloud/data \
        && echo 'Directories ready'"
    print_success "Directories recreated"

    print_success "Nextcloud full reset complete"
    echo ""
    print_info "Next steps:"
    echo "  1. Start services: ./run.sh start"
    echo "  2. Wait for Nextcloud to initialize (may take 2-3 minutes)"
    echo "  3. Check logs: ./run.sh logs nextcloud"
    echo "  4. Verify status: ./run.sh occ status"
    echo ""
    print_info "The entrypoint will re-extract Nextcloud from the Docker image,"
    print_info "create a fresh config.php, and run the post-installation hook."
    print_info "Custom configs (reverse-proxy, tuning) are applied automatically."
}

cmd_setup_env() {
    # Non-interactive .env generator for CI/CD
    # Preserves existing .env if present and valid
    if [ -f "$ENV_FILE" ] && [ -s "$ENV_FILE" ]; then
        local key_count
        key_count=$(grep -c '^[A-Z_]' "$ENV_FILE" 2>/dev/null || echo "0")
        if [ "$key_count" -ge 5 ]; then
            print_info ".env already exists with $key_count keys, keeping it"
            return 0
        fi
    fi

    print_info "Generating .env with defaults..."

    # Helper to generate random passwords
    gen_pass() {
        openssl rand -base64 24 2>/dev/null | tr -d '/+=' | head -c 16 || \
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1
    }

    cat > "$ENV_FILE" << EOF
# Freddy Home Server - Auto-generated by run.sh setup-env
TZ=${TZ:-America/Toronto}
PUID=${PUID:-1000}
PGID=${PGID:-1000}
PHOTOPRISM_ADMIN_PASSWORD=$(gen_pass)
PHOTOPRISM_DB_NAME=photoprism
PHOTOPRISM_DB_USER=photoprism
PHOTOPRISM_DB_PASSWORD=$(gen_pass)
NEXTCLOUD_DB_NAME=nextcloud
NEXTCLOUD_DB_USER=nextcloud
NEXTCLOUD_DB_PASSWORD=$(gen_pass)
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=$(gen_pass)
SULLIVAN_TAILSCALE_IP=${SULLIVAN_TAILSCALE_IP:-100.87.125.19}
MEDIA_PATH_AUDIOBOOKS=${MEDIA_PATH_AUDIOBOOKS:-/media/audiobooks}
EOF

    chmod 600 "$ENV_FILE"
    print_success ".env created ($(grep -c '^[A-Z_]' "$ENV_FILE") keys)"
}

cmd_ssl_renew() {
    print_header "🔄 Renewing SSL Certificates"

    CERT_DIR="/opt/ssl/7gram.xyz"
    DOMAIN="7gram.xyz"
    LETSENCRYPT_DIR="/etc/letsencrypt/live/$DOMAIN"

    # Check if certificates exist locally
    if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
        print_warning "No certificates found in $CERT_DIR. Run './run.sh ssl-init' first."
        return 1
    fi

    # Check if cert is Let's Encrypt
    if ! openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -issuer 2>/dev/null | grep -q "Let's Encrypt"; then
        print_warning "Certificate is not from Let's Encrypt. Run './run.sh ssl-init' to get LE certs."
        return 1
    fi

    # Check expiration (only renew if expires within 30 days)
    if ! openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -checkend $((30*24*60*60)) >/dev/null 2>&1; then
        print_info "Certificate expires in more than 30 days. No renewal needed."
        return 0
    fi

    print_info "Certificate expires soon. Renewing..."

    if sudo certbot renew --quiet; then
        # Check if renewal actually created new files
        if [ -f "$LETSENCRYPT_DIR/fullchain.pem" ] && [ -f "$LETSENCRYPT_DIR/privkey.pem" ]; then
            print_info "Copying renewed certificates..."

            # Copy renewed certificates
            if sudo cp "$LETSENCRYPT_DIR/fullchain.pem" "$CERT_DIR/" && \
               sudo cp "$LETSENCRYPT_DIR/privkey.pem" "$CERT_DIR/"; then

                # Set permissions
                sudo chmod 644 "$CERT_DIR/fullchain.pem"
                sudo chmod 600 "$CERT_DIR/privkey.pem"

                print_success "SSL certificates renewed"

                # Reload nginx if running
                if docker ps | grep -q nginx; then
                    print_info "Reloading nginx..."
                    docker compose exec -T nginx nginx -s reload 2>/dev/null || print_warning "Could not reload nginx"
                fi

            else
                print_error "Failed to copy renewed certificates"
                return 1
            fi
        else
            print_warning "Certbot renew completed but no renewed certificates found"
            print_info "Certificates may not need renewal yet"
        fi
    else
        print_error "Certbot renew failed"
        print_info "Check certbot logs: sudo certbot certificates"
        return 1
    fi
}

show_usage() {
    cat << EOF
🏠 Freddy - Personal & Authentication Services Manager

Usage: ./run.sh <command> [options]

Commands:
  start [prod]      Start all services (prod mode pulls images first)
  stop              Stop all services
  restart [service] Restart all services or a specific service
  status            Show service status
  logs [service]    View logs (all or specific service)
  pull              Pull latest images
  health            Check service health
  clean             Clean up unused Docker resources
  shell <service>   Open shell in a container
  update            Pull images and recreate containers
  occ <command>     Run Nextcloud occ command (as www-data)
  scan [path|all]   Rescan Nextcloud files (default: --all)
  reset-nextcloud-db Reset Nextcloud PostgreSQL database (fixes auth issues)
  ssl-init [--force] Initialize SSL certificates with Let's Encrypt
  ssl-renew         Renew SSL certificates
  setup-env         Generate .env file with defaults (for CI/CD)
  help              Show this help message

Modes:
  (default)         Development mode - use existing images
  prod              Production mode - pull latest images before starting

Examples:
  ./run.sh start              # Start services (dev mode)
  ./run.sh start prod         # Pull images and start services
  ./run.sh prod start         # Same as above (alternative syntax)
  ./run.sh logs photoprism    # View PhotoPrism logs
  ./run.sh restart nginx      # Restart only nginx
  ./run.sh shell nextcloud    # Open shell in Nextcloud container
  ./run.sh update             # Update all services to latest
  ./run.sh occ files:scan --all   # Rescan all Nextcloud files
  ./run.sh occ status             # Show Nextcloud status
  ./run.sh scan                   # Rescan all files (shorthand)
  ./run.sh scan /user/files/Photos # Rescan specific path
  ./run.sh reset-nextcloud-db     # Reset Nextcloud database (fixes password errors)

Services:
  nginx             - Reverse proxy (ports 80, 443)
  photoprism        - Photo management (port 2342)
  photoprism-postgres - PhotoPrism database
  nextcloud         - Cloud storage (port 8080)
  nextcloud-cron    - Nextcloud background jobs
  nextcloud-postgres - Nextcloud database
  homeassistant     - Home automation (port 8123)
  audiobookshelf    - Audiobook server (port 13378)

Access URLs:
  Dashboard:        https://freddy.7gram.xyz
  PhotoPrism:       https://freddy.7gram.xyz/photoprism
  Nextcloud:        https://freddy.7gram.xyz/nextcloud
  Home Assistant:   https://freddy.7gram.xyz/homeassistant
  Audiobookshelf:   https://freddy.7gram.xyz/audiobookshelf

Configuration:
  - Environment variables: .env
  - Docker Compose: docker-compose.yml
  - Service configs: ./services/

For more information, see the README.md
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    check_docker
    check_compose_file

    # No arguments - show usage
    if [ $# -lt 1 ]; then
        show_usage
        exit 0
    fi

    # Check if first argument is "prod" mode
    local mode="dev"
    local command=$1

    if [ "$1" = "prod" ]; then
        mode="prod"
        shift
        command=${1:-start}
    fi

    shift || true

    # Execute command
    case $command in
        start|up)
            cmd_start "$mode" "$@"
            ;;
        stop|down)
            cmd_stop "$@"
            ;;
        restart)
            cmd_restart "$@"
            ;;
        status|ps)
            cmd_status
            ;;
        logs)
            cmd_logs "$@"
            ;;
        pull)
            cmd_pull
            ;;
        health|check)
            cmd_health
            ;;
        clean|prune)
            cmd_clean
            ;;
        shell|exec)
            cmd_shell "$@"
            ;;
        update|upgrade)
            cmd_update
            ;;
        occ)
            cmd_occ "$@"
            ;;
        scan|rescan)
            cmd_scan "$@"
            ;;
        reset-nextcloud-db|reset-nc-db)
            cmd_reset_nextcloud_db
            ;;
        ssl-init|ssl)
            cmd_ssl_init "$1"
            ;;
        ssl-renew|renew)
            cmd_ssl_renew
            ;;
        setup-env)
            cmd_setup_env
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
