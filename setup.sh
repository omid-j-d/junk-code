#!/bin/bash
# ðŸš€ Junk Server Setup
# Debian / Ubuntu
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SWAP_FILE="/swapfile"
BBR_CONF="/etc/sysctl.d/99-tcp-bbr.conf"
IPV6_CONF="/etc/sysctl.d/99-disable-ipv6.conf"
MODULES_CONF="/etc/modules-load.d/modules.conf"
DNS_CONF="/etc/systemd/resolved.conf.d/99-junk-dns.conf"
JUNK_CONF="/etc/junk-setup.conf"

# ---------- helpers ----------

die() { echo -e "${RED}âœ— $*${NC}"; exit 1; }
info() { echo -e "${CYAN}â„¹ $*${NC}"; }
ok() { echo -e "${GREEN}âœ“ $*${NC}"; }
warn() { echo -e "${YELLOW}âš  $*${NC}"; }
trap 'echo -e "\n${RED}âœ— Setup stopped at line $LINENO.${NC}"' ERR

require_root() { [[ "$EUID" -eq 0 ]] || die "Please run this script as root."; }

detect_os() {
    [[ -r /etc/os-release ]] || die "Cannot detect operating system."
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID:-}" in
        debian|ubuntu)
            OS_ID="$ID"; OS_NAME="${PRETTY_NAME:-$ID}"; OS_VERSION_ID="${VERSION_ID:-unknown}"; OS_CODENAME="${VERSION_CODENAME:-}" ;;
        *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. Only Debian and Ubuntu are supported." ;;
    esac
    if [[ -z "$OS_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
        OS_CODENAME="$(lsb_release -sc 2>/dev/null || true)"
    fi
    [[ -n "$OS_CODENAME" ]] || die "Could not determine OS codename."
}

get_swap_info() {
    if swapon --show=NAME,SIZE --noheadings 2>/dev/null | grep -q .; then
        SWAP_ACTIVE="yes"; SWAP_NAME="$(swapon --show=NAME --noheadings | head -n1)"; SWAP_SIZE="$(swapon --show=SIZE --noheadings | head -n1)"
    else
        SWAP_ACTIVE="no"; SWAP_NAME="-"; SWAP_SIZE="-"
    fi
}
get_cc() {
    CURRENT_CC="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    CURRENT_QDISC="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
}
get_ipv6_status() { IPV6_DISABLED="$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo unknown)"; }
get_timezone() {
    CURRENT_TZ="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    [[ -n "$CURRENT_TZ" ]] || CURRENT_TZ="$(cat /etc/timezone 2>/dev/null || echo unknown)"
}
get_dns() {
    DNS_SERVERS="$(resolvectl dns 2>/dev/null | awk '/: / {for(i=2;i<=NF;i++)print $i}' | sort -u | paste -sd, - || true)"
    [[ -n "$DNS_SERVERS" ]] || DNS_SERVERS="$(awk '/^nameserver /{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd, - || true)"
    [[ -n "$DNS_SERVERS" ]] || DNS_SERVERS="unknown"
}
get_package_status() {
    local packages=(git sudo curl socat vnstat nload speedtest-cli snapd lsof unzip zip htop mtr btop ufw p7zip-full ca-certificates gnupg screen)
    INSTALLED_PACKAGES=0; MISSING_PACKAGES=0
    for pkg in "${packages[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then ((INSTALLED_PACKAGES+=1)); else ((MISSING_PACKAGES+=1)); fi
    done
}
get_apt_status() {
    APT_UPGRADABLE="$(apt list --upgradable 2>/dev/null | awk 'NR>1 && /\//{n++} END{print n+0}')"
    [[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED="yes" || REBOOT_REQUIRED="no"
}
get_docker_status() { command -v docker >/dev/null 2>&1 && DOCKER_STATUS="$(docker --version 2>/dev/null)" || DOCKER_STATUS="Not installed"; }

get_release_upgrade_info() {
    UPGRADE_PATH=""
    if [[ "$OS_ID" == "debian" ]]; then
        case "$OS_CODENAME" in
            bullseye) UPGRADE_PATH="Debian 11 â†’ 12 (bookworm)" ;;
            bookworm) UPGRADE_PATH="Debian 12 â†’ 13 (trixie)" ;;
            trixie) UPGRADE_PATH="Debian 13 (trixie) â€” current stable" ;;
            *) UPGRADE_PATH="No automatic path configured" ;;
        esac
    else
        if ! command -v do-release-upgrade >/dev/null 2>&1; then
            UPGRADE_PATH="Ubuntu upgrader not installed yet"
        elif do-release-upgrade --check-dist-upgrade-only >/tmp/junk-release-check 2>&1; then
            UPGRADE_PATH="$(grep -E 'New release|new release' /tmp/junk-release-check | head -n1 || true)"
            [[ -n "$UPGRADE_PATH" ]] || UPGRADE_PATH="A supported Ubuntu release upgrade is available"
            rm -f /tmp/junk-release-check
        else
            UPGRADE_PATH="No supported Ubuntu release upgrade reported"
            rm -f /tmp/junk-release-check
        fi
    fi
}

