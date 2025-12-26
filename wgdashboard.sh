#!/bin/bash
set -e

# 🎨 Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}🧰 Installing WGDashboard...${RESET}"

# ===============================
# 1️⃣ نصب پیش‌نیازها
# ===============================
apt update -y
apt install -y iptables wireguard-tools net-tools git unzip

# ===============================
# 2️⃣ کلون repo و نصب
# ===============================
WG_DIR="/opt/WGDashboard"

if [ -d "$WG_DIR" ]; then
    read -p "⚠️ $WG_DIR already exists. Delete it? (y/N): " DELETE
    if [[ "$DELETE" =~ ^[Yy]$ ]]; then
        rm -rf "$WG_DIR"
    fi
fi

git clone https://github.com/WGDashboard/WGDashboard.git "$WG_DIR"
chmod +x "$WG_DIR/src/wgd.sh"
cd "$WG_DIR/src"
./wgd.sh install

# ===============================
# 3️⃣ فعال‌سازی IP Forward
# ===============================
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

# ===============================
# 4️⃣ ساخت سرویس systemd
# ===============================
SERVICE_FILE="/etc/systemd/system/wg-dashboard.service"

mv "$WG_DIR/src/wg-dashboard.service" "$SERVICE_FILE"
chmod 664 "$SERVICE_FILE"
sed -i "s|<absolute_path_of_wgdashboard_src>|$WG_DIR/src|g" "$SERVICE_FILE"

systemctl daemon-reload
systemctl enable wg-dashboard
systemctl start wg-dashboard

echo -e "${GREEN}✅ WGDashboard installed and service started.${RESET}"

# ===============================
# 5️⃣ ساخت wrapper command
# ===============================
WRAPPER="/usr/local/bin/wg-dashboard"
cat > "$WRAPPER" <<EOF
#!/bin/bash
SERVICE="wg-dashboard"

if [ -z "\$1" ]; then
  echo "Usage: wg-dashboard [start|stop|restart|status|update]"
  exit 1
fi

case "\$1" in
  start|stop|restart|status)
    systemctl \$1 \$SERVICE
    ;;
  update)
    cd "$WG_DIR"
    git pull
    chmod +x src/wgd.sh
    src/wgd.sh install
    systemctl restart \$SERVICE
    ;;
  *)
    echo "Invalid command. Use start|stop|restart|status|update"
    ;;
esac
EOF

chmod +x "$WRAPPER"
echo -e "${GREEN}✅ Wrapper command created: wg-dashboard${RESET}"
echo "Usage examples:"
echo "  wg-dashboard start"
echo "  wg-dashboard stop"
echo "  wg-dashboard restart"
echo "  wg-dashboard status"
echo "  wg-dashboard update"
