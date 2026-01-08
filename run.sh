#!/bin/bash
# 🚀 Junk Scripts Menu - Supports .sh & .py 🚀
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

# تغییر به دایرکتوری اسکریپت
cd "$(dirname "$(realpath "$0")")"

clear
echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║              🚀 Junk Scripts Menu 🚀                      ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝${NC}\n"

# لیست همه .sh و .py به جز run.sh و install.sh، مرتب الفبایی
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

if [ "$choice" = "0" ]; then
    echo -e "${GREEN}✔ Goodbye! 👋${NC}"
    exit 0
fi

if [ "$choice" = "$update_option" ]; then
    echo -e "${YELLOW}🔄 Updating from GitHub...${NC}"
    if git pull origin main > /dev/null 2>&1; then
        echo -e "${GREEN}✔ Updated successfully! Restart menu for changes.${NC}"
    else
        echo -e "${RED}✗ Update failed (not a git repo?)${NC}"
    fi
    read -p "Press Enter to continue..."
    exec "$0"
fi

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#scripts[@]} ]; then
    echo -e "${RED}✗ Invalid choice!${NC}"
    sleep 2
    exec "$0"
fi

selected_script="${scripts[$((choice - 1))]}"
echo -e "${GREEN}🚀 Running $selected_script ...${NC}\n"

# مجوز اجرا
chmod +x "$selected_script" 2>/dev/null || true

# اجرا بر اساس نوع فایل
if [[ "$selected_script" == *.py ]]; then
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}✗ Python3 not installed! Install it first: apt install python3${NC}"
        read -p "Press Enter to continue..."
        exec "$0"
    fi
    python3 "$selected_script"
elif head -n 10 "$selected_script" | grep -q "root" || [[ "$selected_script" == setup.sh ]]; then
    sudo bash "$selected_script"
else
    bash "$selected_script"
fi

echo -e "\n${GREEN}✔ Done!${NC}"
read -p "Press Enter to return to menu..."
exec "$0"
