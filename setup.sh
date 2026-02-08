#!/bin/bash
# 🚀 Server Auto Setup Script - Beautiful English Edition 🚀
set -e

# Colors for beauty
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Please run this script as root${NC}"
    exit 1
fi

clear
echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║        🚀 Welcome to Server Auto Setup Script 🚀        ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"



# TCP Congestion Control ⚡
echo -e "${CYAN}🔧 Configuring TCP congestion control${NC}"
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control)
echo -e "Current algorithm: ${YELLOW}$CURRENT_CC${NC}"
echo -e "${BOLD}Options:${NC}"
echo "  1 = BBR 🚀 (Recommended - Better performance)"
echo "  2 = Cubic 🐢"
echo "  3 = Keep current"
read -p $'\n🔹 Your choice [1/2/3] (default: 1 - BBR): ' cc_choice
cc_choice=${cc_choice:-1}

case "$cc_choice" in
    1)
        echo -e "${GREEN}🚀 Enabling BBR...${NC}"
        modprobe tcp_bbr || true
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null || true
        cat <<EOF >/etc/sysctl.d/99-tcp-bbr.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        sysctl --system
        echo -e "${GREEN}✔ BBR enabled successfully!${NC}"
        ;;
    2)
        echo -e "${GREEN}🐢 Enabling Cubic...${NC}"
        cat <<EOF >/etc/sysctl.d/99-tcp-bbr.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = cubic
EOF
        sysctl --system
        echo -e "${GREEN}✔ Cubic enabled successfully!${NC}"
        ;;
    3|"")
        echo -e "${YELLOW}⚠ Keeping current: $CURRENT_CC${NC}"
        ;;
    *)
        echo -e "${YELLOW}⚠ Invalid choice! Falling back to BBR.${NC}"
        modprobe tcp_bbr || true
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null || true
        cat <<EOF >/etc/sysctl.d/99-tcp-bbr.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        sysctl --system
        echo -e "${GREEN}✔ BBR enabled (fallback).${NC}"
        ;;
esac

# IPv6 Management
echo -e "\n${CYAN}🔒 IPv6 settings${NC}"
read -p $'🔹 Disable IPv6? (y/n) [default: n]: ' disable_ipv6
disable_ipv6=${disable_ipv6:-n}

IPV6_CONF="/etc/sysctl.d/99-disable-ipv6.conf"

if [[ "$disable_ipv6" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}🔒 Disabling IPv6...${NC}"
    cat <<EOF > "$IPV6_CONF"
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl --system
    echo -e "${GREEN}✔ IPv6 disabled.${NC}"
else
    if [ -f "$IPV6_CONF" ]; then
        echo -e "${GREEN}🔓 Re-enabling IPv6...${NC}"
        rm -f "$IPV6_CONF"
        sysctl --system
        echo -e "${GREEN}✔ IPv6 enabled.${NC}"
    else
        echo -e "${YELLOW}⚠ IPv6 unchanged.${NC}"
    fi
fi

# Swap Management 💾
echo -e "\n${CYAN}💾 Managing swap space...${NC}"

CURRENT_SWAP=$(swapon --show=NAME,SIZE --noheadings | awk '{print $1}' | head -1 || true)

if [ -n "$CURRENT_SWAP" ]; then
    echo -e "${YELLOW}⚠ Existing swap found: $CURRENT_SWAP${NC}"
    echo "Disabling and removing..."
    swapoff "$CURRENT_SWAP" || true
    rm -f "$CURRENT_SWAP"
    sed -i '\|'"$CURRENT_SWAP"'|d' /etc/fstab
    echo -e "${GREEN}✔ Previous swap removed.${NC}"
else
    echo -e "${GREEN}✔ No existing swap found.${NC}"
fi

read -p $'🔹 Desired swap size in GB (e.g. 2, 4, 8) or 0 to skip [default: 0]: ' swap_gb
swap_gb=${swap_gb:-0}

if [ "$swap_gb" -gt 0 ] 2>/dev/null; then
    echo -e "${GREEN}💾 Creating $swap_gb GB swap file...${NC}"
    SWAP_FILE="/swapfile"
    fallocate -l "${swap_gb}G" "$SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    fi
    echo -e "${GREEN}✔ $swap_gb GB swap created and enabled!${NC}"
else
    echo -e "${YELLOW}⚠ Skipping swap creation.${NC}"
fi

echo -e "\n${BLUE}📊 Current swap status:${NC}"
swapon --show || echo "No swap active."

# System update & packages 📦
echo -e "\n${CYAN}📦 Updating system and installing packages...${NC}"
apt update -y && apt upgrade -y

echo -e "${GREEN}✔ Installing useful tools...${NC}"
apt install -y git sudo curl socat vnstat nload speedtest-cli snapd lsof unzip zip htop mtr btop ufw p7zip-full ca-certificates gnupg screen

# Docker installation 🐳
echo -e "\n${CYAN}🐳 Docker installation${NC}"
read -p $'🔹 Install Docker? (y/n) [default: y]: ' install_docker
install_docker=${install_docker:-y}

if [[ "$install_docker" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}🐳 Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER"
        echo -e "${YELLOW}⚠ User '$SUDO_USER' added to docker group (re-login needed)${NC}"
    fi
    echo -e "${GREEN}✔ Docker installed! Version: $(docker --version)${NC}"
else
    echo -e "${YELLOW}⚠ Skipping Docker.${NC}"
fi

# Cleanup 🧹
echo -e "\n${CYAN}🧹 Cleaning up...${NC}"
apt autoremove -y && apt clean

# Final summary 🎉
echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════╗"
echo "║                     🎉 Setup Complete! 🎉                  ║"
echo "╚══════════════════════════════════════════════════════════╝${NC}"
echo -e "${BOLD}Summary:${NC}"
echo -e "📅 Timezone: $(timedatectl | grep 'Time zone' | awk -F: '{print $2}' | xargs)"
echo -e "⚡ TCP Congestion: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "🔒 IPv6 disabled: $(sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk '{print $NF}' || echo "N/A") (1 = disabled)"
echo -e "💾 Swap: $(swapon --show=SIZE --noheadings --bytes | numfmt --to=iec || echo "None")"
if command -v docker >/dev/null 2>&1; then
    echo -e "🐳 Docker: Installed ($(docker --version))"
else
    echo -e "🐳 Docker: Not installed"
fi
echo -e "\n${YELLOW}⚠ Reboot recommended for full effect!${NC}"
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════╗${NC}"
