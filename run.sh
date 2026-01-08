#!/bin/bash
# 🚀 Junk Scripts Menu - Auto Return Fixed 🚀
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# همیشه تو دایرکتوری خودش باشه
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# تابع اجرای اسکریپت با بازگشت تضمینی
run_script() {
    local script="$1"
    chmod +x "$script" 2>/dev/null || true

    echo -e "${GREEN}🚀 Running $script ...${NC}\n"

    # اگر نیاز به root داره → با sudo
    if head -n 10 "$script" | grep -q "root" || [[ "$script" == setup.sh ]] || [[ "$script" == pingtunnel.sh ]]; then
        sudo bash "$script"
    else
        bash "$script"
    fi

    # بعد از اجرا، حتماً برگرده
    echo -e "\n${GREEN}✔ Script finished.${NC}"
    echo -e "${YELLOW}Press Enter to return to menu...${NC}"
    read -r  # منتظر فشار Enter می‌مونه
}

while true; do
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║              🚀 Junk Scripts Menu 🚀                      ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝${NC}\n"

    # لیست اسکریپت‌ها
    scripts=($(ls *.sh *.py 2>/dev/null | grep -vE '^(run\.sh|install\.sh)$' | sort))

    if [ ${#scripts[@]} -eq 0 ]; then
        echo -e "${RED}✗ No scripts found!${NC}"
        exit 1
    fi

    echo -e "${BOLD}Available Scripts:${NC}"
    for i in "${!scripts[@]}"; do
        num=$((i + 1))
        if [[ "${scripts[i]}" == *.py ]]; then
            echo -e "  ${CYAN}$num)${NC} ${GREEN}${scripts[i]}${NC} ${YELLOW}(Python 🐍)${NC}"
        else
            echo -e "  ${CYAN}$num)${NC} ${GREEN}${scripts[i]}${NC}"
        fi
    done

    update_option=$(( ${#scripts[@]} + 1 ))
    echo -e "  ${CYAN}$update_option)${NC} ${YELLOW}🔄 Update All Scripts (git pull)${NC}"
    echo -e "  ${CYAN}0)${NC} ${RED}🚪 Exit${NC}\n"

    read -p $'🔹 Enter your choice: ' choice

    case "$choice" in
        0)
            echo -e "${GREEN}✔ Goodbye! 👋${NC}"
            exit 0
            ;;
        "$update_option")
            echo -e "${YELLOW}🔄 Updating from GitHub...${NC}"
            if git pull origin main > /dev/null 2>&1; then
                echo -e "${GREEN}✔ Updated successfully! Restart menu for changes.${NC}"
            else
                echo -e "${RED}✗ Update failed (not a git repo?)${NC}"
            fi
            read -r
            continue
            ;;
        *)
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#scripts[@]} ]; then
                echo -e "${RED}✗ Invalid choice!${NC}"
                sleep 2
                continue
            fi

            selected="${scripts[$((choice - 1))]}"
            run_script "$selected"
            # بعد از run_script، لوپ ادامه پیدا می‌کنه → خودکار برمی‌گرده به منو
            ;;
    esac
done
