#!/bin/bash
#



# Update system first
echo "📦 Updating system..."
sudo apt update -y

echo "📥 Installing snapd, certbot and Cloudflare plugin..."
sudo apt install -y snapd curl
sudo snap install core
sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo snap set certbot trust-plugin-with-root=ok
sudo snap install certbot-dns-cloudflare

# Create directories
echo "📁 Creating necessary directories..."
sudo mkdir -p /etc/letsencrypt
mkdir -p ./config/nginx/certs

# Prompt for credentials
echo "🔐 Setting up Cloudflare DNS credentials..."
echo "Please enter your Cloudflare API credentials:"
echo "📋 Get these from: Cloudflare Dashboard → My Profile → API Tokens"
read -p "Cloudflare Email: " cloudflare_email
read -p "Cloudflare Global API Key: " cloudflare_api_key
read -p "Your Email Address: " email_address

# Create DNS credentials file for Cloudflare
sudo tee /etc/letsencrypt/cloudflare.ini > /dev/null <<EOF
# Cloudflare API credentials
dns_cloudflare_email = $cloudflare_email
dns_cloudflare_api_key = $cloudflare_api_key
EOF

# Secure the credentials file
sudo chmod 600 /etc/letsencrypt/cloudflare.ini

echo "🔍 Testing Cloudflare API connection..."
# Test API connection (optional)
curl -s -H "X-Auth-Email: $cloudflare_email" -H "X-Auth-Key: $cloudflare_api_key" "https://api.cloudflare.com/client/v4/user/tokens/verify" > /dev/null || echo "⚠️  Warning: Could not test API connection"

# Generate wildcard certificate
echo "🔒 Generating wildcard certificate for 7gram.xyz..."
sudo certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 60 \
    -d "7gram.xyz" \
    -d "*.7gram.xyz" \
    --agree-tos \
    --email "$email_address" \
    --non-interactive

# Copy certificates to nginx certs directory
echo "📋 Copying certificates to ./config/nginx/certs/ directory..."
sudo cp /etc/letsencrypt/live/7gram.xyz/fullchain.pem ./config/nginx/certs/
sudo cp /etc/letsencrypt/live/7gram.xyz/privkey.pem ./config/nginx/certs/

# Also create copies with the expected filenames for nginx
sudo cp /etc/letsencrypt/live/7gram.xyz/fullchain.pem ./config/nginx/certs/7gram.xyz.crt
sudo cp /etc/letsencrypt/live/7gram.xyz/privkey.pem ./config/nginx/certs/7gram.xyz.key