show_system_info() {
    get_swap_info; get_cc; get_ipv6_status; get_timezone; get_dns; get_package_status; get_apt_status; get_docker_status; get_release_upgrade_info
    echo -e "${PURPLE}"
    echo "â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"
    echo "â•‘                    SERVER INFORMATION                    â•‘"
    echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
    echo -e "${NC}"
    echo -e "${BOLD}System${NC}"
    echo "  OS              : $OS_NAME"
    echo "  Codename        : $OS_CODENAME"
    echo "  Kernel          : $(uname -r)"
    echo "  Architecture    : $(dpkg --print-architecture 2>/dev/null || uname -m)"
    echo "  Uptime          : $(uptime -p 2>/dev/null || uptime)"
    echo "  Timezone        : $CURRENT_TZ"
    echo "  Time sync       : $(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo unknown)"
    echo
    echo -e "${BOLD}Network${NC}"
    echo "  TCP congestion  : $CURRENT_CC"
    echo "  Default qdisc   : $CURRENT_QDISC"
    echo "  IPv6 disabled   : $IPV6_DISABLED"
    echo "  DNS             : $DNS_SERVERS"
    echo
    echo -e "${BOLD}Memory / Swap${NC}"
    echo "  RAM             : $(free -h | awk '/^Mem:/{print $2}')"
    echo "  Swap            : ${SWAP_SIZE} (${SWAP_NAME})"
    echo
    echo -e "${BOLD}Packages${NC}"
    echo "  Required tools  : $INSTALLED_PACKAGES installed / $MISSING_PACKAGES missing"
    echo "  Docker          : $DOCKER_STATUS"
    echo
    echo -e "${BOLD}APT${NC}"
    echo "  Upgradable      : $APT_UPGRADABLE package(s)"
    echo "  Reboot required : $REBOOT_REQUIRED"
    echo
    echo -e "${BOLD}Release upgrade${NC}"
    echo "  Path            : $UPGRADE_PATH"
}

# ---------- BBR ----------
write_bbr_config() {
    local congestion="$1"
    if [[ "$congestion" == "bbr" ]]; then
        modprobe tcp_bbr 2>/dev/null || true
        touch "$MODULES_CONF"
        grep -qxF "tcp_bbr" "$MODULES_CONF" || echo "tcp_bbr" >> "$MODULES_CONF"
    fi
    cat > "$BBR_CONF" <<BBR_EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = $congestion
BBR_EOF
    sysctl --system >/dev/null
}
configure_bbr() {
    echo -e "\n${CYAN}âš¡ TCP congestion control${NC}"
    get_cc; echo "Current: $CURRENT_CC | qdisc: $CURRENT_QDISC"
    echo "  1) BBR + FQ"; echo "  2) Cubic + FQ"; echo "  3) Keep current"
    read -r -p $'ðŸ”¹ Choice [1]: ' cc_choice; cc_choice="${cc_choice:-1}"
    case "$cc_choice" in
        1) write_bbr_config bbr; ok "BBR + FQ enabled." ;;
        2) write_bbr_config cubic; ok "Cubic + FQ enabled." ;;
        3) info "Keeping current TCP congestion control." ;;
        *) warn "Invalid choice. Using BBR + FQ."; write_bbr_config bbr; ok "BBR + FQ enabled." ;;
    esac
}

