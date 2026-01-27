#!/bin/bash
#
# Staging Environment Manager
# Helper script to manage staging environment lifecycle
#
# Usage: ./staging.sh [command]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.staging.yml"
ENV_FILE="$PROJECT_DIR/.env.staging"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ============================================================================
# Commands
# ============================================================================

setup_staging() {
    log "Setting up staging environment..."
    
    # Create staging config directories
    info "Creating staging config directories..."
    mkdir -p "$PROJECT_DIR/services/authentik/config-staging"/{media,custom-templates,certs}
    mkdir -p "$PROJECT_DIR/services/nginx/conf.d-staging"
    mkdir -p "$PROJECT_DIR/services/nextcloud/config-staging"
    mkdir -p "$PROJECT_DIR/services/nextcloud/data-staging"
    
    # Copy production configs to staging (if they exist)
    if [[ -d "$PROJECT_DIR/services/nginx/conf.d" ]]; then
        info "Copying nginx configs..."
        cp -r "$PROJECT_DIR/services/nginx/conf.d"/* "$PROJECT_DIR/services/nginx/conf.d-staging/" 2>/dev/null || true
        
        # Update staging configs to use staging ports and hostnames
        find "$PROJECT_DIR/services/nginx/conf.d-staging" -type f -name "*.conf" -exec \
            sed -i 's/proxy_pass http:\/\/authentik-server:9000/proxy_pass http:\/\/authentik-server-staging:9000/g' {} \;
    fi
    
    # Create .env.staging if it doesn't exist
    if [[ ! -f "$ENV_FILE" ]]; then
        info "Creating .env.staging..."
        if [[ -f "$PROJECT_DIR/.env" ]]; then
            cp "$PROJECT_DIR/.env" "$ENV_FILE"
            echo "" >> "$ENV_FILE"
            echo "# Staging-specific overrides" >> "$ENV_FILE"
            echo "STAGING_AUTHENTIK_SECRET_KEY=change-this-staging-secret-$(openssl rand -hex 32)" >> "$ENV_FILE"
            echo "STAGING_AUTHENTIK_POSTGRES_PASSWORD=staging_authentik_pass_$(openssl rand -hex 16)" >> "$ENV_FILE"
        else
            error ".env file not found. Please create it first."
            exit 1
        fi
    fi
    
    log "✓ Staging environment setup complete"
    echo ""
    info "Next steps:"
    echo "  1. Review and update .env.staging with staging credentials"
    echo "  2. Start staging: ./scripts/staging.sh start"
    echo "  3. Access staging at http://localhost:19000 (Authentik)"
}

start_staging() {
    log "Starting staging environment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        error ".env.staging not found. Run: ./scripts/staging.sh setup"
        exit 1
    fi
    
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    
    log "✓ Staging environment started"
    echo ""
    info "Access staging services:"
    echo "  - Authentik: http://localhost:19000"
    echo "  - Nginx: http://localhost:8080"
    echo ""
    info "View logs: ./scripts/staging.sh logs"
}

stop_staging() {
    log "Stopping staging environment..."
    docker compose -f "$COMPOSE_FILE" stop
    log "✓ Staging environment stopped"
}

restart_staging() {
    log "Restarting staging environment..."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" restart
    log "✓ Staging environment restarted"
}

down_staging() {
    warn "This will stop and remove staging containers (data will be preserved)"
    read -p "Continue? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Removing staging environment..."
        docker compose -f "$COMPOSE_FILE" down
        log "✓ Staging environment removed"
    else
        info "Cancelled"
    fi
}

destroy_staging() {
    error "⚠️  WARNING: This will delete ALL staging data (configs, databases, volumes)"
    warn "This action cannot be undone!"
    echo ""
    read -p "Type 'destroy staging' to confirm: " -r
    if [[ $REPLY == "destroy staging" ]]; then
        log "Destroying staging environment..."
        docker compose -f "$COMPOSE_FILE" down -v
        rm -rf "$PROJECT_DIR/services/authentik/config-staging"
        rm -rf "$PROJECT_DIR/services/nginx/conf.d-staging"
        rm -rf "$PROJECT_DIR/services/nextcloud/config-staging"
        rm -rf "$PROJECT_DIR/services/nextcloud/data-staging"
        log "✓ Staging environment destroyed"
    else
        info "Cancelled"
    fi
}

status_staging() {
    log "Staging environment status:"
    echo ""
    docker compose -f "$COMPOSE_FILE" ps
}

logs_staging() {
    local service="$1"
    if [[ -z "$service" ]]; then
        docker compose -f "$COMPOSE_FILE" logs -f --tail=100
    else
        docker compose -f "$COMPOSE_FILE" logs -f --tail=100 "$service"
    fi
}

sync_to_staging() {
    log "Syncing production configs to staging..."
    
    warn "This will overwrite staging configs with production configs"
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cancelled"
        exit 0
    fi
    
    # Sync nginx configs
    if [[ -d "$PROJECT_DIR/services/nginx/conf.d" ]]; then
        info "Syncing nginx configs..."
        rsync -av --delete \
            "$PROJECT_DIR/services/nginx/conf.d/" \
            "$PROJECT_DIR/services/nginx/conf.d-staging/"
        
        # Update staging configs
        find "$PROJECT_DIR/services/nginx/conf.d-staging" -type f -name "*.conf" -exec \
            sed -i 's/proxy_pass http:\/\/authentik-server:9000/proxy_pass http:\/\/authentik-server-staging:9000/g' {} \;
    fi
    
    log "✓ Configs synced to staging"
    info "Remember to restart staging: ./scripts/staging.sh restart"
}

sync_to_production() {
    error "⚠️  WARNING: This will overwrite production configs with staging configs"
    warn "Make sure you've tested staging configs thoroughly!"
    echo ""
    read -p "Type 'sync to production' to confirm: " -r
    if [[ $REPLY != "sync to production" ]]; then
        info "Cancelled"
        exit 0
    fi
    
    log "Syncing staging configs to production..."
    
    # Backup production configs
    local backup_dir="$PROJECT_DIR/backups/configs-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$PROJECT_DIR/services/nginx/conf.d" "$backup_dir/" 2>/dev/null || true
    info "Production configs backed up to: $backup_dir"
    
    # Sync nginx configs
    if [[ -d "$PROJECT_DIR/services/nginx/conf.d-staging" ]]; then
        info "Syncing nginx configs..."
        rsync -av --delete \
            "$PROJECT_DIR/services/nginx/conf.d-staging/" \
            "$PROJECT_DIR/services/nginx/conf.d/"
        
        # Update production configs
        find "$PROJECT_DIR/services/nginx/conf.d" -type f -name "*.conf" -exec \
            sed -i 's/proxy_pass http:\/\/authentik-server-staging:9000/proxy_pass http:\/\/authentik-server:9000/g' {} \;
    fi
    
    log "✓ Configs synced to production"
    warn "Remember to restart production services!"
    echo "  docker compose restart nginx"
}

usage() {
    cat << EOF
Staging Environment Manager

Usage: $0 [command]

Commands:
    setup       Set up staging environment (create directories, copy configs)
    start       Start staging environment
    stop        Stop staging environment
    restart     Restart staging environment
    down        Stop and remove staging containers (preserve data)
    destroy     Destroy staging environment (delete all data)
    status      Show staging container status
    logs        View staging logs (optional: specify service name)
    
    sync-to-staging     Sync production configs to staging
    sync-to-prod        Sync staging configs to production (with backup)
    
    help        Show this help message

Examples:
    # Initial setup
    $0 setup
    $0 start
    
    # View logs
    $0 logs
    $0 logs authentik-server-staging
    
    # Sync configs
    $0 sync-to-staging    # Production -> Staging
    $0 sync-to-prod       # Staging -> Production (after testing)
    
    # Cleanup
    $0 stop
    $0 down
    $0 destroy            # Complete removal

EOF
}

# ============================================================================
# Main
# ============================================================================

case "${1:-help}" in
    setup)
        setup_staging
        ;;
    start)
        start_staging
        ;;
    stop)
        stop_staging
        ;;
    restart)
        restart_staging
        ;;
    down)
        down_staging
        ;;
    destroy)
        destroy_staging
        ;;
    status)
        status_staging
        ;;
    logs)
        logs_staging "$2"
        ;;
    sync-to-staging)
        sync_to_staging
        ;;
    sync-to-prod|sync-to-production)
        sync_to_production
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $1"
        echo ""
        usage
        exit 1
        ;;
esac
