#!/bin/bash

# Advanced SSL Certificate Installer using acme.sh
# Supports:
# - Domain SSL
# - Wildcard SSL via Cloudflare DNS
# - IPv4 SSL
# - Automatic renewal
# - Custom certificate/key paths
# - Remnawave Nginx certificate paths
#
# Renewal is handled automatically by acme.sh.
# Do NOT use --force here, otherwise every execution would issue a new certificate.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ACME="$HOME/.acme.sh/acme.sh"

clear

echo -e "${CYAN}${BOLD}"
echo "=============================================="
echo "        Advanced SSL Installer"
echo "             Powered by acme.sh"
echo "=============================================="
echo -e "${NC}"

# ============================================================
# Root check
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root.${NC}"
    exit 1
fi

# ============================================================
# Install / update acme.sh
# ============================================================

if [ -f "$ACME" ]; then
    echo -e "${YELLOW}🔄 Updating acme.sh...${NC}"
    "$ACME" --upgrade
else
    echo -e "${CYAN}⬇️ Installing acme.sh...${NC}"

    curl -fsSL https://get.acme.sh | sh -s email=

    if [ ! -f "$ACME" ]; then
        echo -e "${RED}✗ Failed to install acme.sh.${NC}"
        exit 1
    fi
fi

# Use Let's Encrypt
"$ACME" --set-default-ca --server letsencrypt

# ============================================================
# Email
# ============================================================

echo ""
read -rp "Enter your email for Let's Encrypt: " email

if [[ -z "$email" ]]; then
    echo -e "${RED}✗ Email cannot be empty.${NC}"
    exit 1
fi

# Register account if necessary
if "$ACME" --accountemail 2>/dev/null | grep -q "$email"; then
    echo -e "${GREEN}✔ ACME account already registered.${NC}"
else
    echo -e "${CYAN}📝 Registering ACME account...${NC}"
    "$ACME" --register-account -m "$email"
fi

# ============================================================
# Certificate type
# ============================================================

echo ""
echo -e "${BOLD}Choose certificate type:${NC}"
echo ""
echo "1) Domain"
echo "2) IPv4 address"
echo ""

read -rp "Enter choice (1/2): " cert_type

