#!/bin/bash
#
# FREDDY Restore Script
# Restore backed up data from backup directory
#
# Usage: ./restore.sh <backup_directory> [--component=<name>] [--dry-run]
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 <backup_directory> [options]

Restore FREDDY server from backup.

Arguments:
    backup_directory    Path to backup directory (e.g., /mnt/backup/freddy/20251020_020000)

Options:
    --component=NAME    Restore specific component only (authentik, nextcloud, photoprism, configs)
    --dry-run          Show what would be restored without actually restoring
    --help             Show this help message

Examples:
    # Full restore
    $0 /mnt/backup/freddy/20251020_020000

    # Restore only Authentik
    $0 /mnt/backup/freddy/20251020_020000 --component=authentik

    # Dry run (test restore)
    $0 /mnt/backup/freddy/20251020_020000 --dry-run

EOF
}

verify_backup() {
    local backup_dir="$1"
    
    log "Verifying backup directory: $backup_dir"
    
    if [[ ! -d "$backup_dir" ]]; then
        error "Backup directory not found: $backup_dir"
        exit 1
    fi
    
    if [[ ! -f "$backup_dir/MANIFEST.txt" ]]; then
        warn "Backup manifest not found"
    else
        info "Backup manifest found:"
        cat "$backup_dir/MANIFEST.txt" | head -n 10
    fi
    
    # List backup files
    info "Backup contains:"
    ls -lh "$backup_dir"/*.tar.gz "$backup_dir"/*.sql.gz 2>/dev/null | awk '{print $9, $5}'
    
    log "✓ Backup verification complete"
}

confirm_restore() {
    warn "⚠️  IMPORTANT: This will OVERWRITE existing data!"
    warn "Make sure you have a backup of the current state before proceeding."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Restore cancelled"
        exit 0
    fi
}

restore_authentik_db() {
    local backup_dir="$1"
    local db_file=$(ls "$backup_dir"/authentik_postgres_*.sql.gz 2>/dev/null | head -n 1)
    
    if [[ -z "$db_file" ]]; then
        warn "Authentik database backup not found"
        return 1
    fi
    
    log "Restoring Authentik database from: $(basename "$db_file")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore Authentik database"
        return 0
    fi
    
    # Drop and recreate database
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T authentik-postgres \
        psql -U authentik -c "DROP DATABASE IF EXISTS authentik;"
    
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T authentik-postgres \
        psql -U authentik -c "CREATE DATABASE authentik;"
    
    # Restore database
    gunzip -c "$db_file" | docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T authentik-postgres \
        psql -U authentik authentik
    
    log "✓ Authentik database restored"
}

restore_authentik_configs() {
    local backup_dir="$1"
    local config_file=$(ls "$backup_dir"/authentik_config_*.tar.gz 2>/dev/null | head -n 1)
    
    if [[ -z "$config_file" ]]; then
        warn "Authentik config backup not found"
        return 1
    fi
    
    log "Restoring Authentik configs from: $(basename "$config_file")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore Authentik configs"
        return 0
    fi
    
    # Backup current config
    if [[ -d "$PROJECT_DIR/services/authentik/config" ]]; then
        mv "$PROJECT_DIR/services/authentik/config" "$PROJECT_DIR/services/authentik/config.bak.$(date +%s)"
    fi
    
    # Restore configs
    tar xzf "$config_file" -C "$PROJECT_DIR/services/authentik/"
    
    log "✓ Authentik configs restored"
}

restore_nextcloud_db() {
    local backup_dir="$1"
    local db_file=$(ls "$backup_dir"/nextcloud_postgres_*.sql.gz 2>/dev/null | head -n 1)
    
    if [[ -z "$db_file" ]]; then
        warn "Nextcloud database backup not found"
        return 1
    fi
    
    log "Restoring Nextcloud database from: $(basename "$db_file")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore Nextcloud database"
        return 0
    fi
    
    # Put Nextcloud in maintenance mode
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T -u www-data nextcloud \
        php occ maintenance:mode --on
    
    # Drop and recreate database
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T nextcloud-postgres \
        psql -U nextcloud -c "DROP DATABASE IF EXISTS nextcloud;"
    
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T nextcloud-postgres \
        psql -U nextcloud -c "CREATE DATABASE nextcloud;"
    
    # Restore database
    gunzip -c "$db_file" | docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T nextcloud-postgres \
        psql -U nextcloud nextcloud
    
    # Turn off maintenance mode
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T -u www-data nextcloud \
        php occ maintenance:mode --off
    
    log "✓ Nextcloud database restored"
}

restore_nextcloud_data() {
    local backup_dir="$1"
    local data_file=$(ls "$backup_dir"/nextcloud_data_*.tar.gz 2>/dev/null | head -n 1)
    
    if [[ -z "$data_file" ]]; then
        warn "Nextcloud data backup not found"
        return 1
    fi
    
    log "Restoring Nextcloud data from: $(basename "$data_file")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore Nextcloud data"
        return 0
    fi
    
    # Backup current data
    if [[ -d "$PROJECT_DIR/services/nextcloud/config" ]]; then
        mv "$PROJECT_DIR/services/nextcloud/config" "$PROJECT_DIR/services/nextcloud/config.bak.$(date +%s)"
    fi
    if [[ -d "$PROJECT_DIR/services/nextcloud/data" ]]; then
        mv "$PROJECT_DIR/services/nextcloud/data" "$PROJECT_DIR/services/nextcloud/data.bak.$(date +%s)"
    fi
    
    # Restore data
    tar xzf "$data_file" -C "$PROJECT_DIR/services/nextcloud/"
    
    log "✓ Nextcloud data restored"
}

restore_photoprism_db() {
    local backup_dir="$1"
    local db_file=$(ls "$backup_dir"/photoprism_mariadb_*.sql.gz 2>/dev/null | head -n 1)
    
    if [[ -z "$db_file" ]]; then
        warn "PhotoPrism database backup not found"
        return 1
    fi
    
    log "Restoring PhotoPrism database from: $(basename "$db_file")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore PhotoPrism database"
        return 0
    fi
    
    # Restore database
    gunzip -c "$db_file" | docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T photoprism-mariadb \
        mysql -u photoprism -p"${PHOTOPRISM_DB_PASSWORD:-photoprism}" photoprism
    
    log "✓ PhotoPrism database restored"
}

restore_photoprism_data() {
    local backup_dir="$1"
    local storage_file=$(ls "$backup_dir"/photoprism_storage_*.tar.gz 2>/dev/null | head -n 1)
    
    if [[ -z "$storage_file" ]]; then
        warn "PhotoPrism storage backup not found"
        return 1
    fi
    
    log "Restoring PhotoPrism storage from: $(basename "$storage_file")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore PhotoPrism storage"
        return 0
    fi
    
    # Backup current storage
    if [[ -d "$PROJECT_DIR/services/photoprism/storage" ]]; then
        mv "$PROJECT_DIR/services/photoprism/storage" "$PROJECT_DIR/services/photoprism/storage.bak.$(date +%s)"
    fi
    
    # Restore storage
    tar xzf "$storage_file" -C "$PROJECT_DIR/services/photoprism/"
    
    log "✓ PhotoPrism storage restored"
}

restore_docker_configs() {
    local backup_dir="$1"
    local config_file=$(ls "$backup_dir"/docker_configs_*.tar.gz 2>/dev/null | head -n 1)
    
    if [[ -z "$config_file" ]]; then
        warn "Docker configs backup not found"
        return 1
    fi
    
    log "Restoring Docker configs from: $(basename "$config_file")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore Docker configs"
        return 0
    fi
    
    # Backup current configs
    cp "$PROJECT_DIR/docker-compose.yml" "$PROJECT_DIR/docker-compose.yml.bak.$(date +%s)" 2>/dev/null || true
    cp "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.bak.$(date +%s)" 2>/dev/null || true
    
    # Restore configs
    tar xzf "$config_file" -C "$PROJECT_DIR/"
    
    log "✓ Docker configs restored"
}

# ============================================================================
# Main Restore Process
# ============================================================================

main() {
    echo ""
    echo "========================================"
    echo "   FREDDY Restore Script"
    echo "========================================"
    echo ""
    
    # Parse arguments
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi
    
    BACKUP_DIR="$1"
    shift
    
    COMPONENT=""
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --component=*)
                COMPONENT="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Verify backup
    verify_backup "$BACKUP_DIR"
    
    # Confirm restore
    if [[ "$DRY_RUN" != "true" ]]; then
        confirm_restore
    else
        info "Running in DRY RUN mode - no changes will be made"
    fi
    
    echo ""
    log "Starting restore process..."
    
    # Restore components
    case "$COMPONENT" in
        "")
            # Full restore
            log "Performing full restore..."
            restore_authentik_db "$BACKUP_DIR"
            restore_authentik_configs "$BACKUP_DIR"
            restore_nextcloud_db "$BACKUP_DIR"
            restore_nextcloud_data "$BACKUP_DIR"
            restore_photoprism_db "$BACKUP_DIR"
            restore_photoprism_data "$BACKUP_DIR"
            restore_docker_configs "$BACKUP_DIR"
            ;;
        "authentik")
            restore_authentik_db "$BACKUP_DIR"
            restore_authentik_configs "$BACKUP_DIR"
            ;;
        "nextcloud")
            restore_nextcloud_db "$BACKUP_DIR"
            restore_nextcloud_data "$BACKUP_DIR"
            ;;
        "photoprism")
            restore_photoprism_db "$BACKUP_DIR"
            restore_photoprism_data "$BACKUP_DIR"
            ;;
        "configs")
            restore_docker_configs "$BACKUP_DIR"
            ;;
        *)
            error "Unknown component: $COMPONENT"
            exit 1
            ;;
    esac
    
    echo ""
    log "========================================"
    log "Restore completed successfully!"
    log "========================================"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        warn "Remember to restart services if needed:"
        echo "  docker compose restart"
    fi
}

# ============================================================================
# Execute
# ============================================================================

main "$@"
