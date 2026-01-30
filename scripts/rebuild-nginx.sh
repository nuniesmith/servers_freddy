#!/bin/bash
# =============================================================================
# Rebuild Nginx Container
# =============================================================================
# This script rebuilds the nginx container to pick up:
# - New dashboard HTML (fixes encoding issues)
# - Fresh SSL certificates
# - Updated nginx configuration
#
# Usage: ./rebuild-nginx.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "=========================================="
echo -e "${BLUE}🔨 Rebuilding Nginx Container${NC}"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}ERROR: docker-compose.yml not found${NC}"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Step 1: Stop nginx
echo -e "${CYAN}[1/5]${NC} Stopping nginx container..."
docker stop nginx 2>/dev/null || true
docker rm nginx 2>/dev/null || true
echo -e "${GREEN}✓ Nginx stopped${NC}"
echo ""

# Step 2: Remove old image (optional but recommended for clean rebuild)
echo -e "${CYAN}[2/5]${NC} Removing old nginx image..."
docker rmi freddy-nginx 2>/dev/null || true
echo -e "${GREEN}✓ Old image removed${NC}"
echo ""

# Step 3: Rebuild nginx with --no-cache
echo -e "${CYAN}[3/5]${NC} Rebuilding nginx with fresh configuration..."
echo -e "${YELLOW}This may take 1-2 minutes...${NC}"
docker compose build --no-cache nginx
echo -e "${GREEN}✓ Nginx rebuilt${NC}"
echo ""

# Step 4: Start nginx
echo -e "${CYAN}[4/5]${NC} Starting nginx..."
docker compose up -d nginx
echo -e "${GREEN}✓ Nginx started${NC}"
echo ""

# Wait for nginx to initialize
echo -e "${YELLOW}Waiting for nginx to initialize...${NC}"
sleep 5

# Step 5: Verify
echo -e "${CYAN}[5/5]${NC} Verifying nginx status..."
echo ""

# Check if container is running
if docker ps | grep -q "nginx"; then
    echo -e "${GREEN}✓ Nginx container is running${NC}"

    # Check if healthy
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' nginx 2>/dev/null || echo "unknown")
    if [ "$HEALTH" = "healthy" ]; then
        echo -e "${GREEN}✓ Nginx health check: PASSED${NC}"
    elif [ "$HEALTH" = "starting" ]; then
        echo -e "${YELLOW}⏳ Nginx health check: STARTING (waiting...)${NC}"
    else
        echo -e "${YELLOW}⚠ Nginx health check: $HEALTH${NC}"
    fi
else
    echo -e "${RED}✗ Nginx container is NOT running${NC}"
    echo ""
    echo "Check logs with: docker logs nginx"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Nginx Rebuild Complete!${NC}"
echo "=========================================="
echo ""

# Show recent logs
echo -e "${CYAN}Recent nginx logs:${NC}"
echo "----------------------------------------"
docker logs nginx --tail 20 | grep -E "\[INFO\]|\[ERROR\]|\[SUCCESS\]|\[CERT\]" || docker logs nginx --tail 20
echo "----------------------------------------"
echo ""

# Test dashboard
echo -e "${CYAN}Testing services:${NC}"
if curl -sf http://localhost/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health endpoint: OK${NC}"
else
    echo -e "${RED}✗ Health endpoint: FAILED${NC}"
fi

if curl -sf http://localhost/ > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Dashboard: OK${NC}"
else
    echo -e "${RED}✗ Dashboard: FAILED${NC}"
fi

echo ""
echo -e "${CYAN}Access your services:${NC}"
echo "  Dashboard:      https://7gram.xyz"
echo "  PhotoPrism:     https://photo.7gram.xyz"
echo "  Nextcloud:      https://nc.7gram.xyz"
echo "  Home Assistant: https://home.7gram.xyz"
echo "  Audiobookshelf: https://abs.7gram.xyz"
echo ""
echo -e "${BLUE}View full logs: docker logs nginx${NC}"
echo ""
