# 🏠 Freddy Server - Personal Services & Home Automation

Freddy is a self-hosted personal server running on a lightweight home server, providing photo management, cloud storage, home automation, and media services. All services are reverse-proxied through nginx with automated SSL certificate management via Let's Encrypt.

## 🚀 Services

| Service | Domain | Description |
|---------|--------|-------------|
| **Nginx** | `7gram.xyz` | Reverse proxy with SSL termination |
| **PhotoPrism** | `photo.7gram.xyz` | AI-powered photo management |
| **Nextcloud** | `nc.7gram.xyz` | Self-hosted cloud storage |
| **Home Assistant** | `home.7gram.xyz` | Home automation platform |
| **Audiobookshelf** | `audiobook.7gram.xyz` | Audiobook library management |

### Sullivan Services (Proxied)

Freddy also proxies to Sullivan server (media server) via Tailscale:
- Emby, Jellyfin, Plex (media streaming)
- Sonarr, Radarr, Lidarr (media automation)
- qBittorrent, Jackett (downloads)
- Calibre, Mealie, Wiki.js, and more

## 🔐 SSL Certificates

Freddy uses **Let's Encrypt** SSL certificates with **Cloudflare DNS-01 challenge** for wildcard domain coverage (`*.7gram.xyz`).

### Automated Certificate Management

- ✅ **Automatic generation** during CI/CD deployment
- ✅ **Auto-renewal** twice daily via systemd timer
- ✅ **Fallback mechanism** (self-signed certs if Let's Encrypt fails)
- ✅ **90-day validity** (auto-renewed at 60 days)

### Quick SSL Commands

```bash
# Check certificate status
./scripts/cert-manager.sh check

# Request new certificate
sudo ./scripts/cert-manager.sh request

# Upgrade from self-signed to Let's Encrypt
sudo ./scripts/cert-manager.sh upgrade

# Test renewal process
sudo ./scripts/cert-manager.sh test-renewal
```

**📖 See [SSL Setup Documentation](docs/SSL_SETUP.md) for detailed information**

## 🛠️ Quick Start

### Prerequisites

- Docker & Docker Compose
- Domain name (configured with Cloudflare)
- Tailscale (for remote access)
- Cloudflare API credentials

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/nuniesmith/servers_freddy.git ~/freddy
   cd ~/freddy
   ```

2. **Setup environment:**
   ```bash
   cp .env.example .env
   nano .env  # Configure your settings
   ```

3. **Generate SSL certificates:**
   ```bash
   sudo ./scripts/cert-manager.sh request
   ```

4. **Start services:**
   ```bash
   ./run.sh start
   ```

5. **Check health:**
   ```bash
   ./run.sh health
   ```

## 📋 Common Commands

```bash
# Start all services
./run.sh start

# Stop all services
./run.sh stop

# Restart services
./run.sh restart

# View logs
./run.sh logs [service]

# Check service status
./run.sh status

# Run health checks
./run.sh health

# Pull latest images
./run.sh pull

# Clean up unused resources
./run.sh clean
```

## 🤖 CI/CD Deployment

The project uses GitHub Actions for automated deployment:

1. **DNS Update** - Updates Cloudflare DNS records to point to Tailscale IP
2. **SSL Check** - Validates/generates Let's Encrypt certificates
3. **Deploy** - Pulls latest code and restarts services
4. **Health Check** - Verifies all services are running

### Required GitHub Secrets

```
CLOUDFLARE_EMAIL          # Cloudflare account email
CLOUDFLARE_API_KEY        # Cloudflare Global API Key
CERTBOT_EMAIL            # Email for Let's Encrypt notifications
FREDDY_TAILSCALE_IP      # Freddy server Tailscale IP
SULLIVAN_TAILSCALE_IP    # Sullivan server Tailscale IP
SSH_KEY                  # SSH private key for deployment
SSH_USER                 # SSH username
SSH_PORT                 # SSH port (default: 22)
TAILSCALE_OAUTH_CLIENT_ID
TAILSCALE_OAUTH_SECRET
```

**📖 See [Deployment Summary](docs/DEPLOYMENT_SUMMARY.md) for deployment details**

## 📁 Project Structure

```
servers_freddy/
├── .github/workflows/     # CI/CD pipelines
├── docker/               # Docker configurations
│   └── nginx/           # Nginx Dockerfile and entrypoint
├── services/            # Service configurations
│   └── nginx/          # Nginx configs
│       ├── nginx.conf
│       └── conf.d/     # Server block configs
├── scripts/            # Management scripts
│   ├── ci-ssl-setup.sh      # Automated SSL setup (CI/CD)
│   ├── cert-manager.sh      # Interactive SSL management
│   ├── backup.sh            # Backup script
│   └── setup-prod-server.sh # Server setup
├── docs/               # Documentation
│   ├── SSL_SETUP.md           # SSL certificate guide
│   └── DEPLOYMENT_SUMMARY.md  # Deployment details
├── docker-compose.yml  # Service definitions
├── run.sh             # Management wrapper script
└── README.md          # This file
```

## 🔒 Security

- **SSL/TLS:** All services use HTTPS with Let's Encrypt certificates
- **Firewall:** UFW configured to allow only necessary ports
- **Tailscale:** Secure mesh VPN for remote access
- **Docker:** Services isolated in containers
- **Automatic Updates:** Systemd timers for certificate renewal

## 📊 Monitoring

### Health Checks

```bash
# Check all services
./run.sh health

# Check specific service
docker logs [service_name]

# Nginx access logs
docker logs nginx | tail -100

# Certificate expiry
./scripts/cert-manager.sh info
```

### Renewal Timer

```bash
# Check renewal timer status
sudo systemctl status freddy-cert-renewal.timer

# View timer logs
sudo journalctl -u freddy-cert-renewal.service
```

## 🐛 Troubleshooting

### Issue: Services returning 500 errors

**Solution:**
```bash
# Check nginx logs
docker logs nginx

# Verify certificates
./scripts/cert-manager.sh check

# Restart services
./run.sh restart
```

### Issue: SSL certificate warnings

**Cause:** Using self-signed fallback certificates

**Solution:**
```bash
# Generate Let's Encrypt certificates
sudo ./scripts/cert-manager.sh upgrade

# Restart nginx
./run.sh restart nginx
```

### Issue: Cannot connect to services

**Check:**
```bash
# Verify DNS
dig 7gram.xyz
dig photo.7gram.xyz

# Check firewall
sudo ufw status

# Verify services are running
docker ps
```

**📖 See [SSL Setup Guide](docs/SSL_SETUP.md#troubleshooting) for more troubleshooting**

## 📚 Documentation

- **[SSL Setup Guide](docs/SSL_SETUP.md)** - Complete SSL certificate management documentation
- **[Deployment Summary](docs/DEPLOYMENT_SUMMARY.md)** - Recent changes and deployment guide
- **[Deployment Checklist](DEPLOYMENT_CHECKLIST.md)** - Pre/post deployment verification

## 🤝 Contributing

This is a personal server project, but feel free to:
- Report issues
- Suggest improvements
- Fork for your own use

## 📝 License

See [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Let's Encrypt** - Free SSL certificates
- **Cloudflare** - DNS and CDN services
- **Tailscale** - Secure mesh VPN
- **PhotoPrism** - AI-powered photo management
- **Nextcloud** - Self-hosted cloud platform
- **Home Assistant** - Home automation platform

---

**Maintained by:** Jordan / nuniesmith  
**Server:** Freddy (Home Server)  
**Domain:** 7gram.xyz  
**Last Updated:** January 2026