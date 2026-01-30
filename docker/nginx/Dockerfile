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
    /etc/nginx/ssl/fallback \
    /etc/letsencrypt/live/7gram.xyz \
    /var/www/certbot \
    /var/log/nginx \
    /var/cache/nginx \
    /dashboard

# Remove default nginx config that comes with the base image
RUN rm -f /etc/nginx/conf.d/default.conf

# Copy nginx configuration files
COPY services/nginx/nginx.conf /etc/nginx/nginx.conf
COPY services/nginx/conf.d/ /etc/nginx/conf.d/

# Generate self-signed fallback certificate for initial startup
# This allows nginx to start before Let's Encrypt certs are available
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/fallback/privkey.pem \
    -out /etc/nginx/ssl/fallback/fullchain.pem \
    -subj "/C=CA/ST=Ontario/L=Toronto/O=Freddy/CN=7gram.xyz" \
    -addext "subjectAltName=DNS:7gram.xyz,DNS:*.7gram.xyz"

# Set proper permissions for fallback certs
RUN chmod 644 /etc/nginx/ssl/fallback/fullchain.pem && \
    chmod 600 /etc/nginx/ssl/fallback/privkey.pem && \
    chown nginx:nginx /etc/nginx/ssl/fallback/*.pem

# Copy dashboard HTML file
COPY services/nginx/dashboard/index.html /dashboard/index.html
RUN chmod 644 /dashboard/index.html

# Copy entrypoint script
COPY docker/nginx/entrypoint.sh /docker-entrypoint.d/99-init.sh
RUN chmod +x /docker-entrypoint.d/99-init.sh

# Set proper permissions
RUN chown -R nginx:nginx /var/cache/nginx /var/log/nginx /dashboard && \
    chmod -R 755 /etc/nginx

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -sf http://localhost/health > /dev/null || exit 1

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
