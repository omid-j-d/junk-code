#!/bin/bash
# 🚀 PingTunnel Manager - Install & Control with 'pg' 🚀
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/pingtunnel"
BIN_NAME="pingtunnel"
SERVICE_NAME="pingtunnel.service"
SYMLINK="/usr/local/bin/pg"

# چک root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Please run as root (sudo)${NC}"
    exit 1
fi

# تابع نمایش راهنما
usage() {
    echo -e "${BOLD}PingTunnel Manager${NC}"
    echo -e "Usage: ${CYAN}pg${NC} <command>\n"
    echo "Commands:"
    echo "  start     → Start service"
    echo "  stop      → Stop service"
    echo "  restart   → Restart service"
    echo "  status    → Show status"
    echo "  enable    → Enable on boot"
    echo "  disable   → Disable on boot"
    echo "  reconfig  → Change key and reconfigure"
    echo -e "\nOr run without args to install/update."
    exit 1
}

# اگر آرگومان داشت → کنترل سرویس
if [ $# -gt 0 ]; then
    case "$1" in
        start)
            systemctl start "$SERVICE_NAME"
            echo -e "${GREEN}✔ Service started${NC}"
            ;;
        stop)
            systemctl stop "$SERVICE_NAME"
            echo -e "${GREEN}✔ Service stopped${NC}"
            ;;
        restart)
            systemctl restart "$SERVICE_NAME"
            echo -e "${GREEN}✔ Service restarted${NC}"
            ;;
        status)
            systemctl status "$SERVICE_NAME" --no-pager
            ;;
        enable)
            systemctl enable "$SERVICE_NAME"
            echo -e "${GREEN}✔ Auto-start enabled${NC}"
            ;;
        disable)
            systemctl disable "$SERVICE_NAME"
            echo -e "${GREEN}✔ Auto-start disabled${NC}"
            ;;
        reconfig)
            if ! systemctl is-active --quiet "$SERVICE_NAME"; then
                echo -e "${YELLOW}⚠ Service not running. Starting with new config...${NC}"
            fi
            echo -e "${CYAN}🔑 Enter new key:${NC}"
            read -r NEW_KEY
            sed -i "s/-key .*/-key $NEW_KEY/" /etc/systemd/system/$SERVICE_NAME
            systemctl daemon-reload
            systemctl restart "$SERVICE_NAME"
            echo -e "${GREEN}✔ Service reconfigured and restarted with new key!${NC}"
            ;;
        *)
            usage
            ;;
    esac
    exit 0
fi

# نصب یا آپدیت (بدون آرگومان)
clear
echo -e "${CYAN}🚀 PingTunnel Installer & Manager${NC}\n"

# اگر سرویس وجود داشت → فقط آپدیت باینری
if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
    echo -e "${YELLOW}⚠ PingTunnel already installed. Updating binary...${NC}"
else
    echo -e "${CYAN}📦 Installing prerequisites...${NC}"
    apt update -y && apt install -y wget unzip iputils-ping
fi

echo -e "${CYAN}📁 Preparing directory...${NC}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# دانلود فقط اگر فایل نباشه یا قدیمی باشه
if [ ! -f "$BIN_NAME" ]; then
    echo -e "${CYAN}⬇️ Downloading latest PingTunnel...${NC}"
    wget -O pingtunnel.zip https://github.com/esrrhs/pingtunnel/releases/latest/download/pingtunnel_linux_amd64.zip
    unzip -o pingtunnel.zip
    chmod +x "$BIN_NAME"
else
    echo -e "${GREEN}✔ Binary already exists. Skipping download.${NC}"
fi

# گرفتن کلید (فقط اگر سرویس جدید باشه)
if [ ! -f "/etc/systemd/system/$SERVICE_NAME" ]; then
    echo -e "${CYAN}🔑 Enter your PingTunnel key:${NC}"
    read -r PT_KEY
else
    echo -e "${YELLOW}⚠ Service exists. Keeping current key. Use 'pg reconfig' to change it.${NC}"
    PT_KEY=$(grep -- "-key" /etc/systemd/system/$SERVICE_NAME | awk '{print $NF}' || echo "")
fi

# ساخت سرویس
echo -e "${CYAN}🛠 Creating/updating systemd service...${NC}"
cat > /etc/systemd/system/$SERVICE_NAME <<EOF
[Unit]
Description=PingTunnel Server
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BIN_NAME -type server -key $PT_KEY
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# ریلود و فعال‌سازی
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1

# شروع سرویس اگر در حال اجرا نبود
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl start "$SERVICE_NAME"
    echo -e "${GREEN}✔ Service started${NC}"
else
    systemctl restart "$SERVICE_NAME"
    echo -e "${GREEN}✔ Service restarted with updated config${NC}"
fi

# ساخت دستور جهانی pg
if [ ! -L "$SYMLINK" ]; then
    ln -sf "$0" "$SYMLINK"
    echo -e "${GREEN}✔ Global command 'pg' created!${NC}"
else
    echo -e "${YELLOW}⚠ 'pg' command already exists${NC}"
fi

echo -e "\n${GREEN}✅ PingTunnel installed/updated successfully!${NC}"
echo -e "${BOLD}Now control it with:${NC} ${CYAN}pg${NC} start|stop|restart|status|enable|disable|reconfig"
echo -e "\n${BOLD}Current status:${NC}"
systemctl status "$SERVICE_NAME" --no-pager -lAfter=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BIN_NAME -type server -key $PT_KEY
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 فعال‌سازی سرویس..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

echo "✅ نصب با موفقیت انجام شد!"
echo "📌 وضعیت سرویس:"
systemctl status $SERVICE_NAME --no-pager
