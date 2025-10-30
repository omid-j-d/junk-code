#!/bin/bash

# 🚀 آماده‌سازی اولیه سرور

set -e

echo "==============================="
echo " Server Auto Setup Script"
echo "==============================="

# 🕒 تنظیم ساعت و منطقه زمانی بر اساس IP سرور
echo ""
echo "🔍 Detecting server timezone from IP..."
TIMEZONE=$(curl -s https://ipapi.co/timezone)
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

# 🌐 غیرفعال‌سازی IPv6 (با گزینه فعال‌سازی بعدی)
echo ""
echo "Do you want to disable IPv6? (y/n): "
read disable_ipv6
if [[ "$disable_ipv6" == "y" || "$disable_ipv6" == "Y" ]]; then
  echo "Disabling IPv6..."
  cat <<EOF >/etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
  sysctl --system
  echo "✅ IPv6 disabled. Run 'sudo rm /etc/sysctl.d/99-disable-ipv6.conf && sudo sysctl --system' to re-enable."
else
  echo "Skipping IPv6 disable."
fi

# 📦 آپدیت و نصب پکیج‌ها
echo ""
echo "🔄 Updating and upgrading system..."
apt update -y && apt upgrade -y

echo ""
echo "📦 Installing useful packages..."
apt install -y git sudo curl fastfetch socat vnstat nload speedtest-cli snapd lsof unzip zip htop mtr btop ufw p7zip-full

# 🧹 پاکسازی نهایی
echo ""
apt autoremove -y && apt clean

echo ""
echo "✅ Setup complete!"
echo "----------------------------------------"
echo "🕒 Timezone: $(timedatectl | grep 'Time zone')"
echo "⚙️  BBR: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
echo "🌐 IPv6: $(sysctl net.ipv6.conf.all.disable_ipv6 | awk '{print $3}') (1 = disabled)"
echo "----------------------------------------"
echo "Done 🎉"
