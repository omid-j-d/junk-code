#!/bin/bash
# ============================================
#   Iran Firewall Script by امید & ChatGPT 🔒
#   هدف: فقط IP های ایران + چند IP مجاز خارجی
#   پشتیبانی: Debian / Ubuntu / CentOS
# ============================================

# 🧩 بررسی دسترسی root
	if [ "$EUID" -ne 0 ]; then
  echo "	❌ لطفاً با دسترسی root اجرا کن (sudo bash $0)"
  exit 1
fi

echo "🚀 شروع تنظیم فایروال..."

# 🧱 نصب ابزارهای لازم
#apt update -y >/dev/null 2>&1
apt install -y iptables ipset xtables-addons-common curl iptables-persistent

# 🗑️ پاک کردن تنظیمات قبلی
iptables -F
iptables -X
ipset destroy iran 2>/dev/null
ipset destroy whitelist 2>/dev/null

# 🌍 ساخت مجموعه IP ایران
echo "📦 دریافت لیست IP های ایران..."
ipset create iran hash:net
curl -s https://raw.githubusercontent.com/omid-j-d/iran_ip_list/refs/heads/main/Iplist.txt | while read range; do
  ipset add iran $range
done
echo "✅ لیست IPهای ایران بارگذاری شد."

# 🌐 ساخت whitelist
ipset create whitelist hash:ip

echo ""
echo "💡 حالا IPهای خارجی مجاز (whitelist) رو وارد کن."
echo "   وقتی تموم شد فقط Enter خالی بزن تا بره مرحله بعد."
while true; do
  read -p "➕ IP خارجی مجاز: " IP
  [ -z "$IP" ] && break
  ipset add whitelist $IP
  echo "✅ $IP اضافه شد."
done

# 🔥 تنظیم قوانین iptables
echo ""
echo "🛡️ در حال اعمال قوانین فایروال..."

# loopback
iptables -A INPUT -i lo -j ACCEPT

# ارتباطات موجود
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# whitelist
iptables -A INPUT -m set --match-set whitelist src -j ACCEPT

# ایران
iptables -A INPUT -m set --match-set iran src -j ACCEPT

# بقیه بلاک
iptables -A INPUT -j DROP

# ذخیره برای بوت بعدی
netfilter-persistent save >/dev/null 2>&1
systemctl enable netfilter-persistent >/dev/null 2>&1

echo ""
echo "✅ فایروال با موفقیت فعال شد."
echo "📜 فقط IPهای ایران و whitelist می‌تونن وصل شن."
echo "🚫 سایر IPها حتی ping هم ندارن."
echo ""
echo "برای بررسی وضعیت فعلی:"
echo "  iptables -L -v"
echo "  ipset list iran | head"
echo ""
echo "برای افزودن IP جدید به whitelist:"
echo "  sudo ipset add whitelist <IP>"
sudo ipset add whitelist 180.149.44.43
sudo ipset add whitelist 178.162.245.27
sudo ipset add whitelist 51.75.23.11
sudo ipset add whitelist 95.211.45.71
sudo ipset add whitelist 173.234.79.126
sudo ipset add whitelist 46.62.157.168
sudo ipset add whitelist 92.223.2.130
sudo ipset add whitelist 193.31.117.254
sudo ipset add whitelist 95.217.20.82
