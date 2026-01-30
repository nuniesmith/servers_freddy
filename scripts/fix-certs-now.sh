#!/bin/bash
# =============================================================================
# IMMEDIATE SSL CERTIFICATE FIX
# =============================================================================
# This script fixes the corrupted SSL certificates RIGHT NOW.
#
# Problem: The privkey.pem in /opt/ssl/7gram.xyz is corrupted (241 bytes)
# Solution: Copy valid certs from /etc/letsencrypt/live/7gram.xyz/
#
# Usage: sudo ./fix-certs-now.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "=========================================="
echo -e "${BLUE}🔧 FIXING SSL CERTIFICATES NOW${NC}"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Run: sudo $0"
    exit 1
fi

DOMAIN="7gram.xyz"
SOURCE_DIR="/etc/letsencrypt/live/$DOMAIN"
TARGET_DIR="/opt/ssl/$DOMAIN"
BACKUP_DIR="/opt/ssl/backup-$(date +%Y%m%d-%H%M%S)"

# Step 1: Verify source certificates exist
echo -e "${BLUE}[1/6]${NC} Checking source certificates..."
if [ ! -f "$SOURCE_DIR/fullchain.pem" ] || [ ! -f "$SOURCE_DIR/privkey.pem" ]; then
    echo -e "${RED}ERROR: Source certificates not found in $SOURCE_DIR${NC}"
    echo "Please generate certificates with certbot first!"
    exit 1
fi
echo -e "${GREEN}✓ Source certificates found${NC}"

# Step 2: Verify source certificates are valid
echo -e "${BLUE}[2/6]${NC} Validating source certificates..."
if ! openssl x509 -in "$SOURCE_DIR/fullchain.pem" -noout -text >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Source certificate is invalid${NC}"
    exit 1
fi

if ! openssl rsa -in "$SOURCE_DIR/privkey.pem" -check -noout >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Source private key is invalid${NC}"
    exit 1
fi

CERT_MOD=$(openssl x509 -noout -modulus -in "$SOURCE_DIR/fullchain.pem" | openssl md5)
KEY_MOD=$(openssl rsa -noout -modulus -in "$SOURCE_DIR/privkey.pem" | openssl md5)

if [ "$CERT_MOD" != "$KEY_MOD" ]; then
    echo -e "${RED}ERROR: Source certificate and key don't match!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Source certificates are valid and match${NC}"
echo "  Cert modulus: $CERT_MOD"
echo "  Key modulus:  $KEY_MOD"

# Step 3: Backup corrupted certificates
echo -e "${BLUE}[3/6]${NC} Backing up corrupted certificates..."
if [ -d "$TARGET_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -r "$TARGET_DIR/"* "$BACKUP_DIR/" 2>/dev/null || true
    echo -e "${GREEN}✓ Backup created at $BACKUP_DIR${NC}"
else
    echo -e "${YELLOW}⚠ No existing certificates to backup${NC}"
fi

# Step 4: Copy valid certificates
echo -e "${BLUE}[4/6]${NC} Copying valid certificates..."
mkdir -p "$TARGET_DIR"
cp "$SOURCE_DIR/fullchain.pem" "$TARGET_DIR/fullchain.pem"
cp "$SOURCE_DIR/privkey.pem" "$TARGET_DIR/privkey.pem"
chmod 644 "$TARGET_DIR/fullchain.pem"
chmod 600 "$TARGET_DIR/privkey.pem"

# Verify copied files
COPIED_CERT_MOD=$(openssl x509 -noout -modulus -in "$TARGET_DIR/fullchain.pem" | openssl md5)
COPIED_KEY_MOD=$(openssl rsa -noout -modulus -in "$TARGET_DIR/privkey.pem" | openssl md5)

if [ "$COPIED_CERT_MOD" != "$COPIED_KEY_MOD" ]; then
    echo -e "${RED}ERROR: Copy failed - certificates don't match!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Certificates copied successfully${NC}"
ls -lh "$TARGET_DIR/"
echo ""

# Step 5: Stop and remove nginx container
echo -e "${BLUE}[5/6]${NC} Stopping nginx container..."
docker stop nginx 2>/dev/null || true
docker rm nginx 2>/dev/null || true
echo -e "${GREEN}✓ Nginx container removed${NC}"

# Step 6: Rebuild and start nginx with fresh certs
echo -e "${BLUE}[6/6]${NC} Rebuilding nginx with fresh certificates..."
cd ~/freddy 2>/dev/null || cd /home/*/freddy 2>/dev/null || cd /root/freddy 2>/dev/null || {
    echo -e "${RED}ERROR: Could not find freddy directory${NC}"
    exit 1
}

docker compose build --no-cache nginx
docker compose up -d nginx

# Wait for nginx to start
echo ""
echo -e "${YELLOW}Waiting for nginx to start...${NC}"
sleep 5

# Check nginx status
if docker ps | grep -q "nginx"; then
    echo -e "${GREEN}✓ Nginx is running${NC}"

    # Check logs for success
    echo ""
    echo "Recent nginx logs:"
    docker logs nginx --tail 20 | grep -E "\[INFO\]|\[ERROR\]|\[SUCCESS\]" || true
else
    echo -e "${RED}ERROR: Nginx failed to start${NC}"
    echo ""
    echo "Check logs with: docker logs nginx"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}🎉 SSL CERTIFICATES FIXED!${NC}"
echo "=========================================="
echo ""
echo -e "${GREEN}✓ Valid certificates copied to $TARGET_DIR${NC}"
echo -e "${GREEN}✓ Nginx container rebuilt with fresh certs${NC}"
echo -e "${GREEN}✓ Nginx is running${NC}"
echo ""
echo "Test with: curl -kI https://localhost/health"
echo ""
