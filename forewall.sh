#!/bin/bash
# 🧩 Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash $0)"
  exit 1
fi

echo "🚀 Starting firewall setup..."

# 🧱 Install required tools
#apt update -y >/dev/null 2>&1
apt install -y iptables ipset xtables-addons-common curl iptables-persistent

# 🗑️ Clear previous settings
iptables -F
iptables -X
ipset destroy iran 2>/dev/null
ipset destroy whitelist 2>/dev/null

# Local IP list file (default ./Iplist.txt)
IP_FILE="${1:-./ir_ips.txt}"

# 🌍 Create Iran IP set
echo "📦 Loading Iran IP list from: $IP_FILE ..."
if [ ! -f "$IP_FILE" ]; then
  echo "❌ IP file not found: $IP_FILE"
  echo "Please create the file and put one IP range per line."
  exit 1
fi

ipset create iran hash:net
while read range; do
  [ -z "$range" ] && continue
  case "$range" in \#*) continue ;; esac
  ipset add iran $range
done < "$IP_FILE"
echo "✅ Iran IP list loaded."

# 🌐 Create whitelist
ipset create whitelist hash:ip

echo ""
echo "💡 Now enter allowed foreign IPs (whitelist)."
echo "   Press Enter on empty input when finished."
while true; do
  read -p "➕ Allowed external IP: " IP
  [ -z "$IP" ] && break
  ipset add whitelist $IP
  echo "✅ $IP added."
done

# 🔥 Apply iptables rules
echo ""
echo "🛡️ Applying firewall rules..."

# loopback
iptables -A INPUT -i lo -j ACCEPT

# established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# whitelist
iptables -A INPUT -m set --match-set whitelist src -j ACCEPT

# Iran
iptables -A INPUT -m set --match-set iran src -j ACCEPT

# block others
iptables -A INPUT -j DROP

# Save for next boot
netfilter-persistent save >/dev/null 2>&1
systemctl enable netfilter-persistent >/dev/null 2>&1

echo ""
echo "✅ Firewall successfully activated."
echo "📜 Only Iran IPs and whitelist IPs can connect."
echo "🚫 All other IPs (even ping) are blocked."
echo ""
echo "To check current status:"
echo "  iptables -L -v"
echo "  ipset list iran | head"
echo ""
echo "To add a new IP to whitelist:"
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
