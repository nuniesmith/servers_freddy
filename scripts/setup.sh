#!/bin/bash

# Setup script for a fresh install of Fedora Server 42 - Freddy Server
# This script handles Stage 1: updates, installations, and sets up a one-time systemd service for Stage 2 after reboot.
# Assumes .env is in the current directory with required secrets.

# Function to show usage
usage() {
    echo "Usage: $0 [--log]"
    echo "  --log    Pipe all output to a timestamped log file"
    echo "  --help   Show this help message"
    exit 1
}

# Parse command line arguments
ENABLE_LOGGING=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --log)
            ENABLE_LOGGING=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Setup logging if requested
if [ "$ENABLE_LOGGING" = true ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGFILE="freddy_setup_${TIMESTAMP}.log"
    echo "Logging enabled. Output will be saved to: $LOGFILE"
    echo "You can monitor progress with: tail -f $LOGFILE"
    
    # Redirect all output to both console and log file
    exec > >(tee -a "$LOGFILE")
    exec 2>&1
    
    echo "=== Freddy Setup Script Started at $(date) ==="
    echo "=== Command: $0 $* ==="
    echo ""
fi

# Source the .env file
if [ -f .env ]; then
    echo "Validating .env file syntax..."
    
    # Show line 20 specifically since that's where the error was reported
    echo "Checking .env file line 20:"
    sed -n '20p' .env | cat -n
    
    # Check for basic syntax errors in .env file
    if ! bash -n .env 2>/dev/null; then
        echo ""
        echo "Error: .env file has syntax errors. Common issues:"
        echo "  - Line starts with a number (variable names can't start with digits)"
        echo "  - Unquoted values with spaces or special characters"
        echo "  - Missing quotes around values with spaces/symbols"
        echo "  - Invalid variable names (must start with letter/underscore)"
        echo ""
        echo "Full bash syntax check output:"
        bash -n .env
        echo ""
        echo "Please fix the .env file and run the script again."
        exit 1
    fi
    
    echo "Syntax validation passed. Sourcing .env file..."
    source .env
    echo "Successfully sourced .env file"
else
    echo "Error: .env file not found in current directory. Please create it with the required variables."
    exit 1
fi

# Set hostname (default to freddy if not specified in .env)
HOSTNAME=${HOSTNAME:-freddy}
echo "Setting hostname to: $HOSTNAME"
sudo hostnamectl set-hostname "$HOSTNAME" || { echo "Failed to set hostname"; exit 1; }

# Copy .env to /opt for Stage 2 to access post-reboot (more persistent than /tmp)
echo "Copying .env file to /opt for Stage 2..."
sudo mkdir -p /opt/freddy-setup
sudo cp .env /opt/freddy-setup/.env || { echo "Failed to copy .env file"; exit 1; }

# Cache sudo credentials upfront
echo "Caching sudo credentials..."
sudo -v || { echo "Failed to cache sudo credentials"; exit 1; }

# Stage 1: Update the system
echo "Starting system update..."
sudo dnf update -y || { echo "System update failed"; exit 1; }

# Install jq for JSON parsing
echo "Installing jq for JSON parsing..."
sudo dnf install jq -y || { echo "Failed to install jq"; exit 1; }

# Install Tailscale
echo "Installing Tailscale..."
# Add Tailscale repository
curl -fsSL https://pkgs.tailscale.com/stable/fedora/repo.gpg | sudo tee /etc/pki/rpm-gpg/tailscale.asc >/dev/null || { echo "Failed to add Tailscale GPG key"; exit 1; }
curl -fsSL https://pkgs.tailscale.com/stable/fedora/tailscale.repo | sudo tee /etc/yum.repos.d/tailscale.repo || { echo "Failed to add Tailscale repo"; exit 1; }
sudo dnf install tailscale -y || { echo "Failed to install Tailscale"; exit 1; }
sudo systemctl enable --now tailscaled || { echo "Failed to enable Tailscale service"; exit 1; }

# Install Netdata with claim
echo "Installing Netdata..."
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh || { echo "Failed to download Netdata installer"; exit 1; }
sh /tmp/netdata-kickstart.sh --nightly-channel --claim-token "${NETDATA_CLAIM_TOKEN}" --claim-rooms "${NETDATA_CLAIM_ROOMS}" --claim-url "${NETDATA_CLAIM_URL}" || { echo "Netdata installation failed"; exit 1; }

# Install Docker Engine
echo "Removing old Docker packages..."
sudo dnf remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine -y || echo "No old Docker packages to remove"

echo "Installing Docker prerequisites..."
sudo dnf install dnf-plugins-core -y || { echo "Failed to install dnf-plugins-core"; exit 1; }

echo "Adding Docker repository..."
# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/fedora/gpg | sudo tee /etc/pki/rpm-gpg/docker-ce.asc >/dev/null || { echo "Failed to add Docker GPG key"; exit 1; }
# Add Docker repository manually
sudo tee /etc/yum.repos.d/docker-ce.repo > /dev/null <<EOF
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://download.docker.com/linux/fedora/\$releasever/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/docker-ce.asc
EOF

echo "Installing Docker..."
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y || { echo "Failed to install Docker"; exit 1; }

echo "Enabling Docker service..."
sudo systemctl enable --now docker || { echo "Failed to enable Docker service"; exit 1; }

# Add user to docker group
echo "Adding user to docker group..."
sudo groupadd docker || true
sudo usermod -aG docker "${USER}" || { echo "Failed to add user to docker group"; exit 1; }

# Configure Docker to not manage iptables (let firewalld handle)
echo "Configuring Docker daemon..."
echo '{"iptables": false}' | sudo tee /etc/docker/daemon.json || { echo "Failed to configure Docker daemon"; exit 1; }

echo "Restarting Docker service..."
sudo systemctl restart docker || { echo "Failed to restart Docker service"; exit 1; }

# Create Stage 2 script (it will source /opt/freddy-setup/.env)
echo "Creating Stage 2 script..."
cat << 'EOF' | sudo tee /opt/freddy-setup/stage2.sh
#!/bin/bash

# Add logging for Stage 2
exec > >(tee -a /var/log/freddy-setup-stage2.log)
exec 2>&1

echo "=== Freddy Setup Stage 2 Started at $(date) ==="

# Source the .env file from /opt/freddy-setup
if [ -f /opt/freddy-setup/.env ]; then
    source /opt/freddy-setup/.env
    echo "Successfully sourced .env file from /opt/freddy-setup"
else
    echo "Error: /opt/freddy-setup/.env file not found. Stage 2 cannot proceed."
    exit 1
fi

# Set hostname (default to freddy if not specified in .env)
HOSTNAME=${HOSTNAME:-freddy}
echo "Using hostname: $HOSTNAME"

# Get Tailscale API access token
echo "Getting Tailscale API access token..."
ACCESS_TOKEN=$(curl -s -d "client_id=${TAILSCALE_CLIENT_ID}" \
                    -d "client_secret=${TAILSCALE_CLIENT_SECRET}" \
                    -d "grant_type=client_credentials" \
                    https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "Error: Failed to get Tailscale access token"
    exit 1
fi

echo "Successfully obtained Tailscale access token"

# Generate a one-time auth key
echo "Generating Tailscale auth key..."
AUTH_KEY=$(curl -s -X POST \
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                -H "Content-Type: application/json" \
                -d '{
                      "capabilities": {
                        "devices": {
                          "create": {
                            "reusable": false,
                            "ephemeral": false,
                            "preauthorized": true
                          }
                        }
                      },
                      "expirySeconds": 3600
                    }' \
                https://api.tailscale.com/api/v2/tailnet/-/keys | jq -r .key)

if [ -z "$AUTH_KEY" ] || [ "$AUTH_KEY" = "null" ]; then
    echo "Error: Failed to generate Tailscale auth key"
    exit 1
fi

echo "Successfully generated Tailscale auth key"

# Authenticate Tailscale
echo "Authenticating with Tailscale..."
sudo tailscale up --authkey "${AUTH_KEY}" --hostname "${HOSTNAME}" --accept-routes --advertise-exit-node || {
    echo "Error: Failed to authenticate with Tailscale"
    exit 1
}

# Setup basic firewall rules (allow SSH, reload firewalld)
echo "Configuring firewall..."
sudo firewall-cmd --permanent --add-service=ssh || echo "Warning: Failed to add SSH service to firewall"
sudo firewall-cmd --reload || echo "Warning: Failed to reload firewall"

echo "=== Freddy Setup Stage 2 Complete at $(date) ==="
echo "Tailscale authentication completed successfully"

# Clean up the one-time service and files
echo "Cleaning up setup files..."
sudo systemctl disable setup-stage2.service
rm -rf /opt/freddy-setup
echo "Setup cleanup complete"
EOF

# Make Stage 2 script executable
echo "Making Stage 2 script executable..."
sudo chmod +x /opt/freddy-setup/stage2.sh || { echo "Failed to make Stage 2 script executable"; exit 1; }

# Create one-time systemd service for Stage 2
echo "Creating systemd service for Stage 2..."
cat << EOF | sudo tee /etc/systemd/system/setup-stage2.service
[Unit]
Description=Freddy Setup Stage 2 - Tailscale Configuration
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/freddy-setup/stage2.sh
RemainAfterExit=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable the service and reboot
echo "Enabling Stage 2 service..."
sudo systemctl enable setup-stage2.service || { echo "Failed to enable Stage 2 service"; exit 1; }

echo ""
echo "=== Stage 1 Setup Complete ==="
echo "The system will now reboot and run Stage 2 automatically."
echo "Stage 2 will configure Tailscale and complete the setup."
if [ "$ENABLE_LOGGING" = true ]; then
    echo "Setup log saved to: $LOGFILE"
fi
echo ""
echo "Rebooting in 5 seconds..."
sleep 5

sudo reboot