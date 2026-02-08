#!/bin/bash
# Quick fix to properly copy Let's Encrypt certificates to Docker volume

set -e

DOMAIN="7gram.xyz"

echo "================================================"
echo "  SSL Certificate Docker Volume Fix"
echo "================================================"
echo ""

# Stop nginx to release certificate locks
echo "→ Stopping nginx container..."
docker stop nginx 2>/dev/null || true

# Remove and recreate ssl-certs volume  
echo "→ Recreating ssl-certs volume..."
docker volume rm ssl-certs 2>/dev/null || true
docker volume create ssl-certs

# Copy certificates from Let's Encrypt directory to Docker volume
echo "→ Copying Let's Encrypt certificates to Docker volume..."
docker run --rm \
  -v ssl-certs:/certs \
  -v /etc/letsencrypt:/letsencrypt:ro \
  busybox:latest sh -c "
    mkdir -p /certs/live/${DOMAIN} && \
    cp -L /letsencrypt/live/${DOMAIN}/fullchain.pem /certs/live/${DOMAIN}/fullchain.pem && \
    cp -L /letsencrypt/live/${DOMAIN}/privkey.pem /certs/live/${DOMAIN}/privkey.pem && \
    chmod 644 /certs/live/${DOMAIN}/fullchain.pem && \
    chmod 600 /certs/live/${DOMAIN}/privkey.pem && \
    echo 'Files copied:' && \
    ls -lah /certs/live/${DOMAIN}/
  "

# Verify certificates
echo ""
echo "→ Verifying certificates in Docker volume..."
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 \
  -in /certs/live/${DOMAIN}/fullchain.pem \
  -noout -issuer -subject -dates 2>/dev/null || echo "⚠️  Certificate verification failed"

# Also update /opt/ssl for good measure
echo ""
echo "→ Updating /opt/ssl/${DOMAIN}/ ..."
cp -L /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /opt/ssl/${DOMAIN}/fullchain.pem
cp -L /etc/letsencrypt/live/${DOMAIN}/privkey.pem /opt/ssl/${DOMAIN}/privkey.pem
chmod 644 /opt/ssl/${DOMAIN}/fullchain.pem
chmod 600 /opt/ssl/${DOMAIN}/privkey.pem

echo ""
echo "✅ Certificates fixed!"
echo ""
echo "Now restart services with:"
echo "  cd ~/freddy && ./run.sh stop && ./run.sh start"
echo ""
