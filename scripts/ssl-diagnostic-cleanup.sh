#!/bin/bash
#
# SSL Certificate Diagnostic and Cleanup Script
# Run as root on the freddy server
#
# Usage: sudo ./ssl-diagnostic-cleanup.sh [diagnose|cleanup|both]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="7gram.xyz"
# Try multiple locations for the project directory
if [ -n "$PROJECT_DIR" ]; then
    PROJECT_DIR="$PROJECT_DIR"
elif [ -d "/home/actions/freddy" ]; then
    PROJECT_DIR="/home/actions/freddy"
elif [ -d "$HOME/freddy" ]; then
    PROJECT_DIR="$HOME/freddy"
else
    PROJECT_DIR="/home/actions/freddy"
fi
DOCKER_VOLUME="ssl-certs"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║          SSL Certificate Diagnostic & Cleanup Tool               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================================================
# DIAGNOSTIC FUNCTIONS
# =============================================================================

diagnose_certificates() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}                    CERTIFICATE DIAGNOSTICS                        ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # 1. Check what nginx is actually serving
    echo -e "${YELLOW}[1/8] Checking what certificate nginx is serving...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    if command -v openssl &> /dev/null; then
        echo "Testing https://${DOMAIN}:443..."
        CERT_INFO=$(echo | timeout 5 openssl s_client -servername ${DOMAIN} -connect ${DOMAIN}:443 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null || echo "FAILED")
        if [ "$CERT_INFO" != "FAILED" ]; then
            echo -e "${GREEN}Certificate being served:${NC}"
            echo "$CERT_INFO"
            
            # Check if it's self-signed
            ISSUER=$(echo "$CERT_INFO" | grep "issuer=" | head -1)
            if echo "$ISSUER" | grep -qi "Let's Encrypt"; then
                echo -e "${GREEN}✓ Let's Encrypt certificate detected!${NC}"
            elif echo "$ISSUER" | grep -qi "self-signed\|${DOMAIN}"; then
                echo -e "${RED}✗ Self-signed certificate detected!${NC}"
            else
                echo -e "${YELLOW}⚠ Unknown issuer${NC}"
            fi
        else
            echo -e "${RED}Could not connect to ${DOMAIN}:443${NC}"
        fi
    else
        echo -e "${YELLOW}openssl not installed, skipping remote check${NC}"
    fi
    echo ""

    # 2. Check Docker volume
    echo -e "${YELLOW}[2/8] Checking Docker volume '${DOCKER_VOLUME}'...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    if docker volume inspect ${DOCKER_VOLUME} &>/dev/null; then
        echo -e "${GREEN}✓ Volume exists${NC}"
        VOLUME_PATH=$(docker volume inspect ${DOCKER_VOLUME} --format '{{.Mountpoint}}')
        echo "  Mount point: ${VOLUME_PATH}"
        
        echo ""
        echo "Contents of volume:"
        docker run --rm -v ${DOCKER_VOLUME}:/certs:ro busybox:latest find /certs -type f 2>/dev/null | head -50 || echo "  (empty or error)"
        
        echo ""
        echo "Checking for Let's Encrypt certificates in volume:"
        if docker run --rm -v ${DOCKER_VOLUME}:/certs:ro busybox:latest test -f /certs/live/${DOMAIN}/fullchain.pem 2>/dev/null; then
            echo -e "${GREEN}✓ Let's Encrypt certificates found in Docker volume${NC}"
            echo ""
            echo "Certificate details from volume:"
            docker run --rm -v ${DOCKER_VOLUME}:/certs:ro alpine/openssl x509 -in /certs/live/${DOMAIN}/fullchain.pem -noout -issuer -subject -dates 2>/dev/null || echo "  Could not read cert"
        else
            echo -e "${RED}✗ No Let's Encrypt certificates in Docker volume${NC}"
        fi
    else
        echo -e "${RED}✗ Volume '${DOCKER_VOLUME}' does not exist${NC}"
    fi
    echo ""

    # 3. Check nginx container's certificate mount
    echo -e "${YELLOW}[3/8] Checking nginx container's certificate location...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    if docker ps --format '{{.Names}}' | grep -q "^nginx$"; then
        echo -e "${GREEN}✓ Nginx container is running${NC}"
        
        echo ""
        echo "Nginx container mounts:"
        docker inspect nginx --format '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null
        
        echo ""
        echo "Certificates inside nginx container (/etc/nginx/ssl/):"
        docker exec nginx ls -la /etc/nginx/ssl/ 2>/dev/null || echo "  Directory not found or empty"
        
        echo ""
        echo "Certificates inside nginx container (/etc/letsencrypt/):"
        docker exec nginx ls -laR /etc/letsencrypt/ 2>/dev/null | head -30 || echo "  Directory not found or empty"
        
        echo ""
        echo "Certificate nginx is configured to use:"
        docker exec nginx grep -r "ssl_certificate" /etc/nginx/ 2>/dev/null | head -10 || echo "  Could not find ssl_certificate directives"
        
        echo ""
        echo "Reading certificate that nginx is using:"
        CERT_PATH=$(docker exec nginx grep -h "ssl_certificate " /etc/nginx/conf.d/*.conf 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';' || echo "")
        if [ -n "$CERT_PATH" ]; then
            echo "  Configured path: $CERT_PATH"
            docker exec nginx cat "$CERT_PATH" 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null || echo "  Could not read certificate"
        fi
    else
        echo -e "${RED}✗ Nginx container is not running${NC}"
    fi
    echo ""

    # 4. Search for certificate files on host filesystem
    echo -e "${YELLOW}[4/8] Searching for certificate files on host filesystem...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    echo "Looking for .pem files..."
    find /etc /home /root /var -name "*.pem" -type f 2>/dev/null | grep -E "(fullchain|privkey|cert|chain)" | head -20 || echo "  None found"
    
    echo ""
    echo "Looking for letsencrypt directories..."
    find / -type d -name "letsencrypt" 2>/dev/null | head -10 || echo "  None found"
    
    echo ""
    echo "Looking for self-signed certificate directories..."
    find / -type d -name "ssl" 2>/dev/null | grep -v proc | head -10 || echo "  None found"
    echo ""

    # 5. Check Docker volumes mount paths
    echo -e "${YELLOW}[5/8] Checking all Docker volume mount paths...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    docker volume ls --format "{{.Name}}" | while read vol; do
        if echo "$vol" | grep -qiE "ssl|cert|letsencrypt"; then
            echo "Volume: $vol"
            docker volume inspect "$vol" --format '  Mountpoint: {{.Mountpoint}}'
        fi
    done
    echo ""

    # 6. Check nginx configuration
    echo -e "${YELLOW}[6/8] Checking nginx SSL configuration...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    if [ -f "${PROJECT_DIR}/services/nginx/conf.d/10-freddy-services.conf" ]; then
        echo "SSL configuration in 10-freddy-services.conf:"
        grep -E "ssl_certificate|ssl_certificate_key" "${PROJECT_DIR}/services/nginx/conf.d/10-freddy-services.conf" | head -10
    fi
    
    if [ -f "${PROJECT_DIR}/docker/nginx/entrypoint.sh" ]; then
        echo ""
        echo "Entrypoint certificate handling:"
        grep -A5 -B5 "ssl_certificate\|fullchain\|privkey\|self-signed" "${PROJECT_DIR}/docker/nginx/entrypoint.sh" | head -40
    fi
    echo ""

    # 7. Check docker-compose volume configuration
    echo -e "${YELLOW}[7/8] Checking docker-compose.yml volume configuration...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    if [ -f "${PROJECT_DIR}/docker-compose.yml" ]; then
        echo "Nginx volumes in docker-compose.yml:"
        grep -A20 "nginx:" "${PROJECT_DIR}/docker-compose.yml" | grep -E "volumes:|ssl-certs|/etc/letsencrypt|/etc/nginx/ssl" | head -10
        
        echo ""
        echo "Top-level volumes definition:"
        grep -A10 "^volumes:" "${PROJECT_DIR}/docker-compose.yml" | head -15
    fi
    echo ""

    # 8. Check if there are cached/old certificates
    echo -e "${YELLOW}[8/8] Checking for potential certificate conflicts...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    echo "All SSL-related volumes:"
    docker volume ls | grep -iE "ssl|cert|letsencrypt" || echo "  None found"
    
    echo ""
    echo "Checking /var/lib/docker/volumes for cert-related data:"
    ls -la /var/lib/docker/volumes/ 2>/dev/null | grep -iE "ssl|cert" || echo "  None found"
    echo ""
}

# =============================================================================
# CLEANUP FUNCTIONS  
# =============================================================================

cleanup_certificates() {
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}                    CERTIFICATE CLEANUP                            ${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  WARNING: This will remove ALL certificates and stop services!${NC}"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cleanup cancelled."
        return 1
    fi
    echo ""

    # 1. Stop all services
    echo -e "${YELLOW}[1/7] Stopping all Docker services...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    cd "${PROJECT_DIR}" 2>/dev/null || cd ~/freddy
    if [ -x "./run.sh" ]; then
        ./run.sh stop 2>/dev/null || true
    fi
    docker compose down --remove-orphans 2>/dev/null || true
    docker stop nginx 2>/dev/null || true
    docker rm -f nginx 2>/dev/null || true
    echo -e "${GREEN}✓ Services stopped${NC}"
    echo ""

    # 2. Remove ssl-certs Docker volume
    echo -e "${YELLOW}[2/7] Removing ssl-certs Docker volumes...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    docker volume rm ssl-certs 2>/dev/null && echo -e "${GREEN}✓ Removed ssl-certs volume${NC}" || echo "  ssl-certs volume didn't exist"
    docker volume rm freddy_ssl-certs 2>/dev/null && echo -e "${GREEN}✓ Removed freddy_ssl-certs volume${NC}" || echo "  freddy_ssl-certs volume didn't exist"
    echo ""

    # 3. Remove any other cert-related volumes
    echo -e "${YELLOW}[3/7] Removing other certificate-related volumes...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    for vol in $(docker volume ls -q | grep -iE "ssl|cert|letsencrypt" 2>/dev/null); do
        echo "  Removing volume: $vol"
        docker volume rm "$vol" 2>/dev/null || true
    done
    echo -e "${GREEN}✓ Certificate volumes cleaned${NC}"
    echo ""

    # 4. Remove local certificate directories
    echo -e "${YELLOW}[4/7] Removing local certificate directories...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    
    # Common locations to clean
    CERT_DIRS=(
        "/etc/letsencrypt"
        "${PROJECT_DIR}/certs"
        "${PROJECT_DIR}/ssl"
        "${PROJECT_DIR}/certificates"
        "${PROJECT_DIR}/services/nginx/ssl"
        "${HOME}/certs"
        "${HOME}/ssl"
        "${HOME}/letsencrypt"
    )
    
    for dir in "${CERT_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo "  Removing: $dir"
            rm -rf "$dir" 2>/dev/null || true
        fi
    done
    echo -e "${GREEN}✓ Local certificate directories cleaned${NC}"
    echo ""

    # 5. Remove nginx images to force rebuild
    echo -e "${YELLOW}[5/7] Removing nginx Docker images (forces rebuild)...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    docker rmi freddy-nginx 2>/dev/null && echo "  Removed freddy-nginx" || echo "  freddy-nginx not found"
    docker rmi $(docker images -q --filter "reference=*nginx*" --filter "dangling=false" 2>/dev/null) 2>/dev/null || true
    echo -e "${GREEN}✓ Nginx images cleaned${NC}"
    echo ""

    # 6. Prune Docker build cache
    echo -e "${YELLOW}[6/7] Pruning Docker build cache...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    docker builder prune -af 2>/dev/null || true
    echo -e "${GREEN}✓ Build cache pruned${NC}"
    echo ""

    # 7. Create fresh ssl-certs volume
    echo -e "${YELLOW}[7/7] Creating fresh ssl-certs volume...${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    docker volume create ssl-certs
    echo -e "${GREEN}✓ Fresh ssl-certs volume created${NC}"
    echo ""

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    CLEANUP COMPLETE                              ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Re-run the GitHub Actions workflow with 'force_ssl_regen' enabled"
    echo "  2. Or manually run: docker compose up -d"
    echo ""
    echo "The CI workflow will:"
    echo "  - Generate new Let's Encrypt certificates"
    echo "  - Store them in the ssl-certs Docker volume"
    echo "  - Rebuild nginx with fresh certificates"
    echo ""
}

# =============================================================================
# ADDITIONAL DIAGNOSTIC: Check what's actually in the nginx container
# =============================================================================

deep_nginx_check() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                 DEEP NGINX CERTIFICATE CHECK                      ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if ! docker ps --format '{{.Names}}' | grep -q "^nginx$"; then
        echo -e "${RED}Nginx container is not running. Starting it first...${NC}"
        cd "${PROJECT_DIR}" 2>/dev/null || cd ~/freddy
        docker compose up -d nginx 2>/dev/null || true
        sleep 5
    fi

    echo -e "${YELLOW}Checking nginx container internals...${NC}"
    echo ""

    # Check all possible certificate locations inside container
    echo "1. Contents of /etc/nginx/ssl/:"
    docker exec nginx sh -c "ls -la /etc/nginx/ssl/ 2>/dev/null || echo '  (directory empty or missing)'"
    
    echo ""
    echo "2. Contents of /etc/letsencrypt/live/${DOMAIN}/:"
    docker exec nginx sh -c "ls -la /etc/letsencrypt/live/${DOMAIN}/ 2>/dev/null || echo '  (directory empty or missing)'"
    
    echo ""
    echo "3. Full nginx SSL config:"
    docker exec nginx sh -c "grep -r 'ssl_' /etc/nginx/conf.d/ 2>/dev/null | head -20 || echo '  (no ssl config found)'"
    
    echo ""
    echo "4. Certificate being used by nginx (reading actual file):"
    docker exec nginx sh -c "
        CERT_FILE=\$(grep -h 'ssl_certificate ' /etc/nginx/conf.d/*.conf 2>/dev/null | head -1 | awk '{print \$2}' | tr -d ';')
        if [ -n \"\$CERT_FILE\" ] && [ -f \"\$CERT_FILE\" ]; then
            echo \"  File: \$CERT_FILE\"
            openssl x509 -in \"\$CERT_FILE\" -noout -issuer -subject -dates 2>/dev/null
        else
            echo \"  Could not find certificate file\"
        fi
    "
    
    echo ""
    echo "5. Checking if /etc/letsencrypt is a volume mount:"
    docker inspect nginx --format '{{range .Mounts}}{{if eq .Destination "/etc/letsencrypt"}}FOUND: {{.Source}} -> {{.Destination}} ({{.Type}}){{end}}{{end}}' 2>/dev/null || echo "  Not mounted"
    
    echo ""
    echo "6. Nginx entrypoint output (last run):"
    docker logs nginx 2>&1 | grep -iE "certificate|ssl|letsencrypt|self-signed" | tail -20 || echo "  (no relevant logs)"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

case "${1:-both}" in
    diagnose|d)
        diagnose_certificates
        deep_nginx_check
        ;;
    cleanup|c)
        cleanup_certificates
        ;;
    both|b|"")
        diagnose_certificates
        deep_nginx_check
        echo ""
        echo -e "${YELLOW}Would you like to perform cleanup?${NC}"
        read -p "Proceed with cleanup? (yes/no): " DO_CLEANUP
        if [ "$DO_CLEANUP" = "yes" ]; then
            cleanup_certificates
        fi
        ;;
    *)
        echo "Usage: $0 [diagnose|cleanup|both]"
        echo ""
        echo "  diagnose - Only run diagnostics to find certificate issues"
        echo "  cleanup  - Clean up all certificates and prepare for fresh start"
        echo "  both     - Run diagnostics then optionally cleanup (default)"
        exit 1
        ;;
esac

echo -e "${CYAN}Done!${NC}"
