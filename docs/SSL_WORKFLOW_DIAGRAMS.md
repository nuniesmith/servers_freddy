# SSL Certificate Workflow - Visual Guide

## Complete Certificate Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GITHUB ACTIONS CI/CD PIPELINE                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Trigger: push, schedule, manual
                                      ▼
                     ┌──────────────────────────────┐
                     │   Job 1: dns-update         │
                     │                              │
                     │  • Update Cloudflare DNS     │
                     │  • Point domains to server   │
                     └──────────────────────────────┘
                                      │
                                      │ DNS propagation
                                      ▼
                     ┌──────────────────────────────┐
                     │   Job 2: ssl-generate       │
                     │                              │
                     │  • Connect via Tailscale     │
                     │  • Clean old volumes         │
                     │  • Run certbot              │
                     │  • Cloudflare DNS challenge  │
                     │  • Store in ssl-certs volume│
                     └──────────────────────────────┘
                                      │
                                      │ Volume: ssl-certs created
                                      │ Structure: /certs/live/7gram.xyz/
                                      │   ├── fullchain.pem
                                      │   ├── privkey.pem
                                      │   ├── cert.pem
                                      │   └── chain.pem
                                      ▼
                     ┌──────────────────────────────┐
                     │   Job 3: deploy             │
                     │                              │
                     │  Pre-deploy:                 │
                     │   • Verify certs exist       │
                     │   • Validate cert/key match  │
                     │   • Stop old containers      │
                     │                              │
                     │  Deploy:                     │
                     │   • docker-compose build     │
                     │   • docker-compose up -d     │
                     │                              │
                     │  Post-deploy:                │
                     │   • Health checks            │
                     │   • Status reporting         │
                     └──────────────────────────────┘
                                      │
                                      │ nginx starts
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DOCKER RUNTIME                                   │
└─────────────────────────────────────────────────────────────────────────────┘

            ┌────────────────────────────────────────┐
            │     Docker Volume: ssl-certs           │
            │                                        │
            │   /certs/                              │
            │     └── live/                          │
            │         └── 7gram.xyz/                 │
            │             ├── fullchain.pem          │
            │             ├── privkey.pem            │
            │             ├── cert.pem               │
            │             └── chain.pem              │
            └────────────────────────────────────────┘
                          │ (mounted read-only)
                          │
                          ▼
            ┌────────────────────────────────────────┐
            │     Nginx Container                    │
            │                                        │
            │   Volumes:                             │
            │     ssl-certs:/etc/letsencrypt-volume  │
            │                    (read-only)         │
            │                                        │
            │   ┌──────────────────────────────────┐ │
            │   │  entrypoint.sh (on startup)      │ │
            │   │                                  │ │
            │   │  1. Check certs in volume        │ │
            │   │  2. Copy to /etc/nginx/ssl/      │ │
            │   │  3. Validate cert/key match      │ │
            │   │  4. Test nginx config            │ │
            │   │  5. Start nginx daemon           │ │
            │   └──────────────────────────────────┘ │
            │                                        │
            │   /etc/nginx/ssl/                      │
            │     ├── fullchain.pem (copied)         │
            │     └── privkey.pem (copied)           │
            │                                        │
            │   /etc/nginx/ssl/fallback/             │
            │     ├── fullchain.pem (self-signed)    │
            │     └── privkey.pem (self-signed)      │
            │            (used if LE certs missing)  │
            │                                        │
            │   nginx.conf references:               │
            │     ssl_certificate /etc/nginx/ssl/    │
            │                    fullchain.pem;      │
            │     ssl_certificate_key /etc/nginx/    │
            │                    ssl/privkey.pem;    │
            └────────────────────────────────────────┘
                          │
                          │ Port 443 (HTTPS)
                          ▼
            ┌────────────────────────────────────────┐
            │         Internet Traffic               │
            │                                        │
            │  https://7gram.xyz                     │
            │  https://photo.7gram.xyz               │
            │  https://nc.7gram.xyz                  │
            │  https://*.7gram.xyz                   │
            └────────────────────────────────────────┘
```

## Decision Tree: Which Certificates Are Used?

```
nginx container starts
         │
         ▼
    entrypoint.sh runs
         │
         ├──── Check: Does /etc/letsencrypt-volume/live/7gram.xyz/fullchain.pem exist?
         │                                        │
         │                        ┌───────────────┴────────────────┐
         │                        │ YES                            │ NO
         │                        ▼                                ▼
         │              ┌─────────────────────┐        ┌──────────────────────┐
         │              │ Check: Is cert valid│        │  Use fallback certs  │
         │              │  (not expired)?     │        │  (self-signed)       │
         │              └─────────────────────┘        │                      │
         │                        │                    │  Browser warning:    │
         │                ┌───────┴───────┐            │  "Not Secure"        │
         │                │ YES           │ NO         └──────────────────────┘
         │                ▼               ▼                      │
         │      ┌──────────────┐  ┌──────────────┐              │
         │      │ Use LE certs │  │ Use fallback │              │
         │      │ Production!  │  │ (expired)    │              │
         │      └──────────────┘  └──────────────┘              │
         │                │               │                     │
         │                └───────┬───────┘                     │
         │                        │                             │
         ▼                        ▼                             │
    Copy to /etc/nginx/ssl/    Copy to /etc/nginx/ssl/         │
         │                        │                             │
         ├────────────────────────┴─────────────────────────────┘
         │
         ▼
    Validate cert/key match
         │
         ├──── Check: Do modulus values match?
         │                        │
         │                ┌───────┴───────┐
         │                │ YES           │ NO
         │                ▼               ▼
         │         ┌─────────────┐  ┌─────────────┐
         │         │  Continue   │  │ FAIL & EXIT │
         │         │  startup    │  │  Container  │
         │         └─────────────┘  │  won't start│
         │                │         └─────────────┘
         │                ▼
         │         Test nginx config
         │                │
         │                ├──── nginx -t
         │                │         │
         │                │   ┌─────┴─────┐
         │                │   │ PASS      │ FAIL
         │                │   ▼           ▼
         │                │ Start    ┌─────────────┐
         │                │ nginx    │ FAIL & EXIT │
         │                ▼          └─────────────┘
         │         ┌─────────────┐
         │         │   Nginx     │
         │         │   Running   │
         │         │   & Serving │
         │         │   HTTPS     │
         │         └─────────────┘
         │
         ▼
    SUCCESS: Container running