# ---------- IPv6 ----------
configure_ipv6() {
    echo -e "\n${CYAN}ðŸ”’ IPv6 settings${NC}"
    read -r -p $'ðŸ”¹ Disable IPv6? (y/n) [default: n]: ' disable_ipv6; disable_ipv6="${disable_ipv6:-n}"
    if [[ "$disable_ipv6" =~ ^[Yy]$ ]]; then
        cat > "$IPV6_CONF" <<IPV6_EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
IPV6_EOF
        sysctl --system >/dev/null; ok "IPv6 disabled."
    else
        if [[ -f "$IPV6_CONF" ]]; then rm -f "$IPV6_CONF"; sysctl --system >/dev/null; fi
        ok "IPv6 left enabled."
    fi
}

# ---------- Swap ----------
remove_swap() {
    local swap
    while read -r swap; do
        [[ -n "$swap" ]] || continue
        swapoff "$swap" || true
        [[ -f "$swap" ]] && rm -f "$swap"
        sed -i "\|^[[:space:]]*$swap[[:space:]]|d" /etc/fstab
    done < <(swapon --show=NAME --noheadings 2>/dev/null)
    sed -i "\|^[[:space:]]*$SWAP_FILE[[:space:]]|d" /etc/fstab
}
create_swap() {
    local size="$1" bytes
    size="${size^^}"
    if [[ "$size" =~ ^[0-9]+$ ]]; then [[ "$size" == "512" ]] && size="512M" || size="${size}G"; fi
    [[ "$size" =~ ^[0-9]+([MG])$ ]] || { warn "Invalid swap size: $size"; return 1; }
    rm -f "$SWAP_FILE"
    if ! fallocate -l "$size" "$SWAP_FILE" 2>/dev/null; then
        if [[ "$size" == *G ]]; then bytes=$(( ${size%G} * 1024 * 1024 * 1024 )); else bytes=$(( ${size%M} * 1024 * 1024 )); fi
        dd if=/dev/zero of="$SWAP_FILE" bs=1 count=0 seek="$bytes" status=none
    fi
    chmod 600 "$SWAP_FILE"; mkswap "$SWAP_FILE" >/dev/null; swapon "$SWAP_FILE"
    grep -qF "$SWAP_FILE none swap sw 0 0" /etc/fstab || echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    ok "Swap $size created and enabled."
}
configure_swap() {
    echo -e "\n${CYAN}ðŸ’¾ Swap management${NC}"; get_swap_info
    if [[ "$SWAP_ACTIVE" == "yes" ]]; then
        echo "Current swap: $SWAP_NAME ($SWAP_SIZE)"
        echo "  Enter = keep current | D/delete = remove | Number = GB | 512 = 512 MB"
        echo "  512M / 1G = explicit units"
        read -r -p $'ðŸ”¹ Swap size/action: ' swap_input
        if [[ -z "$swap_input" ]]; then ok "Keeping current swap."
        elif [[ "$swap_input" =~ ^[Dd](elete)?$ ]]; then remove_swap; ok "Existing swap removed."
        else remove_swap; create_swap "$swap_input"; fi
    else
        echo "No active swap found."
        read -r -p $'ðŸ”¹ Create swap? Enter GB, 512 for 512 MB, or empty to skip: ' swap_input
        if [[ -z "$swap_input" ]]; then warn "Skipping swap creation."; else create_swap "$swap_input"; fi
    fi
    swapon --show || true
}

