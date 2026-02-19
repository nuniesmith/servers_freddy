<?php

/**
 * Nextcloud Reverse Proxy Configuration
 * ============================================================================
 * Applied automatically by the before-starting hook on every container start.
 *
 * This file configures Nextcloud to work correctly behind the Freddy nginx
 * reverse proxy, which terminates TLS and forwards requests over HTTP.
 *
 * @see https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html
 */

$CONFIG = array(

    // ── Trusted Proxies ─────────────────────────────────────────────────────
    // Docker bridge networks and common private ranges used by the nginx
    // reverse proxy.  Nextcloud will honour X-Forwarded-* headers from these.
    'trusted_proxies' => array(
        '172.16.0.0/12',
        '10.0.0.0/8',
        '192.168.0.0/16',
    ),

    // ── Forwarded Headers ───────────────────────────────────────────────────
    'forwarded_for_headers' => array(
        'HTTP_X_FORWARDED_FOR',
    ),

    // ── Protocol & Host Overwrite ───────────────────────────────────────────
    // nginx terminates TLS, so the internal connection is HTTP.  These
    // settings ensure Nextcloud generates https:// URLs and uses the correct
    // public hostname.
    'overwriteprotocol' => 'https',
    'overwritehost'     => 'nc.7gram.xyz',
    'overwrite.cli.url' => 'https://nc.7gram.xyz',
    'overwritecondaddr' => '^172\\.1[6-9]\\.|^172\\.2[0-9]\\.|^172\\.3[0-1]\\.|^10\\.|^192\\.168\\.',

    // ── Trusted Domains ─────────────────────────────────────────────────────
    // Hostnames / IPs that are allowed to access this Nextcloud instance.
    // The installer sets index 0 automatically; we add our public domain and
    // the Docker service name so health checks and inter-container calls work.
    'trusted_domains' => array(
        0 => 'localhost',
        1 => 'nc.7gram.xyz',
        2 => 'nextcloud',
    ),
);
