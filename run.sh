#!/bin/bash

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

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

while true; do
  clear
  echo -e "${CYAN}${BOLD}"
  echo "======================================"
  echo "          🧰 JUNK TOOL MENU"
  echo "======================================"
  echo -e "${RESET}"

  mapfile -t SCRIPTS < <(
    find "$BASE_DIR" -maxdepth 1 -type f \
    \( -name "*.sh" -o -name "*.py" \) \
    ! -name "run.sh" | sort
  )

  i=1
  for script in "${SCRIPTS[@]}"; do
    echo -e "${YELLOW}$i)${RESET} $(basename "$script")"
    ((i++))
  done

  echo -e "${RED}0) Exit${RESET}"
  echo "--------------------------------------"

  read -p "Select an option: " choice

  if [[ "$choice" == "0" ]]; then
    clear
    echo -e "${GREEN}Bye 👋${RESET}"
    exit 0
  fi

  index=$((choice - 1))
  if [[ -n "${SCRIPTS[$index]}" ]]; then
    script="${SCRIPTS[$index]}"
    clear
    echo -e "${BLUE}▶ Running:${RESET} $(basename "$script")"
    echo "--------------------------------------"

    cd "$BASE_DIR"
    [[ "$script" == *.py ]] && python3 "$script" || bash "$script"

    echo ""
    echo -e "${GREEN}✅ Script finished.${RESET}"
    read -p "Press Enter to return to menu..."
  else
    echo -e "${RED}❌ Invalid option${RESET}"
    sleep 1
  fi
done
