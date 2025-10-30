#!/bin/bash
# Fastfetch Auto Installer & Configurator for Debian 13

set -e

# مسیر تنظیمات
CONFIG_DIR="$HOME/.config/fastfetch"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"
CONFIG_URL="https://raw.githubusercontent.com/omid-j-d/junk-code/main/config.jsonc"

echo "🔧 Updating package list..."
sudo apt update -y

echo "📦 Installing fastfetch..."
sudo apt install -y fastfetch curl

echo "📁 Creating config directory..."
mkdir -p "$CONFIG_DIR"

echo "⬇️ Downloading config.jsonc..."
curl -fsSL "$CONFIG_URL" -o "$CONFIG_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Config file downloaded successfully to $CONFIG_FILE"
else
    echo "❌ Failed to download config file. Please check the URL."
    exit 1
fi

# بررسی اینکه fastfetch از قبل در bashrc هست یا نه
if grep -q "fastfetch" ~/.bashrc; then
    echo "⚙️  fastfetch is already set to run in .bashrc"
else
    echo "🧩 Adding fastfetch to .bashrc..."
    echo "fastfetch" >> ~/.bashrc
fi

echo ""
echo "✅ Installation complete!"
echo "➡️  Please restart your terminal or run 'source ~/.bashrc' to see fastfetch in action."