```

## Certificate Renewal Flow (Scheduled Weekly)

```
Sunday 3am UTC
    │
    ▼
┌─────────────────────────┐
│ Scheduled workflow runs │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│ ssl-generate job        │
│                         │
│ Certbot checks:         │
│ • Current cert valid?   │
│ • Expires < 30 days?    │
└─────────────────────────┘
    │
    ├─────── Cert valid + expires > 30 days
    │        │
    │        ▼
    │   ┌────────────────┐
    │   │ Skip renewal   │
    │   │ Keep existing  │
    │   └────────────────┘
    │
    └─────── Cert expires < 30 days OR invalid
             │
             ▼
        ┌────────────────────┐
        │ Renew certificate  │
        │                    │
        │ • DNS challenge    │
        │ • Generate new     │
        │ • Update volume    │
        └────────────────────┘
             │
             ▼
        ┌────────────────────┐
        │ Deploy job         │
        │                    │
        │ • Restart nginx    │
        │ • Load new certs   │
        └────────────────────┘
             │
             ▼
        ✅ New certificate active
```

## Error Handling Flow

```
Nginx Container Start
         │
         ▼
    Try to load certs
         │
         ├──── Scenario 1: Certs missing from volume
         │     │
         │     ▼
         │  ┌──────────────────────────┐
         │  │ Fall back to self-signed │
         │  │ Log WARNING message      │
         │  │ Continue startup         │
         │  │ Service available ⚠️      │
         │  └──────────────────────────┘
         │
         ├──── Scenario 2: Cert/key mismatch
         │     │
         │     ▼
         │  ┌──────────────────────────┐
         │  │ Log ERROR message        │
         │  │ Container FAILS          │
         │  │ Service unavailable ❌    │
         │  └──────────────────────────┘
         │
         ├──── Scenario 3: Invalid nginx config
         │     │
         │     ▼
         │  ┌──────────────────────────┐
         │  │ nginx -t fails           │
         │  │ Log config errors        │
         │  │ Container FAILS          │
         │  │ Service unavailable ❌    │
         │  └──────────────────────────┘
         │
         └──── Scenario 4: All OK
               │
               ▼
            ┌──────────────────────────┐
            │ Nginx starts normally    │
            │ HTTPS with Let's Encrypt │
            │ Service available ✅      │
            └──────────────────────────┘
```

## Security Boundaries

```
┌──────────────────────────────────────────────────────────┐
│ GitHub Actions Runner                                    │
│ • Has SSH key                                            │
│ • Has Cloudflare API token                               │
│ • Generates certificates                                 │
│ • Writes to ssl-certs volume via SSH to server           │
└──────────────────────────────────────────────────────────┘
                    │
                    │ SSH over Tailscale (encrypted)
                    ▼
┌──────────────────────────────────────────────────────────┐
│ Freddy Server (Physical)                                 │
│                                                          │
│  ┌──────────────────────────────────────────┐           │
│  │ Docker Volume: ssl-certs                 │           │
│  │ • Isolated from host filesystem          │           │
│  │ • Only accessible via Docker API         │           │
│  │ • No direct host path exposure           │           │
│  └──────────────────────────────────────────┘           │
│                    │                                     │
│                    │ Read-only mount                     │
│                    ▼                                     │
│  ┌──────────────────────────────────────────┐           │
│  │ Nginx Container                          │           │
│  │ • Mounts volume read-only (:ro)          │           │
│  │ • Cannot modify source certificates      │           │
│  │ • Copies to internal /etc/nginx/ssl/     │           │
│  │ • Non-privileged user (nginx:nginx)      │           │
│  └──────────────────────────────────────────┘           │
│                    │                                     │
└────────────────────┼─────────────────────────────────────┘
                     │
                     │ Port 443 (HTTPS)
                     ▼
            ┌─────────────────┐
            │ Internet Users  │
            └─────────────────┘
```

## Comparison: Old vs New Approach

### ❌ Old Approach

```
Certbot (CI/CD)
    │
    ├─> Generate certs locally
    │
    ├─> Copy to server: /opt/ssl/7gram.xyz/
    │   (requires SSH, sudo, host filesystem)
    │
    └─> docker-compose.yml mounts:
        /opt/ssl/7gram.xyz:/etc/letsencrypt-volume
        (host path dependency)

Issues:
• Requires sudo for host filesystem
• Path must exist before docker-compose
• Not portable (hardcoded paths)
• Multiple copy operations
• Race conditions possible
```

### ✅ New Approach

```
Certbot (CI/CD)
    │
    └─> Generate directly into Docker volume
        (ssl-certs volume)

docker-compose.yml mounts:
    ssl-certs:/etc/letsencrypt-volume:ro
    (named volume, portable)

Benefits:
• No sudo required
• No host filesystem dependency
• Portable across environments
• Atomic operations
• Simpler CI/CD
```
