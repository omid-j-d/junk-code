#!/bin/bash
# 🚀 Junk Server Setup
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

die() { echo -e "${RED}✗ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ $*${NC}"; }
ok() { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }

# Return success when the user wants to skip the current stage.
# This keeps the script running instead of terminating on bad/optional input.
is_skip() { [[ "${1:-}" =~ ^([Ss]|[Ss][Kk][Ii][Pp])$ ]]; }

read_choice() {
    local __var="$1" prompt="$2" default="${3:-}" value
    while true; do
        if [[ -n "$default" ]]; then
            read -r -p "$prompt [$default]: " value
            value="${value:-$default}"
        else
            read -r -p "$prompt: " value
        fi
        printf -v "$__var" '%s' "$value"
        return 0
    done
}
trap 'echo -e "\n${RED}✗ Setup stopped at line $LINENO.${NC}"' ERR

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
            bullseye) UPGRADE_PATH="Debian 11 → 12 (bookworm)" ;;
            bookworm) UPGRADE_PATH="Debian 12 → 13 (trixie)" ;;
            trixie) UPGRADE_PATH="Debian 13 (trixie) — current stable" ;;
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
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                    SERVER INFORMATION                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
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
    while true; do
        echo -e "\n${CYAN}⚡ TCP congestion control${NC}"
        get_cc; echo "Current: $CURRENT_CC | qdisc: $CURRENT_QDISC"
        echo "  1) BBR + FQ"
        echo "  2) Cubic + FQ"
        echo "  3) Keep current"
        echo "  S) Skip this stage"
        read -r -p $'🔹 Choice [1]: ' cc_choice
        cc_choice="${cc_choice:-1}"
        case "$cc_choice" in
            1) write_bbr_config bbr; ok "BBR + FQ enabled."; return ;;
            2) write_bbr_config cubic; ok "Cubic + FQ enabled."; return ;;
            3) info "Keeping current TCP congestion control."; return ;;
            [Ss]|[Ss][Kk][Ii][Pp]) info "Skipping TCP congestion control."; return ;;
            *) warn "Invalid choice. Please enter 1, 2, 3 or S." ;;
        esac
    done
}

# ---------- IPv6 ----------
configure_ipv6() {
    while true; do
        echo -e "\n${CYAN}🔒 IPv6 settings${NC}"
        read -r -p $'🔹 Disable IPv6? (y/n) [default: n, S=skip]: ' disable_ipv6
        disable_ipv6="${disable_ipv6:-n}"
        if is_skip "$disable_ipv6"; then info "Skipping IPv6 configuration."; return; fi
        if [[ "$disable_ipv6" =~ ^[Yy]$ ]]; then
            cat > "$IPV6_CONF" <<IPV6_EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
IPV6_EOF
            sysctl --system >/dev/null; ok "IPv6 disabled."; return
        elif [[ "$disable_ipv6" =~ ^[Nn]$ ]]; then
            if [[ -f "$IPV6_CONF" ]]; then rm -f "$IPV6_CONF"; sysctl --system >/dev/null; fi
            ok "IPv6 left enabled."; return
        else
            warn "Invalid choice. Enter y, n or S."
        fi
    done
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
    while true; do
        echo -e "\n${CYAN}💾 Swap management${NC}"; get_swap_info
        if [[ "$SWAP_ACTIVE" == "yes" ]]; then
            echo "Current swap: $SWAP_NAME ($SWAP_SIZE)"
            echo "  Enter = keep current | D/delete = remove | Number = GB | 512 = 512 MB"
            echo "  512M / 1G = explicit units | S = skip stage"
            read -r -p $'🔹 Swap size/action: ' swap_input
            if [[ -z "$swap_input" ]]; then ok "Keeping current swap."; return
            elif is_skip "$swap_input"; then info "Skipping swap configuration."; return
            elif [[ "$swap_input" =~ ^[Dd](elete)?$ ]]; then remove_swap; ok "Existing swap removed."; return
            elif [[ "$swap_input" =~ ^[0-9]+([MGmg])?$ && "$swap_input" != "0" ]]; then
                remove_swap
                if create_swap "$swap_input"; then return; fi
            else
                warn "Invalid swap size/action. Examples: 2, 4, 512, 512M, 1G, D, S."
            fi
        else
            echo "No active swap found."
            read -r -p $'🔹 Create swap? Enter GB, 512 for 512 MB, or empty to skip (S=skip): ' swap_input
            if [[ -z "$swap_input" ]]; then warn "Skipping swap creation."; return
            elif is_skip "$swap_input"; then info "Skipping swap configuration."; return
            elif [[ "$swap_input" =~ ^[0-9]+([MGmg])?$ && "$swap_input" != "0" ]]; then
                if create_swap "$swap_input"; then return; fi
            else
                warn "Invalid swap size. Examples: 2, 4, 512, 512M, 1G or S."
            fi
        fi
    done
}

