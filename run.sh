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
    echo "  Audiobookshelf: https://audiobook.7gram.xyz"
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

    local services=("nginx" "photoprism" "nextcloud" "homeassistant" "audiobookshelf" "photoprism-postgres" "nextcloud-postgres")

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

Services:
  nginx             - Reverse proxy (ports 80, 443)
  photoprism        - Photo management (port 2342)
  photoprism-postgres - PhotoPrism database
  nextcloud         - Cloud storage (port 8443)
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
