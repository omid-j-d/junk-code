#!/bin/bash
set -e

BASE_DIR="/opt"

# 🎨 Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}🧰 Docker Node Installer${RESET}"

# اسم node
read -p "Enter a name for your node container: " NODE_NAME
if [ -z "$NODE_NAME" ]; then
    echo -e "${RED}❌ Name cannot be empty${RESET}"
    exit 1
fi

NODE_DIR="$BASE_DIR/$NODE_NAME"

# بررسی وجود فولدر
if [ -d "$NODE_DIR" ]; then
    read -p "⚠️ Folder $NODE_DIR already exists. Delete it? (y/N): " DELETE
    if [[ "$DELETE" =~ ^[Yy]$ ]]; then
        rm -rf "$NODE_DIR"
        mkdir -p "$NODE_DIR"
    else
        echo "🔄 Keeping existing folder. Will update docker & data."
    fi
else
    mkdir -p "$NODE_DIR"
fi

cd "$NODE_DIR"

# پورت و SECRET_KEY
read -p "Enter NODE_PORT: " NODE_PORT
if [ -z "$NODE_PORT" ]; then NODE_PORT=12345; fi
read -p "Enter SECRET_KEY: " SECRET_KEY
if [ -z "$SECRET_KEY" ]; then SECRET_KEY=""; fi

# دانلود geoip.dat و geosite.dat
GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"
GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"

echo "⬇️ Downloading geoip.dat and geosite.dat..."
curl -L -o "$NODE_DIR/geoip.dat" "$GEOIP_URL"
curl -L -o "$NODE_DIR/geosite.dat" "$GEOSITE_URL"

# ساخت docker-compose.yml
cat > "$NODE_DIR/docker-compose.yml" <<EOF
version: "3.8"

services:
  $NODE_NAME:
    container_name: $NODE_NAME
    hostname: $NODE_NAME
    image: remnawave/node:latest
    network_mode: host
    restart: always
    environment:
      - NODE_PORT=$NODE_PORT
      - SECRET_KEY=$SECRET_KEY
    volumes:
      - './geosite.dat:/usr/local/share/xray/geo-zapret.dat'
      - './geoip.dat:/usr/local/share/xray/ip-zapret.dat'
EOF

# ساخت wrapper command برای start/stop/restart/update
WRAPPER="/usr/local/bin/$NODE_NAME"
cat > "$WRAPPER" <<EOF
#!/bin/bash
NODE_DIR="$NODE_DIR"

if [ -z "\$1" ]; then
  echo "Usage: $NODE_NAME [start|stop|restart|update]"
  exit 1
fi

case "\$1" in
  start)
    docker-compose -f "\$NODE_DIR/docker-compose.yml" up -d
    ;;
  stop)
    docker-compose -f "\$NODE_DIR/docker-compose.yml" down
    ;;
  restart)
    docker-compose -f "\$NODE_DIR/docker-compose.yml" restart
    ;;
  update)
    docker-compose -f "\$NODE_DIR/docker-compose.yml" pull
    docker-compose -f "\$NODE_DIR/docker-compose.yml" up -d
    ;;
  *)
    echo "Invalid command. Use start|stop|restart|update"
    ;;
esac
EOF

chmod +x "$WRAPPER"
echo -e "${GREEN}✅ Node $NODE_NAME installed and wrapper command created as $NODE_NAME${RESET}"
echo "Use '$NODE_NAME start|stop|restart|update' to manage your container"
