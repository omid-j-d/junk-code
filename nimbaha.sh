#!/bin/bash

# دریافت ورودی‌ها
read -p "Enter domain (e.g. example.com): " DOMAIN
read -p "Enter server IP (e.g. 1.2.3.4): " IP

# پاک کردن کانفیگ‌های قدیمی
echo "Cleaning old Nginx configs..."
rm -f /etc/nginx/sites-available/* 2>/dev/null
rm -f /etc/nginx/sites-enabled/* 2>/dev/null

# ساخت فایل جدید در conf.d
CONF_PATH="/etc/nginx/conf.d/nim.conf"
echo "Creating new config at $CONF_PATH"

cat > $CONF_PATH <<EOF
server {
    listen 443 ssl;
    server_name ${DOMAIN};
    ssl_certificate /root/c.crt;
    ssl_certificate_key /root/p.key;
    ssl_protocols TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    return 403;

    location /forbidden {
        return 403;
    }
}

server {
    listen 443 ssl;
    server_name ${IP};
    return 301 https://${DOMAIN};
}

server {
    listen 80 default_server;
    server_name ${DOMAIN};
    return 403;

    location /forbidden {
        return 403;
    }
}

server {
    listen 80;
    server_name ${IP};
    return 301 http://${DOMAIN};
}
EOF

# بررسی سینتکس و ری‌استارت nginx
echo "Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "Reloading Nginx..."
    systemctl restart nginx
    echo "✅ Nginx restarted successfully with new config."
else
    echo "❌ Nginx config test failed. Please check the syntax above."
fi
