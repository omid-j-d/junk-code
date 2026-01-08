#!/bin/bash
# 🚀 Advanced SSL Certificate Installer with acme.sh 🚀
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${CYAN}🚀 Advanced SSL Installer using acme.sh${NC}\n"

# گرفتن دامنه
read -p "Enter domain name (e.g. example.com or *.example.com for wildcard): " domain
[[ -z "$domain" ]] && echo -e "${RED}✗ Domain cannot be empty!${NC}" && exit 1

# تشخیص wildcard
if [[ "$domain" == \*.** ]]; then
    is_wildcard=true
    echo -e "${YELLOW}⚠ Wildcard domain detected: $domain${NC}"
else
    is_wildcard=false
fi

# گرفتن ایمیل
read -p "Enter your email for Let's Encrypt: " email
[[ -z "$email" ]] && echo -e "${RED}✗ Email cannot be empty!${NC}" && exit 1

# انتخاب مسیر ذخیره
echo -e "\n${BOLD}Choose certificate storage location:${NC}"
echo "1) /root/c.crt & /root/p.key"
echo "2) /opt/marznode/<folder>/xray/certs/"
echo "3) Custom full paths"
echo "4) Wildcard via DNS (Cloudflare recommended)"
read -p "Enter choice (1/2/3/4): " choice

case $choice in
  1)
    key_path="/root/p.key"
    crt_path="/root/c.crt"
    mkdir -p "/root"
    ;;
  2)
    read -p "Enter folder name (inside /opt/marznode/): " folder
    [[ -z "$folder" ]] && echo -e "${RED}✗ Folder name required!${NC}" && exit 1
    base="/opt/marznode/$folder/xray/certs"
    mkdir -p "$base"
    key_path="$base/private.key"
    crt_path="$base/fullchain.pem"
    ;;
  3)
    echo "Enter FULL paths for certificate files:"
    read -p "Key file path (e.g. /etc/ssl/private/key.pem): " key_path
    read -p "Cert file path (e.g. /etc/ssl/certs/fullchain.pem): " crt_path
    [[ -z "$key_path" || -z "$crt_path" ]] && echo -e "${RED}✗ Paths cannot be empty!${NC}" && exit 1
    mkdir -p "$(dirname "$key_path")"
    mkdir -p "$(dirname "$crt_path")"
    ;;
  4)
    if [ "$is_wildcard" = false ]; then
        echo -e "${RED}✗ For wildcard option, domain must start with *. (e.g. *.example.com)${NC}"
        exit 1
    fi
    echo -e "${YELLOW}🌐 Wildcard mode: Using DNS challenge (Cloudflare)${NC}"
    read -p "Enter your Cloudflare API Token (with Zone.DNS Edit permission): " cf_token
    [[ -z "$cf_token" ]] && echo -e "${RED}✗ API Token required!${NC}" && exit 1
    export CF_Token="$cf_token"
    key_path="/root/.acme.sh/${domain}_ecc/fullchain.cer"  # ذخیره پیش‌فرض acme.sh
    crt_path="/root/.acme.sh/${domain}_ecc/${domain}.cer"
    echo -e "${YELLOW}Wildcard cert will be saved in acme.sh default folder.${NC}"
    echo -e "You can copy them manually later.\n"
    ;;
  *)
    echo -e "${RED}✗ Invalid choice!${NC}"
    exit 1
    ;;
esac

echo -e "\n${BOLD}Final paths:${NC}"
echo -e "🔑 Key:  $key_path"
echo -e "📜 Cert: $crt_path\n"

# نصب یا آپدیت acme.sh
if [ -f "$HOME/.acme.sh/acme.sh" ]; then
    echo -e "${YELLOW}🔄 Updating acme.sh...${NC}"
    ~/.acme.sh/acme.sh --upgrade
else
    echo -e "${CYAN}⬇️ Installing acme.sh...${NC}"
    curl https://get.acme.sh | sh -s email="$email"
fi

# تنظیمات
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# ثبت حساب
if ~/.acme.sh/acme.sh --account-email | grep -q "$email"; then
    echo -e "${GREEN}✔ Account already registered.${NC}"
else
    ~/.acme.sh/acme.sh --register-account -m "$email"
fi

# هشدار پورت 80 برای حالت معمولی
if [ "$choice" != "4" ]; then
    echo -e "${YELLOW}⚠ For standalone mode: Port 80 must be FREE (no nginx/apache running).${NC}"
    read -p "Press Enter to continue or Ctrl+C to cancel..."
fi

# صدور گواهی
echo -e "\n${CYAN}📜 Issuing certificate for $domain...${NC}"

if [ "$choice" = "4" ]; then
    # حالت Wildcard با DNS
    if ~/.acme.sh/acme.sh --issue -d "$domain" --dns dns_cf --force; then
        echo -e "${GREEN}✔ Wildcard certificate issued successfully!${NC}"
    else
        echo -e "${RED}✗ Failed. Check Cloudflare Token or Zone.${NC}"
        exit 1
    fi
else
    # حالت معمولی
    if ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --force; then
        echo -e "${GREEN}✔ Certificate issued successfully!${NC}"
    else
        echo -e "${RED}✗ Failed. Check port 80, DNS, or rate limits.${NC}"
        exit 1
    fi
fi

# نصب گواهی در مسیر دلخواه (به جز حالت wildcard که خودش ذخیره می‌کنه)
if [ "$choice" != "4" ]; then
    echo -e "${CYAN}💾 Installing certificate files...${NC}"
    ~/.acme.sh/acme.sh --installcert -d "$domain" \
        --key-file "$key_path" \
        --fullchain-file "$crt_path" \
        --ecc  # استفاده از ECC برای امنیت بیشتر
    echo -e "${GREEN}✔ Certificate files copied to custom paths!${NC}"
else
    echo -e "${GREEN}✔ Wildcard cert saved in ~/.acme.sh/${domain}_ecc/${NC}"
    ls -l "$HOME/.acme.sh/${domain}_ecc/"
fi

echo -e "\n${GREEN}✅ SSL installation complete!${NC}"
echo -e "🔑 Key:  $key_path"
echo -e "📜 Cert: $crt_path"
echo -e "\n${YELLOW}⚠ Remember to restart your service (Marzban, Xray, Nginx, etc.) to apply the new certificate.${NC}"esac

echo ""
echo "Selected paths:"
echo "Key: $key_path"
echo "Cert: $crt_path"
echo ""

# نصب acme.sh
curl https://get.acme.sh | sh

# تنظیم سرور و ثبت حساب
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --register-account -m "$email"

# صدور و نصب گواهی
~/.acme.sh/acme.sh --issue -d "$domain" --standalone
~/.acme.sh/acme.sh --installcert -d "$domain" \
  --key-file "$key_path" \
  --fullchain-file "$crt_path"

echo ""
echo "✅ SSL certificate installed successfully!"
echo "🔑 Key: $key_path"
echo "📜 Cert: $crt_path"