# ---------- Mirrors ----------
backup_apt_sources() {
    local stamp backup; stamp="$(date +%Y%m%d-%H%M%S)"; backup="/root/apt-sources-backup-$stamp"
    mkdir -p "$backup"; cp -a /etc/apt/sources.list "$backup/" 2>/dev/null || true; cp -a /etc/apt/sources.list.d "$backup/" 2>/dev/null || true; echo "$backup"
}
mirror_test() {
    local url="$1" codename="$2" arch="$3" bytes speed path
    url="${url%/}"

    # Test a real compressed Packages index instead of a tiny InRelease file.
    # This gives a useful approximation of download throughput from this VPS.
    path="dists/$codename/main/binary-$arch/Packages.xz"
    speed="$(curl -4 -fsSL --max-time 15 --connect-timeout 5 -o /dev/null \
        -w '%{speed_download}' "$url/$path" 2>/dev/null || true)"

    [[ "$speed" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v bps="$speed" 'BEGIN { printf "%.2f", bps/1048576 }'
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
    while true; do
        echo -e "\n${CYAN}🌐 APT mirror${NC}"; get_selected_mirror; [[ -n "$SELECTED_MIRROR" ]] && echo "Saved mirror: $SELECTED_MIRROR"
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
        echo "  0) Keep current"
        local i=1 item name url choice
        for item in "${candidates[@]}"; do name="${item%%|*}"; url="${item#*|}"; echo "  $i) $name - $url"; ((i+=1)); done
        echo "  T) Benchmark all mirrors (download speed)"
        echo "  A) Automatically select fastest mirror"
        echo "  C) Custom mirror URL"
        echo "  S) Skip this stage"
        read -r -p $'🔹 Choice [0]: ' choice
        choice="${choice:-0}"

        if [[ "$choice" =~ ^[Ss]$|^[Ss][Kk][Ii][Pp]$ ]]; then info "Skipping mirror configuration."; return; fi
        if [[ "$choice" == "0" ]]; then info "Keeping current mirror configuration."; return; fi

        if [[ "$choice" =~ ^[TtAa]$ ]]; then
            local best_url="" best_speed=0 speed arch
            arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
            echo
            echo "Testing download throughput for $OS_CODENAME/$arch..."
            printf '%-42s %12s\n' "Mirror" "Speed"
            printf '%-42s %12s\n' "------------------------------------------" "------------"
            for item in "${candidates[@]}"; do
                name="${item%%|*}"; url="${item#*|}"; printf '%-42s ' "$name"
                if speed="$(mirror_test "$url" "$OS_CODENAME" "$arch")"; then
                    echo "${speed} MB/s"
                    if awk -v a="$speed" -v b="$best_speed" 'BEGIN{exit !(a>b)}'; then best_speed="$speed"; best_url="$url"; fi
                else
                    echo "unreachable / unsupported"
                fi
            done
            if [[ -z "$best_url" ]]; then warn "No working mirror passed the benchmark."; continue; fi
            echo
            info "Fastest tested mirror: $best_url (${best_speed} MB/s)"
            if [[ "$choice" =~ ^[Aa]$ ]]; then
                [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$best_url" || set_ubuntu_mirror "$best_url"
                return
            fi
            read -r -p $'Use this fastest mirror? (Y/n): ' use_best
            use_best="${use_best:-y}"
            if [[ "$use_best" =~ ^[Yy]$ ]]; then
                [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$best_url" || set_ubuntu_mirror "$best_url"
                return
            fi
            continue
        fi

        if [[ "$choice" =~ ^[Cc]$ ]]; then
            read -r -p "Custom mirror base URL (S=skip): " url
            if is_skip "$url"; then info "Skipping mirror configuration."; return; fi
            url="${url%/}"
            if [[ -z "$url" || ! "$url" =~ ^https?:// ]]; then warn "Invalid mirror URL."; continue; fi
        elif [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#candidates[@]})); then
            item="${candidates[$((choice-1))]}"; url="${item#*|}"
        else
            warn "Invalid choice. Enter a listed number, T, A, C or S."
            continue
        fi
        [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$url" || set_ubuntu_mirror "$url"
        return
    done
}

# ---------- DNS ----------
configure_dns() {
    while true; do
        echo -e "\n${CYAN}🧭 DNS configuration${NC}"; get_dns; echo "Current DNS: $DNS_SERVERS"
        echo "  1) Cloudflare      1.1.1.1 / 1.0.0.1"
        echo "  2) Google          8.8.8.8 / 8.8.4.4"
        echo "  3) Quad9           9.9.9.9 / 149.112.112.112"
        echo "  4) Keep current"
        echo "  5) Custom"
        echo "  S) Skip this stage"
        read -r -p $'🔹 Choice [4]: ' dns_choice; dns_choice="${dns_choice:-4}"
        case "$dns_choice" in
            1) DNS1="1.1.1.1"; DNS2="1.0.0.1";;
            2) DNS1="8.8.8.8"; DNS2="8.8.4.4";;
            3) DNS1="9.9.9.9"; DNS2="149.112.112.112";;
            4) info "Keeping current DNS."; return;;
            [Ss]|[Ss][Kk][Ii][Pp]) info "Skipping DNS configuration."; return;;
            5)
                read -r -p "Primary DNS (S=skip): " DNS1
                if is_skip "$DNS1"; then info "Skipping DNS configuration."; return; fi
                read -r -p "Secondary DNS (optional): " DNS2
                DNS2="${DNS2:-$DNS1}"
                ;;
            *) warn "Invalid choice. Enter 1-5 or S."; continue;;
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
        return
    done
}

# ---------- Time ----------
configure_time() {
    echo -e "\n${CYAN}🕒 Time and timezone${NC}"; get_timezone; echo "Current timezone: $CURRENT_TZ"; echo "Current clock:    $(date)"
    read -r -p $'🔹 Detect timezone from public IP and fix clock? (Y/n, S=skip): ' time_choice; time_choice="${time_choice:-y}"
    if is_skip "$time_choice"; then info "Skipping time/timezone configuration."; return; fi
    if [[ "$time_choice" =~ ^[Yy]$ ]]; then
        local detected_tz=""
        local public_ip=""

        # Try several providers because IP-geolocation APIs can rate-limit or block
        # requests from VPS/datacenter addresses.
        public_ip="$(curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '\r\n' || true)"

        # 1) ipapi.co
        detected_tz="$(curl -4 -fsSL --max-time 7 https://ipapi.co/timezone/ 2>/dev/null | tr -d '\r\n' || true)"
        [[ "$detected_tz" == "Undefined" || "$detected_tz" == "null" ]] && detected_tz=""

        # 2) ipwho.is (JSON response)
        if [[ -z "$detected_tz" && -n "$public_ip" ]]; then
            detected_tz="$(curl -4 -fsSL --max-time 7 "https://ipwho.is/$public_ip" 2>/dev/null | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*{[^}]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
        fi

        # 3) ipinfo.io (tokenless endpoint; may be unavailable in some regions)
        if [[ -z "$detected_tz" && -n "$public_ip" ]]; then
            detected_tz="$(curl -4 -fsSL --max-time 7 "https://ipinfo.io/$public_ip/json" 2>/dev/null | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
        fi

        if [[ -n "$detected_tz" ]]; then
            if timedatectl list-timezones | grep -qx "$detected_tz"; then
                timedatectl set-timezone "$detected_tz"
                ok "Timezone set to $detected_tz based on public IP${public_ip:+ ($public_ip)}."
            else
                warn "Detected timezone '$detected_tz' is not available on this system."
            fi
        else
            warn "Could not detect timezone from public IP. Keeping current timezone: $CURRENT_TZ"
            info "You can set it manually with: timedatectl set-timezone <Area/City>"
        fi
    elif [[ ! "$time_choice" =~ ^[Nn]$ ]]; then
        warn "Invalid choice. Enter y, n or S."
        return
    fi
    timedatectl set-ntp true 2>/dev/null || true; systemctl restart systemd-timesyncd 2>/dev/null || true; ok "Time synchronization requested."
}

# ---------- System updates / packages ----------
update_system() {
    while true; do
        echo -e "\n${CYAN}📦 System update${NC}"
        read -r -p $'🔹 Run apt update + upgrade? (Y/n, S=skip): ' answer; answer="${answer:-y}"
        if is_skip "$answer"; then info "Skipping system update."; return; fi
        if [[ "$answer" =~ ^[Yy]$ ]]; then apt-get update; apt-get upgrade -y; ok "System packages updated."; return; fi
        if [[ "$answer" =~ ^[Nn]$ ]]; then info "Skipping system update."; return; fi
        warn "Invalid choice. Enter y, n or S."
    done
}
install_packages() {
    while true; do
        echo -e "\n${CYAN}🧰 Useful packages${NC}"
        read -r -p $'🔹 Install missing useful packages? (Y/n, S=skip): ' answer; answer="${answer:-y}"
        if is_skip "$answer"; then info "Skipping package installation."; return; fi
        if [[ "$answer" =~ ^[Yy]$ ]]; then apt-get install -y git sudo curl socat vnstat nload speedtest-cli snapd lsof unzip zip htop mtr btop ufw p7zip-full ca-certificates gnupg screen; ok "Useful packages installed."; return; fi
        if [[ "$answer" =~ ^[Nn]$ ]]; then info "Skipping package installation."; return; fi
        warn "Invalid choice. Enter y, n or S."
    done
}

# ---------- Docker ----------
configure_docker() {
    while true; do
        echo -e "\n${CYAN}🐳 Docker installation${NC}"
        read -r -p $'🔹 Install Docker? (y/n) [default: y, S=skip]: ' install_docker; install_docker="${install_docker:-y}"
        if is_skip "$install_docker"; then info "Skipping Docker."; return; fi
        if [[ "$install_docker" =~ ^[Yy]$ ]]; then
            if command -v docker >/dev/null 2>&1; then ok "Docker already installed: $(docker --version)"; else curl -fsSL https://get.docker.com | sh; systemctl enable --now docker; [[ -n "${SUDO_USER:-}" ]] && usermod -aG docker "$SUDO_USER"; ok "Docker installed: $(docker --version)"; fi
            return
        elif [[ "$install_docker" =~ ^[Nn]$ ]]; then info "Skipping Docker."; return
        else warn "Invalid choice. Enter y, n or S."; fi
    done
}

# ---------- Release upgrade ----------
get_debian_target() {
    case "$OS_CODENAME" in
        bullseye) echo "bookworm";;
        bookworm) echo "trixie";;
        *) echo "";;
    esac
}
prepare_debian_release_sources() {
    local target="$1" mirror backup file
    get_selected_mirror; mirror="${SELECTED_MIRROR:-https://deb.debian.org/debian}"; mirror="${mirror%/}"
    backup="$(backup_apt_sources)"; info "APT sources backup: $backup"; mkdir -p /etc/apt/sources.list.d
    # Disable existing Debian archive source files; third-party sources remain for manual review.
    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -e "$file" ]] || continue; [[ "$file" == "/etc/apt/sources.list.d/junk-debian.sources" ]] && continue
        if grep -qiE 'https?://[^[:space:]]*(debian\.org/debian|debian\.petiak\.ir/debian|famaserver\.com/debian|pardisco\.co/debian|arvancloud\.ir/debian|iranserver\.com/debian|aminidc\.com/debian)' "$file" 2>/dev/null; then
            mv "$file" "$file.pre-upgrade.$(date +%Y%m%d-%H%M%S)"
        fi
    done
    cat > /etc/apt/sources.list.d/junk-debian.sources <<SRC_EOF