case "$cert_type" in

    1)
        cert_kind="domain"

        read -rp "Enter domain (example.com or *.example.com): " domain

        if [[ -z "$domain" ]]; then
            echo -e "${RED}✗ Domain cannot be empty.${NC}"
            exit 1
        fi

        ;;

    2)
        cert_kind="ip"

        read -rp "Enter IPv4 address: " domain

        if [[ -z "$domain" ]]; then
            echo -e "${RED}✗ IP address cannot be empty.${NC}"
            exit 1
        fi

        # Basic IPv4 validation
        if ! [[ "$domain" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo -e "${RED}✗ Invalid IPv4 address.${NC}"
            exit 1
        fi

        ;;

    *)
        echo -e "${RED}✗ Invalid choice.${NC}"
        exit 1
        ;;

esac

# ============================================================
# Wildcard detection
# ============================================================

is_wildcard=false

if [[ "$cert_kind" == "domain" && "$domain" == \*.* ]]; then
    is_wildcard=true
fi

# ============================================================
# Certificate storage
# ============================================================

echo ""
echo -e "${BOLD}Choose certificate storage location:${NC}"
echo ""
echo "1) /root/c.crt & /root/p.key"
echo "2) /opt/marznode/<folder>/xray/certs/"
echo "3) /opt/remnawave/nginx/<filename>.pem & <filename>.key"
echo "4) Custom full paths"
echo ""

read -rp "Enter choice (1/2/3/4): " storage_choice

case "$storage_choice" in

    1)

        key_path="/root/p.key"
        crt_path="/root/c.crt"

        mkdir -p "/root"

        ;;

    2)

        read -rp "Enter folder name (inside /opt/marznode/): " folder

        if [[ -z "$folder" ]]; then
            echo -e "${RED}✗ Folder name cannot be empty.${NC}"
            exit 1
        fi

        base="/opt/marznode/$folder/xray/certs"

        mkdir -p "$base"

        key_path="$base/private.key"
        crt_path="$base/fullchain.pem"

        ;;

    3)

        mkdir -p "/opt/remnawave/nginx"

        echo ""
        read -rp "Enter certificate filename (without extension): " remnawave_name

        if [[ -z "$remnawave_name" ]]; then
            echo -e "${RED}✗ Filename cannot be empty.${NC}"
            exit 1
        fi

        # Prevent path traversal
        if [[ "$remnawave_name" == */* || "$remnawave_name" == *..* ]]; then
            echo -e "${RED}✗ Invalid filename.${NC}"
            exit 1
        fi

        crt_path="/opt/remnawave/nginx/${remnawave_name}.pem"
        key_path="/opt/remnawave/nginx/${remnawave_name}.key"

        ;;

    4)

        echo ""
        echo "Enter FULL paths for certificate files."
        echo ""

        read -rp "Certificate path (.pem/.crt): " crt_path
        read -rp "Private key path (.key): " key_path

        if [[ -z "$crt_path" || -z "$key_path" ]]; then
            echo -e "${RED}✗ Paths cannot be empty.${NC}"
            exit 1
        fi

        mkdir -p "$(dirname "$crt_path")"
        mkdir -p "$(dirname "$key_path")"

        ;;

    *)

        echo -e "${RED}✗ Invalid storage choice.${NC}"
        exit 1

        ;;

esac

# ============================================================
# Display configuration
# ============================================================

echo ""
echo -e "${BOLD}==============================================${NC}"
echo -e "${BOLD}Certificate configuration${NC}"
echo -e "${BOLD}==============================================${NC}"

echo -e "Target : ${CYAN}$domain${NC}"
echo -e "Type   : ${CYAN}$cert_kind${NC}"

if [ "$is_wildcard" = true ]; then
    echo -e "Mode   : ${CYAN}Wildcard / Cloudflare DNS${NC}"
else
    echo -e "Mode   : ${CYAN}Standalone HTTP-01${NC}"
fi

echo -e "Cert   : ${CYAN}$crt_path${NC}"
echo -e "Key    : ${CYAN}$key_path${NC}"

echo ""

# ============================================================
# Prepare directories
# ============================================================

mkdir -p "$(dirname "$crt_path")"
mkdir -p "$(dirname "$key_path")"

chmod 700 "$(dirname "$key_path")"

# ============================================================
# Cloudflare / Wildcard
# ============================================================

if [ "$is_wildcard" = true ]; then

    echo ""
    echo -e "${YELLOW}🌐 Wildcard certificate detected.${NC}"
    echo ""
    echo "Cloudflare DNS API Token is required."
    echo "Required permission:"
    echo "Zone -> DNS -> Edit"
    echo ""

    read -rsp "Enter Cloudflare API Token: " cf_token
    echo ""

    if [[ -z "$cf_token" ]]; then
        echo -e "${RED}✗ Cloudflare API Token cannot be empty.${NC}"
        exit 1
    fi

    export CF_Token="$cf_token"

fi

# ============================================================
# Port 80 check
# ============================================================

if [ "$is_wildcard" = false ]; then

    echo ""
    echo -e "${YELLOW}⚠ Standalone HTTP validation requires TCP port 80.${NC}"
    echo ""

    if command -v ss >/dev/null 2>&1; then

        if ss -ltnH '( sport = :80 )' | grep -q .; then
            echo -e "${RED}✗ Port 80 is currently in use.${NC}"
            echo ""
            ss -ltnp '( sport = :80 )' || true
            echo ""
            echo "Stop the service using port 80 and run the script again."
            exit 1
        fi

    fi

fi

# ============================================================
# Issue certificate
# ============================================================

echo ""
echo -e "${CYAN}${BOLD}📜 Issuing certificate...${NC}"
echo ""

if [ "$is_wildcard" = true ]; then

    # --------------------------------------------------------
    # Wildcard / Cloudflare DNS
    # --------------------------------------------------------

    echo -e "${BLUE}Using Cloudflare DNS challenge...${NC}"

    "$ACME" --issue \
        -d "$domain" \
        --dns dns_cf \
        --keylength ec-256

elif [ "$cert_kind" = "ip" ]; then

    # --------------------------------------------------------
    # IPv4 certificate
    #
    # Let's Encrypt IP certificates currently use the
    # shortlived certificate profile.
    # --------------------------------------------------------

    echo -e "${BLUE}Using Let's Encrypt IP certificate profile...${NC}"

    "$ACME" --issue \
        -d "$domain" \
        --standalone \
        --certificate-profile shortlived \
        --days 6 \
        --keylength ec-256

else

    # --------------------------------------------------------
    # Normal domain
    # --------------------------------------------------------

    echo -e "${BLUE}Using standalone HTTP-01 challenge...${NC}"

    "$ACME" --issue \
        -d "$domain" \
        --standalone \
        --keylength ec-256

fi

# ============================================================
# Install / deploy certificate
#
# IMPORTANT:
# acme.sh stores these paths in the certificate configuration.
# When automatic renewal happens, the renewed certificate is
# installed into these same paths.
# ============================================================

echo ""
echo -e "${CYAN}💾 Installing certificate to target paths...${NC}"
echo ""

"$ACME" --install-cert \
    -d "$domain" \
    --ecc \
    --key-file "$key_path" \
    --fullchain-file "$crt_path"

# ============================================================
# Permissions
# ============================================================

chmod 600 "$key_path"
chmod 644 "$crt_path"

# ============================================================
# Verify files
# ============================================================

if [ ! -s "$key_path" ]; then
    echo -e "${RED}✗ Private key was not installed correctly.${NC}"
    exit 1
fi

if [ ! -s "$crt_path" ]; then
    echo -e "${RED}✗ Certificate was not installed correctly.${NC}"
    exit 1
fi

# ============================================================
# Renewal information
# ============================================================

echo ""
echo -e "${GREEN}${BOLD}==============================================${NC}"
echo -e "${GREEN}${BOLD}           SSL installation complete${NC}"
echo -e "${GREEN}${BOLD}==============================================${NC}"

echo ""
echo -e "🔐 Certificate : ${CYAN}$domain${NC}"
echo -e "📜 Certificate : ${CYAN}$crt_path${NC}"
echo -e "🔑 Private key : ${CYAN}$key_path${NC}"

echo ""
echo -e "${GREEN}✔ Certificate installed successfully.${NC}"
echo -e "${GREEN}✔ Automatic renewal is managed by acme.sh.${NC}"

# ============================================================
# Show renewal configuration
# ============================================================

echo ""

if "$ACME" --list | grep -Fq "$domain"; then
    echo -e "${GREEN}✔ Certificate is registered in acme.sh.${NC}"
else
    echo -e "${YELLOW}⚠ Certificate was installed, but could not be found in acme.sh list.${NC}"
fi

echo ""
echo -e "${YELLOW}ℹ Renewal command:${NC}"
echo ""
echo "  $ACME --renew -d \"$domain\""

echo ""
echo -e "${YELLOW}ℹ acme.sh automatic renewal is enabled by its scheduled task.${NC}"
echo ""

echo -e "${BOLD}Files:${NC}"
echo "  Certificate: $crt_path"
echo "  Private key: $key_path"

echo ""
echo -e "${GREEN}Done.${NC}"
