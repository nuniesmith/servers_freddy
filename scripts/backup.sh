#!/bin/bash
#
# FREDDY Backup Script
# Automated backup of critical data: Authentik, Nextcloud, PhotoPrism, configs
#
# Usage: ./backup.sh [--full] [--config-only]
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/mnt/backup/freddy}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE_DIR/$TIMESTAMP"

# Backup components
BACKUP_AUTHENTIK="${BACKUP_AUTHENTIK:-true}"
BACKUP_NEXTCLOUD="${BACKUP_NEXTCLOUD:-true}"
BACKUP_PHOTOPRISM="${BACKUP_PHOTOPRISM:-true}"
BACKUP_CONFIGS="${BACKUP_CONFIGS:-true}"
BACKUP_DOCKER_VOLUMES="${BACKUP_DOCKER_VOLUMES:-false}"

# Logging
LOG_FILE="$BACKUP_BASE_DIR/backup.log"
ERROR_LOG="$BACKUP_BASE_DIR/backup_errors.log"

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$ERROR_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! command -v docker &> /dev/null; then
        error "This script requires root privileges or docker access"
        exit 1
    fi
    
    # Check if backup directory exists
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        warn "Backup directory doesn't exist. Creating: $BACKUP_BASE_DIR"
        mkdir -p "$BACKUP_BASE_DIR"
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG "$BACKUP_BASE_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -lt 50 ]]; then
        warn "Low disk space: ${AVAILABLE_SPACE}GB available"
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        error "Docker is not running"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

backup_authentik_db() {
    log "Backing up Authentik PostgreSQL database..."
    
    local backup_file="$BACKUP_DIR/authentik_postgres_$TIMESTAMP.sql.gz"
    
    # Dump PostgreSQL database
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T authentik-postgres \
        pg_dump -U authentik authentik | gzip > "$backup_file"
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Authentik database backed up: $size"
    else
        error "Failed to backup Authentik database"
        return 1
    fi
}

backup_authentik_configs() {
    log "Backing up Authentik configs..."
    
    local backup_file="$BACKUP_DIR/authentik_config_$TIMESTAMP.tar.gz"
    
    # Backup config directory
    tar czf "$backup_file" -C "$PROJECT_DIR/services/authentik" config/
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Authentik configs backed up: $size"
    else
        error "Failed to backup Authentik configs"
        return 1
    fi
}

backup_nextcloud_db() {
    log "Backing up Nextcloud PostgreSQL database..."
    
    local backup_file="$BACKUP_DIR/nextcloud_postgres_$TIMESTAMP.sql.gz"
    
    # Dump PostgreSQL database
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T nextcloud-postgres \
        pg_dump -U nextcloud nextcloud | gzip > "$backup_file"
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Nextcloud database backed up: $size"
    else
        error "Failed to backup Nextcloud database"
        return 1
    fi
}

backup_nextcloud_data() {
    log "Backing up Nextcloud data (this may take a while)..."
    
    local backup_file="$BACKUP_DIR/nextcloud_data_$TIMESTAMP.tar.gz"
    
    # Put Nextcloud in maintenance mode
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T -u www-data nextcloud \
        php occ maintenance:mode --on
    
    # Backup data directory (excluding large cache directories)
    tar czf "$backup_file" \
        -C "$PROJECT_DIR/services/nextcloud" \
        --exclude='data/appdata_*/preview' \
        --exclude='data/*/cache' \
        --exclude='data/*/thumbnails' \
        config/ data/
    
    # Turn off maintenance mode
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T -u www-data nextcloud \
        php occ maintenance:mode --off
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Nextcloud data backed up: $size"
    else
        error "Failed to backup Nextcloud data"
        docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T -u www-data nextcloud \
            php occ maintenance:mode --off
        return 1
    fi
}

backup_photoprism_db() {
    log "Backing up PhotoPrism MariaDB database..."
    
    local backup_file="$BACKUP_DIR/photoprism_mariadb_$TIMESTAMP.sql.gz"
    
    # Dump MariaDB database
    docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T photoprism-mariadb \
        mysqldump -u photoprism -p"${PHOTOPRISM_DB_PASSWORD:-photoprism}" photoprism | gzip > "$backup_file"
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ PhotoPrism database backed up: $size"
    else
        error "Failed to backup PhotoPrism database"
        return 1
    fi
}

backup_photoprism_data() {
    log "Backing up PhotoPrism storage (metadata only, excluding originals)..."
    
    local backup_file="$BACKUP_DIR/photoprism_storage_$TIMESTAMP.tar.gz"
    
    # Backup storage directory (sidecar files, thumbnails, etc)
    # Exclude originals as they should be backed up separately
    tar czf "$backup_file" \
        -C "$PROJECT_DIR/services/photoprism" \
        --exclude='storage/originals' \
        storage/
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ PhotoPrism storage backed up: $size"
    else
        error "Failed to backup PhotoPrism storage"
        return 1
    fi
}

