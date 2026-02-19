<?php

/**
 * Nextcloud Performance Tuning Configuration
 * ============================================================================
 * Applied automatically by the before-starting hook on every container start.
 *
 * Covers caching, background jobs, logging, and general performance settings
 * recommended for a self-hosted Nextcloud behind a reverse proxy.
 *
 * @see https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/caching_configuration.html
 * @see https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/background_jobs_configuration.html
 */

$CONFIG = array(

    // ── Local Cache (APCu) ──────────────────────────────────────────────────
    // APCu is bundled with the official Nextcloud image and provides fast
    // in-memory caching for frequently accessed data on a single server.
    'memcache.local' => '\OC\Memcache\APCu',

    // ── Background Jobs ─────────────────────────────────────────────────────
    // The nextcloud-cron sidecar container runs cron.php every 5 minutes.
    // This is far more reliable than AJAX-triggered background jobs.
    'background_job_mode' => 'cron',

    // ── Maintenance Window ──────────────────────────────────────────────────
    // Heavy background tasks (e.g. file cleanup, expiration) will only run
    // during the maintenance window.  Value is the UTC hour (0-23).
    'maintenance_window_start' => 4,

    // ── Logging ─────────────────────────────────────────────────────────────
    // Log to the container's stdout via the built-in file logger pointing at
    // the default log path.  Level 2 = WARN (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR).
    'loglevel'       => 2,
    'log_type'       => 'file',
    'logfile'        => '/var/www/html/data/nextcloud.log',
    'log_rotate_size' => 10485760, // 10 MB – rotated automatically by Nextcloud
    'logdateformat'  => 'Y-m-d H:i:s T',

    // ── Locale & Region ─────────────────────────────────────────────────────
    'default_locale'       => 'en_CA',
    'default_phone_region' => 'CA',

    // ── File Handling ───────────────────────────────────────────────────────
    // Allow chunked uploads for large files (matches PHP / nginx limits).
    'trashbin_retention_obligation' => 'auto, 30',
    'versions_retention_obligation' => 'auto, 365',

    // ── Previews ────────────────────────────────────────────────────────────
    'enable_previews'      => true,
    'preview_max_x'        => 2048,
    'preview_max_y'        => 2048,
    'preview_max_filesize_image' => 50, // MB

    // ── Integrity & Security ────────────────────────────────────────────────
    'check_data_directory_permissions' => true,
    'check_for_working_wellknown_setup' => true,

    // ── Connection Handling ─────────────────────────────────────────────────
    // Increase timeout for operations on large files or slow storage.
    'connection_timeout' => 60,

    // ── Filesystem Check ────────────────────────────────────────────────────
    // Disable the filesystem check on every request for better performance.
    // Files added outside Nextcloud can be picked up via `occ files:scan`.
    'filesystem_check_changes' => 0,

    // ── Share Settings ──────────────────────────────────────────────────────
    'share_folder' => '/Shares',

    // ── Temp Directory ──────────────────────────────────────────────────────
    'tempdirectory' => '/tmp',
);
