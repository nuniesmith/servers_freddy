#!/bin/bash
# =============================================================================
# SSL Certificate Verification Script
# =============================================================================
# This script checks the ssl-certs Docker volume and verifies certificates
# Run on the Freddy server to check SSL certificate status
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

DOMAIN="${DOMAIN:-7gram.xyz}"

echo ""
echo "=========================================="
echo -e "${CYAN}SSL Certificate Verification${NC}"
echo "=========================================="
echo ""

# Check if ssl-certs volume exists
echo -e "${BLUE}[1/6]${NC} Checking for ssl-certs Docker volume..."
if docker volume inspect ssl-certs >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} ssl-certs volume exists"
else
    echo -e "  ${RED}✗${NC} ssl-certs volume NOT found"
    echo ""
    echo -e "${YELLOW}Action needed:${NC} Run GitHub Actions workflow with 'force_ssl_regen: true'"
    exit 1
fi

# List volume contents
echo ""
echo -e "${BLUE}[2/6]${NC} Checking volume contents..."
echo ""
docker run --rm -v ssl-certs:/certs:ro busybox:latest ls -lR /certs 2>/dev/null || {
    echo -e "  ${YELLOW}⚠${NC}  Volume is empty"
}

# Check for Let's Encrypt certificates
echo ""
echo -e "${BLUE}[3/6]${NC} Checking for Let's Encrypt certificates..."
if docker run --rm -v ssl-certs:/certs:ro busybox:latest test -f /certs/live/$DOMAIN/fullchain.pem 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Certificate found: /certs/live/$DOMAIN/fullchain.pem"
    CERT_EXISTS=true
else
    echo -e "  ${YELLOW}⚠${NC}  Let's Encrypt certificates not found"
    echo -e "     Nginx will use self-signed fallback certificates"
    CERT_EXISTS=false
fi

if docker run --rm -v ssl-certs:/certs:ro busybox:latest test -f /certs/live/$DOMAIN/privkey.pem 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Private key found: /certs/live/$DOMAIN/privkey.pem"
else
    echo -e "  ${YELLOW}⚠${NC}  Private key not found"
fi

# Check certificate details if it exists
if [ "$CERT_EXISTS" = true ]; then
    echo ""
    echo -e "${BLUE}[4/6]${NC} Checking certificate details..."
    echo ""
    
    # Get certificate info
    docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
        -in /certs/live/$DOMAIN/fullchain.pem -noout -text 2>/dev/null | grep -A 2 "Issuer:\|Not Before\|Not After\|Subject:\|DNS:" | while read line; do
        echo "  $line"
    done
    
    # Check issuer
    echo ""
    ISSUER=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
        -in /certs/live/$DOMAIN/fullchain.pem -noout -issuer 2>/dev/null)
    
    if echo "$ISSUER" | grep -qi "Let's Encrypt"; then
        echo -e "  ${GREEN}✓${NC} Certificate issued by: Let's Encrypt"
        CERT_TYPE="Let's Encrypt (Production)"
    elif echo "$ISSUER" | grep -qi "Staging"; then
        echo -e "  ${YELLOW}⚠${NC}  Certificate issued by: Let's Encrypt Staging"
        CERT_TYPE="Let's Encrypt (Staging - not trusted by browsers)"
    else
        echo -e "  ${YELLOW}⚠${NC}  Certificate issued by: $ISSUER"
        CERT_TYPE="Unknown/Self-Signed"
    fi
    
    # Check expiration
    echo ""
    if docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
        -in /certs/live/$DOMAIN/fullchain.pem -noout -checkend 0 >/dev/null 2>&1; then
        EXPIRY=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
            -in /certs/live/$DOMAIN/fullchain.pem -noout -enddate 2>/dev/null | cut -d= -f2)
        echo -e "  ${GREEN}✓${NC} Certificate is valid (expires: $EXPIRY)"
    else
        echo -e "  ${RED}✗${NC} Certificate is EXPIRED!"
    fi
    
    # Check if expiring soon (30 days)
    if docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
        -in /certs/live/$DOMAIN/fullchain.pem -noout -checkend 2592000 >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Certificate has > 30 days until expiration"
    else
        echo -e "  ${YELLOW}⚠${NC}  Certificate expires in < 30 days (renewal recommended)"
    fi
fi

# Verify certificate/key match
if [ "$CERT_EXISTS" = true ]; then
    echo ""
    echo -e "${BLUE}[5/6]${NC} Verifying certificate/key pair match..."
    
    CERT_MOD=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
        -noout -modulus -in /certs/live/$DOMAIN/fullchain.pem 2>/dev/null | openssl md5 || echo "error")
    KEY_MOD=$(docker run --rm -v ssl-certs:/certs:ro alpine/openssl rsa \
        -noout -modulus -in /certs/live/$DOMAIN/privkey.pem 2>/dev/null | openssl md5 || echo "error")
    
    if [ "$CERT_MOD" = "$KEY_MOD" ] && [ "$CERT_MOD" != "error" ]; then
        echo -e "  ${GREEN}✓${NC} Certificate and private key MATCH"
    else
        echo -e "  ${RED}✗${NC} Certificate and private key DO NOT MATCH!"
        echo -e "     ${YELLOW}Action needed:${NC} Run workflow with 'force_ssl_regen: true'"
    fi
fi

# Check nginx container
echo ""
echo -e "${BLUE}[6/6]${NC} Checking nginx container status..."

if docker ps --filter "name=nginx" --format "{{.Names}}" | grep -q "nginx"; then
    echo -e "  ${GREEN}✓${NC} Nginx container is running"
    
    # Check what certs nginx is using
    echo ""
    echo "  Certificates in nginx container:"
    docker exec nginx ls -lh /etc/nginx/ssl/ 2>/dev/null | tail -n +2 | while read line; do
        echo "    $line"
    done
    
    # Check certificate issuer in nginx
    echo ""
    NGINX_ISSUER=$(docker exec nginx openssl x509 -in /etc/nginx/ssl/fullchain.pem -noout -issuer 2>/dev/null || echo "error")
    if echo "$NGINX_ISSUER" | grep -qi "Let's Encrypt"; then
        echo -e "  ${GREEN}✓${NC} Nginx is using Let's Encrypt certificates"
    else
        echo -e "  ${YELLOW}⚠${NC}  Nginx is using fallback certificates"
        echo "    $NGINX_ISSUER"
    fi
else
    echo -e "  ${YELLOW}⚠${NC}  Nginx container is not running"
fi

# Summary
echo ""
echo "=========================================="
echo -e "${CYAN}Summary${NC}"
echo "=========================================="
echo ""
if [ "$CERT_EXISTS" = true ]; then
    echo -e "${GREEN}Certificate Type:${NC} $CERT_TYPE"
    echo -e "${GREEN}Status:${NC} Certificates are present in ssl-certs volume"
    echo -e "${GREEN}Location:${NC} /certs/live/$DOMAIN/"
    echo ""
    if echo "$CERT_TYPE" | grep -q "Production"; then
        echo -e "${GREEN}✓ Production SSL certificates are active${NC}"
    else
        echo -e "${YELLOW}⚠ Non-production certificates detected${NC}"
    fi
else
    echo -e "${YELLOW}Status:${NC} No Let's Encrypt certificates found"
    echo -e "${YELLOW}Action:${NC} Run GitHub Actions workflow with 'force_ssl_regen: true'"
fi
echo ""
echo "=========================================="
