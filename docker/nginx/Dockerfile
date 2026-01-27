# =============================================================================
# Freddy Nginx Production Dockerfile
# =============================================================================
# This Dockerfile bakes all nginx configuration into the image so no host
# volume mounts are needed for config files. SSL certificates are still
# mounted from Docker volumes at runtime.
#
# =============================================================================

FROM nginx:alpine AS base

# Install required tools
RUN apk add --no-cache \
    curl \
    openssl \
    && rm -rf /var/cache/apk/*

# =============================================================================
# Production Stage
# =============================================================================
FROM base AS production

# Create directories
RUN mkdir -p /etc/nginx/conf.d \
    /etc/nginx/ssl \
    /etc/letsencrypt \
    /var/www/certbot \
    /var/log/nginx \
    /var/cache/nginx

# Copy nginx configuration files
COPY services/nginx/conf.d/ /etc/nginx/conf.d/

# Generate self-signed fallback certificate for initial startup
# This allows nginx to start before Let's Encrypt certs are available
RUN mkdir -p /etc/nginx/ssl/fallback && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/fallback/privkey.pem \
    -out /etc/nginx/ssl/fallback/fullchain.pem \
    -subj "/C=CA/ST=Ontario/L=Toronto/O=Freddy/CN=7gram.xyz" \
    -addext "subjectAltName = DNS:7gram.xyz,DNS:*.7gram.xyz" && \
    # Create the directory for cert symlinks (symlinks created at runtime by entrypoint)
    mkdir -p /etc/letsencrypt/live/7gram.xyz

# Set proper permissions for fallback certs
RUN chmod 644 /etc/nginx/ssl/fallback/fullchain.pem && \
    chmod 600 /etc/nginx/ssl/fallback/privkey.pem && \
    chown nginx:nginx /etc/nginx/ssl/fallback/*.pem

# Copy entrypoint script
COPY docker/nginx/entrypoint.sh /docker-entrypoint.d/99-init.sh
RUN chmod +x /docker-entrypoint.d/99-init.sh

# Set proper permissions
RUN chown -R nginx:nginx /var/cache/nginx /var/log/nginx && \
    chmod -R 755 /etc/nginx

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf http://localhost/health > /dev/null || exit 1

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