# ---------- Mirrors ----------
backup_apt_sources() {
    local stamp backup; stamp="$(date +%Y%m%d-%H%M%S)"; backup="/root/apt-sources-backup-$stamp"
    mkdir -p "$backup"; cp -a /etc/apt/sources.list "$backup/" 2>/dev/null || true; cp -a /etc/apt/sources.list.d "$backup/" 2>/dev/null || true; echo "$backup"
}
mirror_test() {
    local url="$1" codename="$2" start end
    start="$(date +%s%3N)"
    curl -4 -fsSL --max-time 5 -o /dev/null "$url/dists/$codename/InRelease" || return 1
    end="$(date +%s%3N)"; echo $((end-start))
}
get_selected_mirror() {
    SELECTED_MIRROR=""
    if [[ -f "$JUNK_CONF" ]]; then
        # shellcheck disable=SC1090
        source "$JUNK_CONF" 2>/dev/null || true
    fi
    SELECTED_MIRROR="${JUNK_MIRROR:-}"
}
save_selected_mirror() { printf 'JUNK_MIRROR=%q\n' "$1" > "$JUNK_CONF"; }

replace_urls_in_sources() {
    local old_pattern="$1" new_url="$2" file
    while IFS= read -r -d '' file; do sed -i -E "s#https?://$old_pattern#${new_url}#g" "$file" || true; done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) -print0)
}
set_debian_mirror() {
    local mirror="$1" backup; mirror="${mirror%/}"; backup="$(backup_apt_sources)"
    replace_urls_in_sources '([^[:space:]#]+\.)?debian\.org/debian' "$mirror"
    replace_urls_in_sources 'archive\.debian\.petiak\.ir/debian' "$mirror"
    replace_urls_in_sources 'repo\.mirror\.famaserver\.com/debian' "$mirror"
    replace_urls_in_sources 'mirrors\.pardisco\.co/debian' "$mirror"
    replace_urls_in_sources 'mirror\.arvancloud\.ir/debian' "$mirror"
    replace_urls_in_sources 'mirror\.iranserver\.com/debian' "$mirror"
    replace_urls_in_sources 'mirror\.aminidc\.com/debian' "$mirror"
    save_selected_mirror "$mirror"; ok "Debian mirror changed to $mirror"; info "APT source backup: $backup"
}
set_ubuntu_mirror() {
    local mirror="$1" backup; mirror="${mirror%/}"; backup="$(backup_apt_sources)"
    replace_urls_in_sources '([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu' "$mirror"
    replace_urls_in_sources 'security\.ubuntu\.com/ubuntu' "$mirror"
    replace_urls_in_sources 'ir\.archive\.ubuntu\.com/ubuntu' "$mirror"
    replace_urls_in_sources 'archive\.ubuntu\.petiak\.ir/ubuntu' "$mirror"
    replace_urls_in_sources 'mirrors\.pardisco\.co/ubuntu' "$mirror"
    replace_urls_in_sources 'mirror\.arvancloud\.ir/ubuntu' "$mirror"
    replace_urls_in_sources 'ir\.ubuntu\.sindad\.cloud/ubuntu' "$mirror"
    replace_urls_in_sources 'mirror\.iranserver\.com/ubuntu' "$mirror"
    replace_urls_in_sources 'ubuntu\.pishgaman\.net/ubuntu' "$mirror"
    replace_urls_in_sources 'ubuntu\.parsvds\.com/ubuntu' "$mirror"
    replace_urls_in_sources 'ubuntu\.mobinhost\.com/ubuntu' "$mirror"
    replace_urls_in_sources 'ubuntu\.hostiran\.ir/ubuntuarchive' "$mirror"
    replace_urls_in_sources 'mirror\.faraso\.org/ubuntu' "$mirror"
    save_selected_mirror "$mirror"; ok "Ubuntu mirror changed to $mirror"; info "APT source backup: $backup"
}
configure_mirror() {
    echo -e "\n${CYAN}ðŸŒ APT mirror${NC}"; get_selected_mirror; [[ -n "$SELECTED_MIRROR" ]] && echo "Saved mirror: $SELECTED_MIRROR"
    local candidates
    if [[ "$OS_ID" == "debian" ]]; then
        candidates=(
            "Debian CDN|https://deb.debian.org/debian"
            "Iran - Petiak (official Debian mirror)|https://archive.debian.petiak.ir/debian"
            "Iran - FamaServer (official Debian mirror)|https://repo.mirror.famaserver.com/debian"
            "Iran - Pardisco|https://mirrors.pardisco.co/debian"
            "Iran - ArvanCloud|https://mirror.arvancloud.ir/debian"
            "Netherlands - Leaseweb|https://mirror.nl.leaseweb.net/debian"
            "Netherlands - UTwente|https://debian.snt.utwente.nl/debian"
            "Germany - FAU|https://ftp.fau.de/debian"
            "Germany - Debian country mirror|https://ftp.de.debian.org/debian"
            "Kernel.org|https://mirrors.kernel.org/debian"
        )
    else
        candidates=(
            "Ubuntu primary|https://archive.ubuntu.com/ubuntu"
            "Iran - Petiak|https://archive.ubuntu.petiak.ir/ubuntu"
            "Iran - Pardisco|https://mirrors.pardisco.co/ubuntu"
            "Iran - ArvanCloud|https://mirror.arvancloud.ir/ubuntu"
            "Iran - Sindad|https://ir.ubuntu.sindad.cloud/ubuntu"
            "Iran - Pishgaman|https://ubuntu.pishgaman.net/ubuntu"
            "Iran - IranServer|https://mirror.iranserver.com/ubuntu"
            "Iran - ParsVDS|https://ubuntu.parsvds.com/ubuntu"
            "Iran - MobinHost|https://ubuntu.mobinhost.com/ubuntu"
            "Netherlands|https://nl.archive.ubuntu.com/ubuntu"
            "Germany|https://de.archive.ubuntu.com/ubuntu"
        )
    fi
    echo "  0) Keep current"; local i=1 item name url
    for item in "${candidates[@]}"; do name="${item%%|*}"; url="${item#*|}"; echo "  $i) $name - $url"; ((i+=1)); done
    echo "  T) Test all mirrors"; echo "  A) Automatically select fastest working mirror"; echo "  C) Custom mirror URL"
    read -r -p $'ðŸ”¹ Choice [0]: ' mirror_choice; mirror_choice="${mirror_choice:-0}"
    if [[ "$mirror_choice" =~ ^[TtAa]$ ]]; then
        local best_url="" best_ms=999999 latency
        for item in "${candidates[@]}"; do
            name="${item%%|*}"; url="${item#*|}"; printf "  %-42s " "$name"
            if latency="$(mirror_test "$url" "$OS_CODENAME")"; then echo "${latency} ms"; if ((latency<best_ms)); then best_ms="$latency"; best_url="$url"; fi; else echo "unreachable"; fi
        done
        if [[ "$mirror_choice" =~ ^[Aa]$ ]]; then
            [[ -n "$best_url" ]] || { warn "No working mirror found."; return; }
            info "Fastest working mirror: $best_url (${best_ms} ms)"
            [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$best_url" || set_ubuntu_mirror "$best_url"
        else read -r -p "Press Enter to continue..." _; fi
        return
    fi
    if [[ "$mirror_choice" =~ ^[Cc]$ ]]; then read -r -p "Custom mirror base URL: " url; [[ -n "$url" ]] || return; url="${url%/}"
    elif [[ "$mirror_choice" =~ ^[0-9]+$ ]] && ((mirror_choice>=1 && mirror_choice<=${#candidates[@]})); then item="${candidates[$((mirror_choice-1))]}"; url="${item#*|}"
    else return; fi
    [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$url" || set_ubuntu_mirror "$url"
}

# ---------- DNS ----------
configure_dns() {
    echo -e "\n${CYAN}ðŸ§­ DNS configuration${NC}"; get_dns; echo "Current DNS: $DNS_SERVERS"
    echo "  1) Cloudflare      1.1.1.1 / 1.0.0.1"; echo "  2) Google          8.8.8.8 / 8.8.4.4"; echo "  3) Quad9           9.9.9.9 / 149.112.112.112"; echo "  4) Keep current"; echo "  5) Custom"
    read -r -p $'ðŸ”¹ Choice [4]: ' dns_choice; dns_choice="${dns_choice:-4}"
    case "$dns_choice" in
        1) DNS1="1.1.1.1"; DNS2="1.0.0.1";; 2) DNS1="8.8.8.8"; DNS2="8.8.4.4";; 3) DNS1="9.9.9.9"; DNS2="149.112.112.112";;
        4) info "Keeping current DNS."; return;;
        5) read -r -p "Primary DNS: " DNS1; read -r -p "Secondary DNS: " DNS2; [[ -n "$DNS1" ]] || return;;
        *) warn "Invalid choice."; return;;
    esac
    if systemctl is-active --quiet systemd-resolved 2>/dev/null && command -v resolvectl >/dev/null 2>&1; then
        mkdir -p "$(dirname "$DNS_CONF")"
        cat > "$DNS_CONF" <<DNS_EOF
