# =============================================================================
# Freddy Nextcloud Production Dockerfile
# =============================================================================
# Custom Nextcloud image built on the official nextcloud:stable-apache base.
#
# Two-stage build:
#   1. Builder  – copies config files and validates PHP syntax
#   2. Production – installs extras, bakes in configs & helper scripts
#
# Runtime behaviour:
#   - The official entrypoint runs as root for init (install / upgrade),
#     then Apache drops privileges to www-data.
#   - Custom config files are applied via the before-starting hook so they
#     survive Nextcloud upgrades.
#   - An `occ` wrapper is provided at /usr/local/bin/occ for convenience.
#
# Data ownership:
#   - /var/www/html        – Nextcloud application (www-data:www-data)
#   - /var/www/html/data   – User files           (www-data:www-data)
#   - /var/www/html/config – Generated configs     (www-data:www-data)
# =============================================================================

# =============================================================================
# Stage 1: Builder – validate configuration files
# =============================================================================
FROM nextcloud:stable-apache AS builder

# Copy custom Nextcloud config overrides for validation
COPY services/nextcloud/config/ /tmp/nextcloud-config/

# Validate PHP syntax on every config file so we fail fast at build time
RUN set -e; \
    for f in /tmp/nextcloud-config/*.config.php; do \
    echo "Validating: $(basename "$f")"; \
    php -l "$f" || exit 1; \
    done; \
    echo "✅ All config files passed syntax validation"

# =============================================================================
# Stage 2: Production image
# =============================================================================
FROM nextcloud:stable-apache AS production

LABEL maintainer="nuniesmith"
LABEL description="Freddy Nextcloud – custom image with baked-in config"

# ── Install additional packages ──────────────────────────────────────────────
# ffmpeg            – video thumbnail / preview generation
# imagemagick-extra – HEIC, SVG, and additional format support (version-agnostic
#                     glob handles Debian Bookworm→Trixie package name changes)
# procps            – ps, top (debugging inside the container)
# sudo              – run occ as www-data from any shell user
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    procps \
    sudo \
    && apt-get install -y --no-install-recommends \
    libmagickcore-*-extra 2>/dev/null \
    || echo "ImageMagick extra formats package not found, skipping" \
    && rm -rf /var/lib/apt/lists/*

# ── Copy validated config files from builder ─────────────────────────────────
# Staged into a holding directory; the before-starting hook copies them into
# /var/www/html/config/ at every container start so they survive upgrades.
COPY --from=builder /tmp/nextcloud-config/ /usr/src/nextcloud-custom-config/

# ── Entrypoint hooks (official image calls these automatically) ──────────────
COPY docker/nextcloud/hooks/before-starting/  /docker-entrypoint-hooks.d/before-starting/
COPY docker/nextcloud/hooks/post-installation/ /docker-entrypoint-hooks.d/post-installation/

RUN chmod -R +x /docker-entrypoint-hooks.d/

# ── OCC wrapper script ──────────────────────────────────────────────────────
# Allows running:  docker exec nextcloud occ files:scan --all
# The wrapper ensures commands always execute as www-data regardless of the
# calling user (root inside the container, or via docker exec).
RUN { \
    echo '#!/bin/bash'; \
    echo 'set -e'; \
    echo ''; \
    echo '# Run occ as www-data, the only user that should touch Nextcloud data'; \
    echo 'if [ "$(id -u)" -eq 0 ]; then'; \
    echo '    exec sudo -E -u www-data php /var/www/html/occ "$@"'; \
    echo 'else'; \
    echo '    exec php /var/www/html/occ "$@"'; \
    echo 'fi'; \
    } > /usr/local/bin/occ \
    && chmod +x /usr/local/bin/occ

# ── Cron helper (used by the nextcloud-cron sidecar container) ───────────────
# The sidecar starts the same image with `entrypoint: /cron.sh`.  The official
# image already ships /cron.sh, but we ensure it exists and is executable.
RUN test -f /cron.sh && chmod +x /cron.sh || { \
    echo '#!/bin/sh'; \
    echo 'set -e'; \
    echo '# Run Nextcloud cron.php every 5 minutes'; \
    echo 'while true; do'; \
    echo '    su -s /bin/sh www-data -c "php -f /var/www/html/cron.php"'; \
    echo '    sleep 300'; \
    echo 'done'; \
    } > /cron.sh && chmod +x /cron.sh

# ── Allow www-data to use sudo without password (for occ wrapper) ────────────
RUN echo 'www-data ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/nextcloud \
    && chmod 0440 /etc/sudoers.d/nextcloud

# ── PHP tuning (upload limits, memory, opcache) ─────────────────────────────
RUN { \
    echo 'upload_max_filesize=10G'; \
    echo 'post_max_size=10G'; \
    echo 'memory_limit=1G'; \
    echo 'max_execution_time=3600'; \
    echo 'max_input_time=3600'; \
    echo 'output_buffering=0'; \
    } > "$PHP_INI_DIR/conf.d/nextcloud-tuning.ini"

# ── OPcache tuning for Nextcloud recommendations ────────────────────────────
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.interned_strings_buffer=32'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.revalidate_freq=1'; \
    echo 'opcache.jit=1255'; \
    echo 'opcache.jit_buffer_size=128M'; \
    } > "$PHP_INI_DIR/conf.d/opcache-tuning.ini"

# ── Apache tuning ────────────────────────────────────────────────────────────
# Increase Apache timeout for large file uploads behind nginx reverse proxy
RUN { \
    echo 'Timeout 3600'; \
    echo 'ProxyTimeout 3600'; \
    } > /etc/apache2/conf-available/timeout.conf \
    && a2enconf timeout

# ── Set data directory permissions ───────────────────────────────────────────
RUN mkdir -p /var/www/html/data /var/www/html/config /var/www/html/custom_apps \
    && chown -R www-data:www-data /var/www/html/data \
    /var/www/html/config \
    /var/www/html/custom_apps \
    /usr/src/nextcloud-custom-config

EXPOSE 80

# The official entrypoint handles Nextcloud installation, upgrades, and hooks,
# then starts Apache.  We do not override it.
# ENTRYPOINT ["/entrypoint.sh"]  ← inherited from base image
# CMD ["apache2-foreground"]     ← inherited from base image
