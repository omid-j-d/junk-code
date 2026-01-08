#!/bin/bash

set -e

# Check root
if [ "$EUID" -ne 0 ]; then
  echo "❌ لطفاً اسکریپت را با root اجرا کنید"
  exit 1
fi

echo "🔑 لطفاً کلید (Key) مورد نظر را وارد کنید:"
read -r PT_KEY

INSTALL_DIR="/opt/pingtunnel"
BIN_NAME="pingtunnel"
SERVICE_NAME="pingtunnel.service"

echo "📦 نصب پیش‌نیازها..."
apt update -y
apt install -y wget unzip iputils-ping

echo "📁 ساخت دایرکتوری نصب..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

echo "⬇️ دانلود آخرین نسخه pingtunnel..."
wget -O pingtunnel.zip https://github.com/esrrhs/pingtunnel/releases/latest/download/pingtunnel_linux_amd64.zip

echo "📂 استخراج فایل..."
unzip -o pingtunnel.zip
chmod +x $BIN_NAME

echo "🛠 ساخت سرویس systemd..."
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

echo "🔄 فعال‌سازی سرویس..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

echo "✅ نصب با موفقیت انجام شد!"
echo "📌 وضعیت سرویس:"
systemctl status $SERVICE_NAME --no-pager