[Resolve]
DNS=$DNS1 $DNS2
FallbackDNS=1.1.1.1 8.8.8.8
DNS_EOF
        systemctl restart systemd-resolved; ok "DNS configured through systemd-resolved."
    else
        local backup="/etc/resolv.conf.junk-backup-$(date +%Y%m%d-%H%M%S)"; cp -L /etc/resolv.conf "$backup" 2>/dev/null || true
        rm -f /etc/resolv.conf; printf 'nameserver %s\nnameserver %s\n' "$DNS1" "$DNS2" > /etc/resolv.conf
        ok "DNS configured in /etc/resolv.conf"; warn "NetworkManager/netplan may overwrite /etc/resolv.conf."; info "Backup: $backup"
    fi
}

# ---------- Time ----------
configure_time() {
    echo -e "\n${CYAN}ðŸ•’ Time and timezone${NC}"; get_timezone; echo "Current timezone: $CURRENT_TZ"; echo "Current clock:    $(date)"
    read -r -p $'ðŸ”¹ Detect timezone from public IP and fix clock? (Y/n): ' time_choice; time_choice="${time_choice:-y}"
    if [[ "$time_choice" =~ ^[Yy]$ ]]; then
        local detected_tz="$(curl -4 -fsSL --max-time 7 https://ipapi.co/timezone/ 2>/dev/null | tr -d '\r\n' || true)"
        if [[ -n "$detected_tz" && "$detected_tz" != "Undefined" ]]; then
            if timedatectl list-timezones | grep -qx "$detected_tz"; then timedatectl set-timezone "$detected_tz"; ok "Timezone set to $detected_tz based on public IP."; else warn "Detected timezone '$detected_tz' is not available."; fi
        else warn "Could not detect timezone from public IP."; fi
    fi
    timedatectl set-ntp true 2>/dev/null || true; systemctl restart systemd-timesyncd 2>/dev/null || true; ok "Time synchronization requested."
}