backup_docker_configs() {
    log "Backing up Docker configs and compose files..."
    
    local backup_file="$BACKUP_DIR/docker_configs_$TIMESTAMP.tar.gz"
    
    # Backup all service configs and docker-compose files
    tar czf "$backup_file" \
        -C "$PROJECT_DIR" \
        docker-compose.yml \
        .env \
        services/nginx/conf.d/ \
        services/nginx/nginx.conf \
        services/homeassistant/config/ \
        services/audiobookshelf/config/ \
        --exclude='services/*/config/*.log*' \
        --exclude='services/*/config/cache' \
        --exclude='services/*/config/logs'
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Docker configs backed up: $size"
    else
        error "Failed to backup Docker configs"
        return 1
    fi
}

backup_docker_volumes() {
    log "Backing up critical Docker volumes..."
    
    local backup_file="$BACKUP_DIR/docker_volumes_$TIMESTAMP.tar.gz"
    
    # List of critical named volumes to backup
    local volumes=(
        "freddy_authentik_postgres_data"
        "freddy_authentik_redis_data"
        "freddy_nextcloud_postgres_data"
        "freddy_photoprism_mariadb_data"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume inspect "$volume" &> /dev/null; then
            info "Backing up volume: $volume"
            docker run --rm \
                -v "$volume":/volume \
                -v "$BACKUP_DIR":/backup \
                alpine tar czf "/backup/${volume}_$TIMESTAMP.tar.gz" -C /volume ./
        else
            warn "Volume not found: $volume"
        fi
    done
    
    log "✓ Docker volumes backed up"
}

backup_scripts() {
    log "Backing up scripts directory..."
    
    local backup_file="$BACKUP_DIR/scripts_$TIMESTAMP.tar.gz"
    
    tar czf "$backup_file" -C "$PROJECT_DIR" scripts/
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Scripts backed up: $size"
    else
        error "Failed to backup scripts"
        return 1
    fi
}

create_backup_manifest() {
    log "Creating backup manifest..."
    
    local manifest_file="$BACKUP_DIR/MANIFEST.txt"
    
    cat > "$manifest_file" << EOF
FREDDY Backup Manifest
======================
Backup Date: $(date)
Backup Directory: $BACKUP_DIR
Server: FREDDY
Hostname: $(hostname)

Components Backed Up:
- Authentik Database: $BACKUP_AUTHENTIK
- Nextcloud Database & Data: $BACKUP_NEXTCLOUD
- PhotoPrism Database & Storage: $BACKUP_PHOTOPRISM
- Docker Configs: $BACKUP_CONFIGS
- Docker Volumes: $BACKUP_DOCKER_VOLUMES

Files in this backup:
EOF
    
    # List all files with sizes
    du -h "$BACKUP_DIR"/* | sort -h >> "$manifest_file"
    
    # Total backup size
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    echo "" >> "$manifest_file"
    echo "Total Backup Size: $total_size" >> "$manifest_file"
    
    log "✓ Backup manifest created"
}

cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local deleted_count=0
    
    # Find and delete old backup directories
    find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" -mtime +"$RETENTION_DAYS" | while read dir; do
        info "Deleting old backup: $(basename "$dir")"
        rm -rf "$dir"
        ((deleted_count++))
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        log "✓ Deleted $deleted_count old backup(s)"
    else
        log "✓ No old backups to delete"
    fi
}

send_notification() {
    local status="$1"
    local message="$2"
    
    # TODO: Implement notification (email, webhook, etc.)
    # Example: curl -X POST webhook_url -d "message=$message"
    
    info "Notification: [$status] $message"
}

# ============================================================================
# Main Backup Process
# ============================================================================

main() {
    local start_time=$(date +%s)
    
    echo ""
    echo "========================================"
    echo "   FREDDY Backup Script"
    echo "========================================"
    echo ""
    
    # Parse arguments
    FULL_BACKUP=false
    CONFIG_ONLY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                FULL_BACKUP=true
                BACKUP_DOCKER_VOLUMES=true
                shift
                ;;
            --config-only)
                CONFIG_ONLY=true
                BACKUP_AUTHENTIK=false
                BACKUP_NEXTCLOUD=false
                BACKUP_PHOTOPRISM=false
                BACKUP_DOCKER_VOLUMES=false
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Start backup
    log "Starting backup process..."
    log "Backup directory: $BACKUP_DIR"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Run checks
    check_prerequisites
    
    # Backup components
    if [[ "$BACKUP_AUTHENTIK" == "true" ]]; then
        backup_authentik_db
        backup_authentik_configs
    fi
    
    if [[ "$BACKUP_NEXTCLOUD" == "true" ]]; then
        backup_nextcloud_db
        backup_nextcloud_data
    fi
    
    if [[ "$BACKUP_PHOTOPRISM" == "true" ]]; then
        backup_photoprism_db
        backup_photoprism_data
    fi
    
    if [[ "$BACKUP_CONFIGS" == "true" ]]; then
        backup_docker_configs
        backup_scripts
    fi
    
    if [[ "$BACKUP_DOCKER_VOLUMES" == "true" ]]; then
        backup_docker_volumes
    fi
    
    # Create manifest
    create_backup_manifest
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    # Get total size
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    
    echo ""
    log "========================================"
    log "Backup completed successfully!"
    log "Duration: ${minutes}m ${seconds}s"
    log "Total size: $total_size"
    log "Location: $BACKUP_DIR"
    log "========================================"
    echo ""
    
    send_notification "SUCCESS" "FREDDY backup completed: $total_size in ${minutes}m ${seconds}s"
}

# ============================================================================
# Execute
# ============================================================================

main "$@"
