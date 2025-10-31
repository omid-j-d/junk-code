#!/bin/bash

# تابعی برای گرفتن Ctrl+C
trap ctrl_c INT

ctrl_c() {
    echo -e "\n⚡ Returning to main menu..."
    sleep 1
}

while true; do
    clear
    echo "======================="
    echo "   AIO Script Launcher "
    echo "======================="
    echo "1) adblocklist"
    echo "4) Run script 2"
    echo "3) Exit"
    read -p "Choose an option [1-3]: " choice

    case $choice in
        1)
            echo "🐍 Running Python script..."
            # Ctrl+C داخل این اسکریپت باعث برگرداندن به منو میشه
            PY_FILE=$(mktemp /tmp/nsfwblock.py)
            curl -fsSL https://raw.githubusercontent.com/omid-j-d/junk-code/refs/heads/main/nsfwblock.py -o "$PY_FILE"
            python3 "$PY_FILE" || true
            rm -f "$PY_FILE"
            ;;
        2)
            echo "🚀 Running Bash script..."
            bash <(curl -fsSL https://raw.githubusercontent.com/omid-j-d/junk-code/main/setup-fastfetch.sh) || true
            ;;
        3)
            echo "👋 Goodbye!"
            exit 0
            ;;
        4)
            echo "🐍 Running Python script..."
            python3 <(https://raw.githubusercontent.com/omid-j-d/junk-code/refs/heads/main/nsfwblock.py) || true
            ;;
        *)
            echo "❌ Invalid option, try again."
            sleep 1
            ;;
    esac
done