# ---------- System updates / packages ----------
update_system() { echo -e "\n${CYAN}ðŸ“¦ Updating package index and system...${NC}"; apt-get update; apt-get upgrade -y; ok "System packages updated."; }
install_packages() { echo -e "\n${CYAN}ðŸ§° Installing useful tools...${NC}"; apt-get install -y git sudo curl socat vnstat nload speedtest-cli snapd lsof unzip zip htop mtr btop ufw p7zip-full ca-certificates gnupg screen; ok "Useful packages installed."; }

# ---------- Docker ----------
configure_docker() {
    echo -e "\n${CYAN}ðŸ³ Docker installation${NC}"; read -r -p $'ðŸ”¹ Install Docker? (y/n) [default: y]: ' install_docker; install_docker="${install_docker:-y}"
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        if command -v docker >/dev/null 2>&1; then ok "Docker already installed: $(docker --version)"; else curl -fsSL https://get.docker.com | sh; systemctl enable --now docker; [[ -n "${SUDO_USER:-}" ]] && usermod -aG docker "$SUDO_USER"; ok "Docker installed: $(docker --version)"; fi
    else info "Skipping Docker."; fi
}

# ---------- Release upgrade ----------
get_debian_target() {
    case "$OS_CODENAME" in
        bullseye) echo "