Types: deb
URIs: $mirror
Suites: $target $target-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: $target-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SRC_EOF
    save_selected_mirror "$mirror"; ok "Debian APT sources prepared for $target using $mirror."
}
upgrade_debian_one_release() {
    local target="$1"
    warn "This will upgrade Debian $OS_CODENAME → $target."; warn "Only one Debian major release is upgraded per run."
    while true; do
        read -r -p "Type UPGRADE to continue (or S to skip): " confirm
        if [[ "$confirm" == "UPGRADE" ]]; then break; fi
        if is_skip "$confirm"; then info "Upgrade skipped."; return; fi
        warn "Invalid confirmation. Type UPGRADE or S."
    done
    apt-get update; apt-get upgrade -y; apt-get full-upgrade -y
    prepare_debian_release_sources "$target"
    apt-get update; apt-get full-upgrade -y; apt-get autoremove -y
    ok "Debian $OS_CODENAME → $target upgrade step completed."
    warn "Reboot before running setup.sh again for the next major release."
}
upgrade_release() {
    echo -e "\n${CYAN}⬆️ Distribution release upgrade${NC}"; echo "This is separate from normal package upgrades."; echo
    if [[ "$OS_ID" == "debian" ]]; then
        local target="$(get_debian_target)"
        if [[ -z "$target" ]]; then
            [[ "$OS_CODENAME" == "trixie" ]] && ok "Debian 13 (trixie) is current stable." || warn "Automatic upgrade is not configured for '$OS_CODENAME'."
            return
        fi
        upgrade_debian_one_release "$target"
    else
        if ! command -v do-release-upgrade >/dev/null 2>&1; then apt-get update; apt-get install -y update-manager-core; fi
        warn "Ubuntu release upgrades are handled by do-release-upgrade."
        warn "The upgrader manages the supported release path and may disable third-party repositories."
        while true; do
            read -r -p "Start do-release-upgrade now? (y/N, S=skip): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then break; fi
            if [[ -z "$confirm" || "$confirm" =~ ^[Nn]$ ]] || is_skip "$confirm"; then info "Upgrade cancelled."; return; fi
            warn "Invalid choice. Enter y, n or S."
        done
        do-release-upgrade
    fi
}

