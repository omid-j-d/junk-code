#!/bin/bash
set -e

REPO="https://github.com/omid-j-d/junk-code.git"
DEST="/opt/junk-code"
BIN="/usr/local/bin/junk"

echo "🧰 Installing Junk Tools..."

# چک root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root"
  exit 1
fi

# پیش‌نیازها
#apt update -y
apt install -y git python3 curl

# دانلود repo
rm -rf "$DEST"
git clone "$REPO" "$DEST"

# دسترسی اجرا
chmod +x "$DEST/run.sh"

# دستور junk
ln -sf "$DEST/run.sh" "$BIN"
chmod +x "$BIN"

echo ""
echo "✅ Installation complete!"
echo "👉 Run the tool anytime with: junk"
