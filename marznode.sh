#!/bin/bash

MARZ_PATH="/opt/marznode"

# بررسی وجود مسیر marznode
if [ ! -d "$MARZ_PATH" ]; then
    echo "❌ /opt/marznode not found. Installing..."
    bash <(curl -Ls https://raw.githubusercontent.com/mikeesierrah/ez-node/main/marznode.sh)
    exit 0
fi

# پیدا کردن پوشه متغیر داخل /opt/marznode
NODE_DIR=$(find "$MARZ_PATH" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -z "$NODE_DIR" ]; then
    echo "❌ No subdirectory found in $MARZ_PATH"
    exit 1
fi

XRAY_DIR="$NODE_DIR/xray"
if [ ! -d "$XRAY_DIR" ]; then
    echo "❌ Xray directory not found at $XRAY_DIR"
    exit 1
fi

# گرفتن نسخه جدید از کاربر
read -p "Enter Xray version (e.g. 1.8.23): " VERSION

# دانلود فایل جدید
cd "$XRAY_DIR"
ZIP_FILE="Xray-linux-64.zip"
URL="https://github.com/XTLS/Xray-core/releases/download/v${VERSION}/Xray-linux-64.zip"

echo "⬇️ Downloading Xray version v${VERSION}..."
curl -L -o "$ZIP_FILE" "$URL"

# بررسی موفقیت دانلود
if [ ! -f "$ZIP_FILE" ]; then
    echo "❌ Download failed. Please check the version number."
    exit 1
fi

# استخراج با overwrite
echo "📦 Extracting Xray package..."
unzip -o "$ZIP_FILE" >/dev/null 2>&1

# پیدا کردن نام فایل core فعلی
CORE_FILE=$(basename "$NODE_DIR")"-core"

# جایگزینی فایل xray جدید با core فعلی
if [ -f "$XRAY_DIR/xray" ]; then
    echo "🔁 Replacing existing $CORE_FILE..."
    mv -f "$XRAY_DIR/xray" "$XRAY_DIR/$CORE_FILE"
    chmod +x "$XRAY_DIR/$CORE_FILE"
else
    echo "⚠️ No xray binary found after extraction!"
    exit 1
fi

# پاکسازی فایل ZIP
rm -f "$XRAY_DIR/$ZIP_FILE"
echo "🧹 Cleaned up installation files."

# ===============================
# بخش اضافه‌شده برای geoip.dat و geosite.dat
# ===============================
GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"
GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"

echo "🗂 Removing old geoip.dat and geosite.dat..."
rm -f "$XRAY_DIR/geoip.dat" "$XRAY_DIR/geosite.dat"

echo "⬇️ Downloading new geoip.dat and geosite.dat..."
curl -L -o "$XRAY_DIR/geoip.dat" "$GEOIP_URL"
curl -L -o "$XRAY_DIR/geosite.dat" "$GEOSITE_URL"
echo "✅ geoip.dat and geosite.dat updated."

echo ""
echo "✅ Xray v${VERSION} updated successfully!"
echo "📂 Path: $XRAY_DIR/$CORE_FILE"
