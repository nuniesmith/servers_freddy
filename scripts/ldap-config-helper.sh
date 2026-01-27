#!/bin/bash
#
# Authentik LDAP Configuration Helper
#
# This script helps verify LDAP configuration and provides
# connection details for integrating applications.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_DN="dc=7gram,dc=xyz"
SERVICE_ACCOUNT_DN="cn=ldapservice,ou=users,${BASE_DN}"
LDAP_PORT=389
LDAPS_PORT=636

echo -e "${BLUE}=== Authentik LDAP Configuration Helper ===${NC}\n"

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}--- $1 ---${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
print_header "Checking Prerequisites"

if ! command_exists ldapsearch; then
    echo -e "${RED}✗ ldapsearch not found${NC}"
    echo "Install with: sudo apt install ldap-utils"
    exit 1
fi
echo -e "${GREEN}✓ ldap-utils installed${NC}"

if ! command_exists docker; then
    echo -e "${RED}✗ docker not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ docker installed${NC}"

# Check if Authentik containers are running
print_header "Checking Authentik Services"

if docker ps | grep -q "authentik-server"; then
    echo -e "${GREEN}✓ authentik-server is running${NC}"
else
    echo -e "${RED}✗ authentik-server is not running${NC}"
    echo "Start with: docker compose up -d authentik-server"
    exit 1
fi

if docker ps | grep -q "authentik-ldap" || docker ps | grep -q "ak-outpost-ldap"; then
    echo -e "${GREEN}✓ LDAP outpost is running${NC}"
else
    echo -e "${YELLOW}⚠ LDAP outpost not found${NC}"
    echo "You need to create an LDAP outpost in Authentik UI first"
    echo "See: services/authentik/LDAP-SETUP.md"
fi

# Check if LDAP ports are listening
print_header "Checking LDAP Ports"

if netstat -tuln 2>/dev/null | grep -q ":${LDAP_PORT}" || ss -tuln 2>/dev/null | grep -q ":${LDAP_PORT}"; then
    echo -e "${GREEN}✓ LDAP port ${LDAP_PORT} is listening${NC}"
else
    echo -e "${YELLOW}⚠ LDAP port ${LDAP_PORT} is not listening${NC}"
fi

if netstat -tuln 2>/dev/null | grep -q ":${LDAPS_PORT}" || ss -tuln 2>/dev/null | grep -q ":${LDAPS_PORT}"; then
    echo -e "${GREEN}✓ LDAPS port ${LDAPS_PORT} is listening${NC}"
else
    echo -e "${YELLOW}⚠ LDAPS port ${LDAPS_PORT} is not listening${NC}"
fi

# Prompt for service account password
print_header "LDAP Connection Test"

echo -e "\nTo test LDAP, we need the service account password."
echo -e "This is the password for: ${YELLOW}${SERVICE_ACCOUNT_DN}${NC}"
echo -e "\nPress Enter to skip testing, or enter password to test:"
read -s -p "Service account password: " SERVICE_PASSWORD
echo

if [ -n "$SERVICE_PASSWORD" ]; then
    echo -e "\nTesting LDAP connection..."
    
    # Test LDAP connection
    if ldapsearch -x -H "ldap://localhost:${LDAP_PORT}" \
        -D "$SERVICE_ACCOUNT_DN" \
        -w "$SERVICE_PASSWORD" \
        -b "$BASE_DN" \
        "(objectClass=user)" uid cn mail >/dev/null 2>&1; then
        echo -e "${GREEN}✓ LDAP connection successful${NC}"
        
        # Show users
        echo -e "\nFound users:"
        ldapsearch -x -H "ldap://localhost:${LDAP_PORT}" \
            -D "$SERVICE_ACCOUNT_DN" \
            -w "$SERVICE_PASSWORD" \
            -b "$BASE_DN" \
            "(objectClass=user)" uid cn mail 2>/dev/null | grep -E "^(uid|cn|mail):" | head -20
    else
        echo -e "${RED}✗ LDAP connection failed${NC}"
        echo "Check:"
        echo "  1. Service account exists in Authentik"
        echo "  2. Password is correct"
        echo "  3. LDAP outpost is running"
        echo "  4. LDAP provider is configured with base DN: $BASE_DN"
    fi
    
    # Test LDAPS connection if available
    if netstat -tuln 2>/dev/null | grep -q ":${LDAPS_PORT}" || ss -tuln 2>/dev/null | grep -q ":${LDAPS_PORT}"; then
        echo -e "\nTesting LDAPS connection..."
        if LDAPTLS_REQCERT=never ldapsearch -x -H "ldaps://localhost:${LDAPS_PORT}" \
            -D "$SERVICE_ACCOUNT_DN" \
            -w "$SERVICE_PASSWORD" \
            -b "$BASE_DN" \
            "(objectClass=user)" uid >/dev/null 2>&1; then
            echo -e "${GREEN}✓ LDAPS connection successful${NC}"
        else
            echo -e "${RED}✗ LDAPS connection failed${NC}"
        fi
    fi
fi

# Print configuration details
print_header "LDAP Configuration Details"

echo -e "\n${BLUE}For applications on FREDDY (same server):${NC}"
cat <<EOF

Server:              localhost
LDAP Port:           ${LDAP_PORT}
LDAPS Port:          ${LDAPS_PORT}
Base DN:             ${BASE_DN}
Bind DN:             ${SERVICE_ACCOUNT_DN}
Bind Password:       <service-account-password>
User DN:             ou=users,${BASE_DN}
Username Attribute:  uid
Email Attribute:     mail
Name Attribute:      cn
User Object Class:   user
User Filter:         (objectClass=user)

EOF

echo -e "${BLUE}For applications on SULLIVAN (remote server):${NC}"
cat <<EOF

Server:              freddy
LDAP Port:           ${LDAP_PORT}
LDAPS Port:          ${LDAPS_PORT} ${GREEN}(recommended for remote)${NC}
Base DN:             ${BASE_DN}
Bind DN:             ${SERVICE_ACCOUNT_DN}
Bind Password:       <service-account-password>
User DN:             ou=users,${BASE_DN}
Username Attribute:  uid
Email Attribute:     mail
Name Attribute:      cn
User Object Class:   user
User Filter:         (objectClass=user)

EOF

# Print testing commands
print_header "Testing Commands"

echo -e "\n${BLUE}Test LDAP from FREDDY:${NC}"
cat <<'EOF'

ldapsearch -x -H ldap://localhost:389 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(objectClass=user)"

EOF

echo -e "${BLUE}Test LDAPS from FREDDY:${NC}"
cat <<'EOF'

ldapsearch -x -H ldaps://localhost:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(objectClass=user)"

EOF

echo -e "${BLUE}Test LDAP from SULLIVAN:${NC}"
cat <<'EOF'

ldapsearch -x -H ldap://freddy:389 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(objectClass=user)"

EOF

echo -e "${BLUE}Test LDAPS from SULLIVAN (recommended):${NC}"
cat <<'EOF'

ldapsearch -x -H ldaps://freddy:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(objectClass=user)"

EOF

# Print next steps
print_header "Next Steps"

cat <<EOF

1. Create LDAP outpost in Authentik UI (if not done):
   ${YELLOW}Applications → Outposts → Create${NC}

2. Create LDAP provider in Authentik UI:
   ${YELLOW}Applications → Providers → Create → LDAP Provider${NC}
   - Base DN: ${BASE_DN}
   - Bind mode: Direct bind

3. Create LDAP application in Authentik UI:
   ${YELLOW}Applications → Applications → Create${NC}
   - Provider: Select your LDAP provider

4. Create service account in Authentik UI:
   ${YELLOW}Directory → Users → Create${NC}
   - Username: ldapservice
   - Type: Internal service account

5. Configure applications:
   - Emby: See sullivan/services/emby/LDAP-INTEGRATION.md
   - Jellyfin: See sullivan/services/jellyfin/LDAP-INTEGRATION.md
   - Nextcloud: See freddy/services/nextcloud/LDAP-INTEGRATION.md

6. Test authentication with a real user

For detailed instructions, see: ${YELLOW}services/authentik/LDAP-SETUP.md${NC}

EOF

echo -e "${GREEN}Configuration helper complete!${NC}\n"
