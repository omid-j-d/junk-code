#!/bin/bash
# 🚀 Scripts Menu - Updated & Sorted 🚀
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

clear
echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║              🚀 Scripts Menu - Choose One 🚀             ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝${NC}\n"

# لیست همه فایل‌های .sh به جز run.sh و install.sh، مرتب‌شده الفبایی
scripts=($(ls *.sh 2>/dev/null | grep -vE '^(run\.sh|install\.sh)$' | sort))

# اگر اسکریپتی نبود
if [ ${#scripts[@]} -eq 0 ]; then
    echo -e "${RED}✗ No scripts found in this directory!${NC}"
    exit 1
fi

# نمایش گزینه‌ها با شماره
echo -e "${BOLD}Available Scripts:${NC}"
for i in "${!scripts[@]}"; do
    num=$((i + 1))
    echo -e "  ${CYAN}$num)${NC} ${GREEN}${scripts[i]}${NC}"
done

# گزینه آپدیت همیشه آخر
update_option=$(( ${#scripts[@]} + 1 ))
echo -e "  ${CYAN}$update_option)${NC} ${YELLOW}🔄 Update All Scripts (git pull)${NC}"
echo -e "  ${CYAN}0)${NC} ${RED}🚪 Exit${NC}\n"

# گرفتن انتخاب کاربر
read -p $'🔹 Enter your choice: ' choice

# خروج
if [ "$choice" = "0" ]; then
    echo -e "${GREEN}✔ Goodbye! 👋${NC}"
    exit 0
fi

# آپدیت اسکریپت‌ها
if [ "$choice" = "$update_option" ]; then
    echo -e "${YELLOW}🔄 Updating scripts from GitHub...${NC}"
    if git pull origin main > /dev/null 2>&1; then
        echo -e "${GREEN}✔ Scripts updated successfully! Restart the menu to see changes.${NC}"
    else
        echo -e "${RED}✗ Update failed! Are you in a git repository?${NC}"
    fi
    read -p "Press Enter to continue..."
    exec "$0"  # ری‌استارت منو
fi

# چک اعتبار انتخاب
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#scripts[@]} ]; then
    echo -e "${RED}✗ Invalid choice!${NC}"
    sleep 2
    exec "$0"
fi

# اجرای اسکریپت انتخاب‌شده
selected_script="${scripts[$((choice - 1))]}"
echo -e "${GREEN}🚀 Running $selected_script ...${NC}\n"

# مجوز اجرا اگر لازم باشه
chmod +x "$selected_script" 2>/dev/null || true

# اجرا (با sudo اگر لازم باشه، اما مراقب باش – بسته به اسکریپت)
if grep -q "root" "$selected_script" 2>/dev/null || [[ "$selected_script" == setup.sh* ]]; then
    sudo bash "$selected_script"
else
    bash "$selected_script"
fi

echo -e "\n${GREEN}✔ Done!${NC}"
read -p "Press Enter to return to menu..."
exec "$0"  # برگشت به منو    i=1
    for script in "${SCRIPTS[@]}"; do
        echo -e "${YELLOW}$i)${RESET} $(basename "$script")"
        ((i++))
    done

    echo -e "${RED}0) Exit${RESET}"
    echo "--------------------------------------"
}

# ==============================
# اجرای اسکریپت انتخاب شده
# ==============================
run_script() {
    local script="$1"
    clear
    echo -e "${BLUE}▶ Running:${RESET} $(basename "$script")"
    echo "--------------------------------------"

    cd "$BASE_DIR"
    if [[ "$script" == *.py ]]; then
        python3 "$script"
    else
        bash "$script"
    fi

    echo ""
    echo -e "${GREEN}✅ Script finished.${RESET}"
    read -p "Press Enter to return to menu..."
}

# ==============================
# حلقه منو
# ==============================
while true; do
    show_menu
    read -p "Select an option: " choice

    if [[ "$choice" == "0" ]]; then
        clear
        echo -e "${GREEN}Bye 👋${RESET}"
        exit 0
    fi

    index=$((choice - 1))
    if [[ -n "${SCRIPTS[$index]}" ]]; then
        run_script "${SCRIPTS[$index]}"
    else
        echo -e "${RED}❌ Invalid option${RESET}"
        sleep 1
    fi
done
