#!/bin/bash

# ==============================
# 🧰 JUNK TOOL MENU (Color + Dynamic)
# ==============================

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# 🎨 Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

# جلوگیری از خروج با Ctrl+C
trap '' SIGINT

# ==============================
# نمایش منو
# ==============================
show_menu() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "======================================"
    echo "          🧰 JUNK TOOL MENU"
    echo "======================================"
    echo -e "${RESET}"

    # پیدا کردن تمام اسکریپت های .sh و .py کنار run.sh
   mapfile -t SCRIPTS < <(
    find "$BASE_DIR" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) ! -name "$(basename "$0")" | sort
)

    i=1
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