# ---------- Main ----------
require_root
detect_os
clear
show_system_info
echo
while true; do
    read -r -p $'🔹 Continue with setup? (Y/n): ' continue_setup; continue_setup="${continue_setup:-y}"
    if [[ "$continue_setup" =~ ^[Yy]$ ]]; then break; elif [[ "$continue_setup" =~ ^[Nn]$ ]]; then exit 0; else warn "Invalid choice. Enter y or n."; fi
done
configure_bbr
configure_ipv6
configure_swap
configure_mirror
configure_dns
configure_time
update_system
install_packages
configure_docker
echo
while true; do
    read -r -p $'🔹 Check for a major OS upgrade? (y/N, S=skip): ' do_upgrade; do_upgrade="${do_upgrade:-n}"
    if is_skip "$do_upgrade" || [[ "$do_upgrade" =~ ^[Nn]$ ]]; then info "Skipping major OS upgrade."; break
    elif [[ "$do_upgrade" =~ ^[Yy]$ ]]; then upgrade_release; break
    else warn "Invalid choice. Enter y, n or S."; fi
done

echo -e "\n${CYAN}🧹 Cleaning up...${NC}"
while true; do
    read -r -p $'🔹 Run apt autoremove/clean? (Y/n, S=skip): ' cleanup; cleanup="${cleanup:-y}"
    if is_skip "$cleanup" || [[ "$cleanup" =~ ^[Nn]$ ]]; then info "Skipping cleanup."; break
    elif [[ "$cleanup" =~ ^[Yy]$ ]]; then apt-get autoremove -y; apt-get clean; break
    else warn "Invalid choice. Enter y, n or S."; fi
done
echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════╗"
echo "║                    🎉 Setup Complete!                   ║"
echo "╚══════════════════════════════════════════════════════════╝${NC}"
get_swap_info; get_cc; get_ipv6_status; get_timezone; get_dns; get_apt_status; get_docker_status
echo -e "${BOLD}Final status:${NC}"
echo "  OS              : $OS_NAME"
echo "  Timezone        : $CURRENT_TZ"
echo "  Time sync       : $(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo unknown)"
echo "  TCP congestion  : $CURRENT_CC"
echo "  Default qdisc   : $CURRENT_QDISC"
echo "  IPv6 disabled   : $IPV6_DISABLED"
echo "  DNS             : $DNS_SERVERS"
echo "  Swap            : ${SWAP_SIZE} (${SWAP_NAME})"
echo "  Upgradable      : $APT_UPGRADABLE package(s)"
echo "  Docker          : $DOCKER_STATUS"
[[ -f /var/run/reboot-required ]] && warn "A reboot is required." || warn "A reboot is recommended after kernel/network changes."
