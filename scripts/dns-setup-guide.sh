#!/bin/bash

# =============================================================================
# DNS Setup Guide for Authentik on FREDDY
# =============================================================================

echo "=========================================="
echo "DNS Configuration for Authentik SSO"
echo "=========================================="
echo ""

# Get Tailscale IP for FREDDY
echo "1. Get FREDDY's Tailscale IP:"
echo "   Run: tailscale ip -4"
echo ""
FREDDY_IP=$(tailscale ip -4 2>/dev/null || echo "Not available - install tailscale")
echo "   Current IP: $FREDDY_IP"
echo ""

echo "2. DNS Record to Create:"
echo "   ----------------------------------------"
echo "   Record Type: A or CNAME"
echo "   Hostname:    auth.7gram.xyz"
echo "   Value:       $FREDDY_IP (or freddy.7gram.xyz if using CNAME)"
echo "   TTL:         300"
echo "   ----------------------------------------"
echo ""

echo "3. Options for DNS Setup:"
echo ""
echo "   Option A: Tailscale MagicDNS (Recommended)"
echo "   - Add DNS record in Tailscale admin console"
echo "   - https://login.tailscale.com/admin/dns"
echo "   - Add split DNS for 7gram.xyz domain"
echo ""
echo "   Option B: Domain Registrar"
echo "   - Log into your domain provider (e.g., Cloudflare, GoDaddy)"
echo "   - Navigate to DNS settings"
echo "   - Add A record: auth -> $FREDDY_IP"
echo ""
echo "   Option C: Local /etc/hosts (Testing only)"
echo "   - Edit /etc/hosts on client machines"
echo "   - Add: $FREDDY_IP auth.7gram.xyz"
echo ""

echo "4. Verify DNS Resolution:"
echo "   After creating DNS record, test with:"
echo "   $ nslookup auth.7gram.xyz"
echo "   $ dig auth.7gram.xyz"
echo "   $ ping auth.7gram.xyz"
echo ""

echo "5. Test Nginx Configuration:"
echo "   $ docker compose exec nginx nginx -t"
echo "   $ docker compose restart nginx"
echo ""

echo "6. Access Authentik:"
echo "   After deployment (Task 2):"
echo "   https://auth.7gram.xyz"
echo ""

echo "=========================================="
echo "Additional DNS Records (Optional)"
echo "=========================================="
echo ""
echo "For better organization, consider adding:"
echo "   *.auth.7gram.xyz -> $FREDDY_IP (wildcard for outposts)"
echo ""
