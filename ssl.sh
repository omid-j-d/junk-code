#!/bin/bash

# گرفتن دامنه و ایمیل
read -p "Enter domain name: " domain
read -p "Enter your email: " email

# انتخاب مسیر ذخیره‌سازی
echo ""
echo "Choose certificate storage option:"
echo "1) /root/c.crt & /root/p.key"
echo "2) /opt/marznode/<custom_path>/xray/certs/"
echo "3) Custom path"
read -p "Enter your choice (1/2/3): " choice

case $choice in
  1)
    key_path="/root/p.key"
    crt_path="/root/c.crt"
    ;;
  2)
    read -p "Enter custom folder name (the variable part inside /opt/marznode/...): " folder
    base="/opt/marznode/$folder/xray/certs"
    mkdir -p "$base"
    key_path="$base/private.key"
    crt_path="$base/fullchain.pem"
    ;;
  3)
    read -p "Enter full path for key file: " key_path
    read -p "Enter full path for certificate file: " crt_path
    mkdir -p "$(dirname "$key_path")"
    mkdir -p "$(dirname "$crt_path")"
    ;;
  *)
    echo "Invalid choice. Exiting..."
    exit 1
    ;;
esac

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