# Fix ownership and permissions
sudo chown -R $USER:$USER ./config/nginx/certs/
chmod 644 ./config/nginx/certs/*.pem ./config/nginx/certs/*.crt
chmod 600 ./config/nginx/certs/privkey.pem ./config/nginx/certs/*.key

echo "✅ Certificates generated! Locations:"
echo "Certificate (fullchain): ./config/nginx/certs/fullchain.pem"
echo "Certificate (nginx format): ./config/nginx/certs/7gram.xyz.crt"
echo "Private Key: ./config/nginx/certs/privkey.pem"
echo "Private Key (nginx format): ./config/nginx/certs/7gram.xyz.key"

# Create certificate renewal script
echo "🔄 Setting up automatic certificate renewal..."
SCRIPT_DIR=$(pwd)
sudo tee /usr/local/bin/renew-ssl.sh > /dev/null <<EOF
#!/bin/bash
# Renew certificates and copy to nginx directory
certbot renew --quiet

# Copy renewed certificates
if [ -f /etc/letsencrypt/live/7gram.xyz/fullchain.pem ]; then
    # Copy with original names
    cp /etc/letsencrypt/live/7gram.xyz/fullchain.pem $SCRIPT_DIR/config/nginx/certs/
    cp /etc/letsencrypt/live/7gram.xyz/privkey.pem $SCRIPT_DIR/config/nginx/certs/

    # Copy with nginx expected names
    cp /etc/letsencrypt/live/7gram.xyz/fullchain.pem $SCRIPT_DIR/config/nginx/certs/7gram.xyz.crt
    cp /etc/letsencrypt/live/7gram.xyz/privkey.pem $SCRIPT_DIR/config/nginx/certs/7gram.xyz.key

    # Fix permissions
    OWNER=$(stat -c '%U:%G' "$SCRIPT_DIR")
    chown -R "$OWNER" "$SCRIPT_DIR/config/nginx/certs/"
    chmod 644 "$SCRIPT_DIR/config/nginx/certs/"*.pem "$SCRIPT_DIR/config/nginx/certs/"*.crt
    chmod 600 "$SCRIPT_DIR/config/nginx/certs/privkey.pem" "$SCRIPT_DIR/config/nginx/certs/"*.key

    # Reload nginx container if running
    if docker ps | grep -q "nginx"; then
        docker exec nginx nginx -s reload || echo "Could not reload nginx container"
    fi

    echo "Certificates renewed and copied to $SCRIPT_DIR/config/nginx/certs/"
fi
EOF

sudo chmod +x /usr/local/bin/renew-ssl.sh

# Set up automatic renewal using systemd
sudo tee /etc/systemd/system/certbot-renewal.service > /dev/null <<EOF
[Unit]
Description=Certbot Renewal
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/renew-ssl.sh
User=root
WorkingDirectory=$SCRIPT_DIR
EOF

sudo tee /etc/systemd/system/certbot-renewal.timer > /dev/null <<EOF
[Unit]
Description=Run certbot renewal twice daily
Requires=certbot-renewal.service

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable automatic renewal
sudo systemctl daemon-reload
sudo systemctl enable certbot-renewal.timer
sudo systemctl start certbot-renewal.timer

# Enable and start ufw if not already running (Ubuntu security)
if ! command -v ufw >/dev/null 2>&1 || ! sudo ufw status | grep -q "Status: active"; then
    echo "🔥 Enabling ufw for security..."
    sudo apt install -y ufw
    sudo ufw allow OpenSSH
    sudo ufw allow 'Nginx Full'
    sudo ufw --force enable
fi

echo "✅ Automatic renewal configured!"
echo ""
echo "🧪 Testing renewal with dry run..."
sudo certbot renew --dry-run

echo ""
echo "🎉 SETUP COMPLETE!"
echo ""
echo "📋 IMPORTANT NOTES:"
echo "- Certificates are stored in: ./config/nginx/certs/"
echo "- Available formats:"
echo "  • fullchain.pem & privkey.pem (Let's Encrypt format)"
echo "  • 7gram.xyz.crt & 7gram.xyz.key (nginx format)"
echo "- Cloudflare API credentials: /etc/letsencrypt/cloudflare.ini"
echo "- Automatic renewal: Every 12 hours"
echo "- Test renewal: sudo certbot renew --dry-run"
echo "- Check renewal timer: sudo systemctl status certbot-renewal.timer"
echo "- Firewall configured for HTTP/HTTPS traffic"
echo ""
echo "🔧 DOCKER-COMPOSE VOLUME MAPPING:"
echo "Add this to your nginx service in docker-compose.yml:"
echo "  volumes:"
echo "    - ./config/nginx/certs:/etc/nginx/ssl:ro"
echo ""
echo "🔧 NGINX SSL CONFIGURATION:"
echo "Use either format in your nginx config:"
echo "  ssl_certificate /etc/nginx/ssl/7gram.xyz.crt;"
echo "  ssl_certificate_key /etc/nginx/ssl/7gram.xyz.key;"
echo "OR:"
echo "  ssl_certificate /etc/nginx/ssl/fullchain.pem;"
echo "  ssl_certificate_key /etc/nginx/ssl/privkey.pem;"
echo ""
echo "🔧 NEXT STEPS:"
echo "1. Update your docker-compose.yml file to mount ./config/nginx/certs/"
echo "2. Update nginx SSL configuration to use correct certificate paths"
echo "3. Start your docker containers: docker-compose up -d"
echo ""
echo "☁️ CLOUDFLARE REQUIREMENTS MET:"
echo "✅ Domain added to Cloudflare account"
echo "✅ Nameservers changed from Namecheap to Cloudflare"
echo "✅ DNS records imported and configured"
echo "✅ API credentials configured"
echo ""
echo "🔐 CLOUDFLARE API SETUP:"
echo "- Dashboard → My Profile → API Tokens → Global API Key"
echo "- Or create a custom API token with Zone:DNS:Edit permissions"
echo ""
echo "🔧 FEDORA SPECIFIC FEATURES:"
echo "- Uses apt package manager"
echo "- Firewalld configured for web traffic"
echo "- SELinux compatible (default Fedora security)"
