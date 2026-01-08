#!/bin/bash

# 🚀 Server Auto Setup Script
set -e

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root"
  exit 1
fi

echo "==============================="
echo " Server Auto Setup Script"
echo "==============================="

# 🕒 تنظیم ساعت و منطقه زمانی
echo ""
echo "🔍 Detecting server timezone from IP..."
TIMEZONE=$(curl -s https://ipapi.co/timezone || true)

if [ -n "$TIMEZONE" ]; then
  echo "🌍 Setting timezone to $TIMEZONE"
  timedatectl set-timezone "$TIMEZONE"
else
  echo "⚠️  Could not detect timezone automatically. Using UTC."
  timedatectl set-timezone UTC
fi

timedatectl status | grep "Time zone"

# 💡 فعال‌سازی BBR
echo ""
echo "⚙️ Enabling TCP BBR..."
modprobe tcp_bbr || true

if ! grep -q "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
  echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

cat <<EOF >/etc/sysctl.d/99-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl --system
echo "✅ BBR enabled successfully!"
sysctl net.ipv4.tcp_congestion_control

# 🌐 غیرفعال‌سازی IPv6 (اختیاری)
echo ""
read -p "Do you want to disable IPv6? (y/n): " disable_ipv6

if [[ "$disable_ipv6" =~ ^[Yy]$ ]]; then
  echo "Disabling IPv6..."
  cat <<EOF >/etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
  sysctl --system
  echo "✅ IPv6 disabled."
else
  echo "Skipping IPv6 disable."
fi

# 📦 آپدیت و نصب پکیج‌ها
echo ""
echo "🔄 Updating and upgrading system..."
apt update -y
apt upgrade -y

echo ""
echo "📦 Installing useful packages..."
apt install -y \
  git sudo curl socat vnstat nload speedtest-cli snapd \
  lsof unzip zip htop mtr btop ufw p7zip-full \
  ca-certificates gnupg screen

# 🐳 نصب Docker (اختیاری - روش رسمی)
echo ""
read -p "Do you want to install Docker? (y/n): " install_docker

if [[ "$install_docker" =~ ^[Yy]$ ]]; then
  echo "🐳 Installing Docker using official script..."
  curl -fsSL https://get.docker.com | sh

  systemctl enable docker
  systemctl start docker

  # اضافه کردن یوزر اجراکننده اسکریپت به گروه docker
  if [ -n "$SUDO_USER" ]; then
    usermod -aG docker "$SUDO_USER"
    echo "👤 User '$SUDO_USER' added to docker group (logout required)"
  fi

  echo "✅ Docker installed successfully!"
  docker --version
  docker compose version
else
  echo "Skipping Docker installation."
fi

# 🧹 پاکسازی نهایی
echo ""
echo "🧹 Cleaning up..."
apt autoremove -y
apt clean

# 📊 خلاصه نهایی
echo ""
echo "========================================"
echo "✅ Setup complete!"
echo "----------------------------------------"
echo "🕒 Timezone: $(timedatectl | grep 'Time zone')"
echo "⚙️  BBR: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
echo "🌐 IPv6: $(sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk '{print $3}') (1 = disabled)"
if command -v docker >/dev/null 2>&1; then
  echo "🐳 Docker: Installed"
else
  echo "🐳 Docker: Not installed"
fi
echo "----------------------------------------"
echo "🎉 Done!"
