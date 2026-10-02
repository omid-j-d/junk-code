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
JUNK_CONF="/etc/junk-setup.conf"
GEO_COUNTRY_CODE=""
GEO_COUNTRY_NAME=""

# ---------- helpers ----------

die() { echo -e "${RED}✗ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ $*${NC}"; }
ok() { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }

# Force all network operations initiated by this script to use IPv4.
# This does not disable IPv6 on the server.
APT_IPV4_CONF="/etc/apt/apt.conf.d/99-junk-force-ipv4"
curl4() { curl -4 "$@"; }
apt4() { apt-get -o Acquire::ForceIPv4=true "$@"; }
apt4_query() { apt -o Acquire::ForceIPv4=true "$@"; }
ensure_ipv4_apt() {
    printf '%s\n' 'Acquire::ForceIPv4 "true";' > "$APT_IPV4_CONF"
}

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
    APT_UPGRADABLE="$(apt4_query list --upgradable 2>/dev/null | awk 'NR>1 && /\//{n++} END{print n+0}')"
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
        # Ubuntu's release upgrader can return a non-zero status even when
        # its diagnostic output is useful. Do not use the exit code alone.
        if ! command -v do-release-upgrade >/dev/null 2>&1; then
            UPGRADE_PATH="Ubuntu upgrader not installed yet"
        else
            local check_output available_line current_prompt
            check_output="$(mktemp)"
            current_prompt="$(awk -F= '/^[[:space:]]*Prompt=/{print $2}' /etc/update-manager/release-upgrades 2>/dev/null | tr -d '[:space:]' || true)"

            # Refresh package metadata first; the upgrader itself is then
            # asked to check the supported release path.
            apt4 update >/dev/null 2>&1 || true
            do-release-upgrade --check-dist-upgrade-only >"$check_output" 2>&1 || true

            available_line="$(grep -Eio "New release '[^']+' available|New release [^ ]+ available|new release.*available" "$check_output" | head -n1 || true)"
            if [[ -n "$available_line" ]]; then
                UPGRADE_PATH="$available_line"
            elif grep -qiE 'No new release found|No new release|There are no.*release|already the newest' "$check_output"; then
                UPGRADE_PATH="No newer supported Ubuntu release currently reported"
            elif [[ "$current_prompt" == "never" ]]; then
                UPGRADE_PATH="Disabled by /etc/update-manager/release-upgrades (Prompt=never)"
            else
                UPGRADE_PATH="Upgrade check inconclusive — run 'do-release-upgrade -c' manually"
            fi
            rm -f "$check_output"
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

# Discover the server country from its public IPv4. This is used only to
# add country-local mirror candidates; mirror selection still depends on the
# real IPv4 throughput benchmark.
detect_public_country() {
    local public_ip="" response code name
    GEO_COUNTRY_CODE=""
    GEO_COUNTRY_NAME=""

    # IPv4-only public address discovery. Try more than one endpoint so a
    # single blocked/rate-limited service cannot break dynamic mirror discovery.
    for endpoint in \
        "https://api.ipify.org" \
        "https://ipv4.icanhazip.com" \
        "https://ifconfig.me/ip"; do
        public_ip="$(curl4 -fsSL --max-time 6 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ "$public_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            break
        fi
        public_ip=""
    done
    [[ -n "$public_ip" ]] || return 1

    # API 1: ipapi.co — plain country endpoint, no JSON parser required.
    code="$(curl4 -fsSL --max-time 7 "https://ipapi.co/$public_ip/country/" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$code" =~ ^[A-Za-z]{2}$ ]]; then
        GEO_COUNTRY_CODE="${code^^}"
        name="$(curl4 -fsSL --max-time 7 "https://ipapi.co/$public_ip/country_name/" 2>/dev/null | tr -d '\r' | sed 's/[[:space:]]*$//' || true)"
        GEO_COUNTRY_NAME="$name"
    fi

    # API 2: ipwho.is — useful fallback when ipapi is blocked/rate-limited.
    if [[ -z "$GEO_COUNTRY_CODE" ]]; then
        response="$(curl4 -fsSL --max-time 8 "https://ipwho.is/$public_ip" 2>/dev/null || true)"
        GEO_COUNTRY_CODE="$(printf '%s' "$response" | sed -n 's/.*"country_code"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]\)".*/\1/p' | head -n1 | tr '[:lower:]' '[:upper:]')"
        GEO_COUNTRY_NAME="$(printf '%s' "$response" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    fi

    # API 3: ipinfo.io — tokenless lookup as a final fallback.
    if [[ -z "$GEO_COUNTRY_CODE" ]]; then
        response="$(curl4 -fsSL --max-time 8 "https://ipinfo.io/$public_ip/json" 2>/dev/null || true)"
        GEO_COUNTRY_CODE="$(printf '%s' "$response" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]\)".*/\1/p' | head -n1 | tr '[:lower:]' '[:upper:]')"
        GEO_COUNTRY_NAME="$(printf '%s' "$response" | sed -n 's/.*"country_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    fi

    [[ "$GEO_COUNTRY_CODE" =~ ^[A-Z]{2}$ ]] || return 1
    [[ -n "$GEO_COUNTRY_NAME" ]] || GEO_COUNTRY_NAME="$GEO_COUNTRY_CODE"
    return 0
}

# Debian publishes the authoritative complete mirror list. Extract the
# package mirrors belonging to the detected country from that live list.
discover_debian_country_mirrors() {
    local country="$1" html text
    [[ -n "$country" ]] || return 0

    html="$(curl4 -fsSL --max-time 20 https://www.debian.org/mirror/list-full 2>/dev/null || true)"
    [[ -n "$html" ]] || return 0

    text="$(printf '%s\n' "$html" |
        sed -E \
          -e 's#<h3[^>]*>#\n@@COUNTRY@@ #g' \
          -e 's#</h3>#\n#g' \
          -e 's#</p>#\n#g' \
          -e 's#</li>#\n#g' \
          -e 's#<br[[:space:]]*/?>#\n#g' \
          -e 's#<[^>]+>##g' \
          -e 's/\&amp;/\&/g' \
          -e 's/\&nbsp;/ /g' |
        sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

    printf '%s\n' "$text" | awk -v wanted="$country" '
        function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
        /^@@COUNTRY@@ / {
            current=trim(substr($0,13))
            active=(current == wanted)
            site=""
            next
        }
        !active { next }
        /^Site:[[:space:]]*/ {
            site=trim(substr($0,6))
            next
        }
        /^Packages over HTTP:[[:space:]]*/ {
            path=trim(substr($0,20))
            if (site != "" && path != "") {
                if (path !~ /^\//) path="/" path
                printf "%s|http://%s%s\n", site, site, path
            }
            site=""
            next
        }
    ' | sort -u
}

# Debian's official country alias, e.g. ftp.de.debian.org. We validate it
# before using it, so a syntactically possible but nonexistent alias is ignored.
debian_country_alias() {
    local code="${1^^}" cc
    cc="$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')"
    [[ "$cc" =~ ^[a-z]{2}$ ]] || return 1
    printf 'https://ftp.%s.debian.org/debian\n' "$cc"
}

validate_debian_mirror() {
    local url="${1%/}" arch="${2:-amd64}" suite="${3:-$OS_CODENAME}"
    curl4 -fsSI --max-time 8 --connect-timeout 4 "$url/dists/$suite/Release" >/dev/null 2>&1 || \
    curl4 -fsSL --max-time 8 --connect-timeout 4 -o /dev/null "$url/dists/$suite/main/binary-$arch/Packages.xz" >/dev/null 2>&1
}

ubuntu_country_alias() {
    local code="${1^^}" cc
    cc="$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')"
    [[ "$cc" =~ ^[a-z]{2}$ ]] || return 1
    printf 'https://%s.archive.ubuntu.com/ubuntu\n' "$cc"
}

# Ubuntu exposes the best official archive mirrors for a country through
# Launchpad. The result can include several mirrors in the country (or the
# country's continent plus the primary mirror when the country has none).
discover_ubuntu_country_mirrors() {
    local code="$1" country_url json obj url
    [[ -n "$code" ]] || return 0
    code="${code^^}"
    country_url="https://api.launchpad.net/devel/+countries/${code}"

    json="$(curl4 -fsSL --max-time 15 --get \
        --data-urlencode "ws.op=getBestMirrorsForCountry" \
        --data-urlencode "country=${country_url}" \
        --data-urlencode "mirror_type=Archive" \
        https://api.launchpad.net/devel/ubuntu 2>/dev/null || true)"
    [[ -n "$json" ]] || return 0

    # Launchpad deliberately returns continent/global fallbacks when a country
    # has no local mirror.  We do NOT want those here: only mirrors whose
    # country_link exactly matches the detected country are accepted.
    # Split the JSON collection into mirror objects. This avoids requiring jq
    # during the early mirror-selection phase.
    printf '%s' "$json" | sed 's/},{/}\n{/g' | while IFS= read -r obj; do
        [[ "$obj" == *"country_link"*"${country_url}"* ]] || continue

        url="$(printf '%s' "$obj" | sed -n 's/.*"https_base_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        [[ -n "$url" ]] || url="$(printf '%s' "$obj" | sed -n 's/.*"http_base_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        [[ -n "$url" ]] || continue
        printf 'Local - %s|%s\n' "${url%/}" "${url%/}"
    done | sort -u
}

add_country_mirrors() {
    local -n _arr="$1"
    local line host item existing arch alias duplicate
    local -a country_lines=()

    if ! detect_public_country; then
        warn "Could not detect server country; skipping dynamic local mirrors."
        return 0
    fi
    info "Detected public IP country: ${GEO_COUNTRY_NAME} (${GEO_COUNTRY_CODE})"
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

    # 1) Official mirrors registered in the exact detected country.
    if [[ "$OS_ID" == "debian" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            host="${line%%|*}"
            item="${line#*|}"
            if validate_debian_mirror "$item" "$arch" "$OS_CODENAME"; then
                country_lines+=("${GEO_COUNTRY_NAME} - ${host}|${item}")
            fi
        done < <(discover_debian_country_mirrors "$GEO_COUNTRY_NAME")
    else
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            host="${line%%|*}"
            item="${line#*|}"
            if curl4 -fsSI --max-time 8 --connect-timeout 4 "$item/dists/$OS_CODENAME/Release" >/dev/null 2>&1; then
                country_lines+=("${GEO_COUNTRY_NAME} - ${host}|${item}")
            fi
        done < <(discover_ubuntu_country_mirrors "$GEO_COUNTRY_CODE")
    fi

    # 2) Always expose the official country mirror as a distinct choice.
    # It is intentionally shown even if the alias was not discovered/validated;
    # the user can choose it and the normal APT validation will decide whether
    # it is usable.
    if [[ "$OS_ID" == "debian" ]]; then
        if alias="$(debian_country_alias "$GEO_COUNTRY_CODE" 2>/dev/null)"; then
            country_lines+=("${GEO_COUNTRY_NAME} - Official country mirror|${alias}")
        fi
    else
        if alias="$(ubuntu_country_alias "$GEO_COUNTRY_CODE" 2>/dev/null)"; then
            country_lines+=("${GEO_COUNTRY_NAME} - Official country archive|${alias}")
        fi
    fi

    # 3) Iran keeps the requested curated mirrors as fallback candidates, but
    # they are no longer a special-case replacement for the country's own
    # official mirrors.
    if [[ "$GEO_COUNTRY_CODE" == "IR" ]]; then
        if [[ "$OS_ID" == "debian" ]]; then
            country_lines+=(
                "Iran - Liara|https://linux-mirror.liara.ir/repository/debian"
                "Iran - ParsPack|https://debian.parspack.com/debian"
                "Iran - Runflare|http://mirror-linux.runflare.com/debian"
            )
        else
            country_lines+=(
                "Iran - Liara|https://linux-mirror.liara.ir/repository/ubuntu"
                "Iran - ParsPack|https://ubuntu.parspack.com/ubuntu"
                "Iran - Runflare|http://mirror-linux.runflare.com/ubuntu"
            )
        fi
    fi

    # 4) Always expose the official primary archive/CDN as a distinct choice.
    if [[ "$OS_ID" == "debian" ]]; then
        country_lines+=("Debian official primary CDN|https://deb.debian.org/debian")
    else
        country_lines+=("Ubuntu official primary archive|https://archive.ubuntu.com/ubuntu")
    fi

    # Deduplicate by URL while preserving order.
    for line in "${country_lines[@]}"; do
        host="${line#*|}"
        [[ -n "$host" ]] || continue
        duplicate=0
        for item in "${_arr[@]}"; do
            existing="${item#*|}"
            if [[ "${existing%/}" == "${host%/}" ]]; then
                duplicate=1
                break
            fi
        done
        ((duplicate == 0)) && _arr+=("$line")
    done

    if ((${#country_lines[@]} > 0)); then
        ok "Added ${#country_lines[@]} ${OS_ID^} mirror candidate(s) for ${GEO_COUNTRY_NAME}."
    else
        warn "No mirror candidates could be built for ${GEO_COUNTRY_NAME}."
    fi
}

# ---------- Mirrors ----------
# Download a real Packages index over IPv4 and report throughput in MB/s.
# For Ubuntu, $repo is the archive base. For Debian, security uses a separate
# /debian-security tree and is benchmarked separately when requested.
mirror_test() {
    local url="$1" codename="$2" arch="$3" distro="${4:-$OS_ID}" kind="${5:-main}" speed path
    url="${url%/}"
    if [[ "$distro" == "ubuntu" ]]; then
        path="dists/$codename/main/binary-$arch/Packages.xz"
    else
        if [[ "$kind" == "security" ]]; then
            path="dists/${codename}-security/main/binary-$arch/Packages.xz"
        else
            path="dists/$codename/main/binary-$arch/Packages.xz"
        fi
    fi
    speed="$(curl4 -fsSL --max-time 15 --connect-timeout 5 -o /dev/null \
        -w '%{speed_download}' "$url/$path" 2>/dev/null || true)"
    [[ "$speed" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v bps="$speed" 'BEGIN { printf "%.2f", bps/1048576 }'
}

get_selected_mirror() {
    SELECTED_MIRROR=""
    SELECTED_SECURITY_MIRROR=""
    SECURITY_MODE="official"
    if [[ -f "$JUNK_CONF" ]]; then
        # shellcheck disable=SC1090
        source "$JUNK_CONF" 2>/dev/null || true
    fi
    SELECTED_MIRROR="${JUNK_MIRROR:-}"
    SELECTED_SECURITY_MIRROR="${JUNK_SECURITY_MIRROR:-}"
    SECURITY_MODE="${JUNK_SECURITY_MODE:-official}"
}
save_selected_mirror() {
    local mirror="$1"
    printf 'JUNK_MIRROR=%q\n' "$mirror" > "$JUNK_CONF"
    [[ -n "${SELECTED_SECURITY_MIRROR:-}" ]] && printf 'JUNK_SECURITY_MIRROR=%q\n' "$SELECTED_SECURITY_MIRROR" >> "$JUNK_CONF"
    printf 'JUNK_SECURITY_MODE=%q\n' "${SECURITY_MODE:-official}" >> "$JUNK_CONF"
}

replace_urls_in_sources() {
    local old_pattern="$1" new_url="$2" file
    while IFS= read -r -d '' file; do
        sed -i -E "s#https?://$old_pattern#${new_url}#g" "$file" || true
    done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) -print0)
}

set_debian_mirror() {
    local mirror="$1" file tmp
    mirror="${mirror%/}"

    while IFS= read -r -d '' file; do
        case "$file" in
            *.list)
                # Change ONLY the URI on Debian archive/release lines.
                # Preserve suites, components, options and Signed-By exactly.
                # Do not touch unrelated repositories (for example Docker).
                sed -i -E \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}([[:space:]]|$)/ { s#https?://[^[:space:]]+#${mirror}#; }" \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}-updates([[:space:]]|$)/ { s#https?://[^[:space:]]+#${mirror}#; }" \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+\[[^]]*\][[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}([[:space:]]|$)/ s#https?://[^[:space:]]+#${mirror}#" \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+\[[^]]*\][[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}-updates([[:space:]]|$)/ s#https?://[^[:space:]]+#${mirror}#" \
                    "$file" || true
                ;;
            *.sources)
                # Deb822: modify ONLY the URIs field in matching non-security
                # stanzas. Every other field is preserved byte-for-byte.
                tmp="${file}.junk-main.$$"
                awk -v newurl="$mirror" -v codename="$OS_CODENAME" '
                    BEGIN { RS=""; ORS="\n\n" }
                    {
                        n=split($0, lines, "\n")
                        suites=""
                        for (i=1; i<=n; i++) {
                            if (lines[i] ~ /^[[:space:]]*Suites:[[:space:]]*/) {
                                suites=lines[i]
                                sub(/^[[:space:]]*Suites:[[:space:]]*/, "", suites)
                                break
                            }
                        }
                        ismain = (suites ~ "(^|[[:space:]])" codename "([[:space:]]|$)" || suites ~ "(^|[[:space:]])" codename "-updates([[:space:]]|$)")
                        issecurity = (suites ~ "(^|[[:space:]])" codename "-security([[:space:]]|$)")
                        if (ismain && !issecurity) {
                            for (i=1; i<=n; i++) {
                                if (lines[i] ~ /^[[:space:]]*URIs:[[:space:]]*/) lines[i]="URIs: " newurl
                            }
                        }
                        for (i=1; i<=n; i++) print lines[i]
                    }
                ' "$file" > "$tmp" && mv "$tmp" "$file" || rm -f "$tmp"
                ;;
        esac
    done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) -print0)

    save_selected_mirror "$mirror"
    ok "Debian mirror changed to $mirror"
}

set_ubuntu_mirror() {
    local mirror="$1" file tmp
    mirror="${mirror%/}"

    while IFS= read -r -d '' file; do
        case "$file" in
            *.list)
                # Change ONLY the URI on Ubuntu archive/release lines.
                # Preserve suites, components and repository options.
                sed -i -E \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}([[:space:]]|$)/ s#https?://[^[:space:]]+#${mirror}#" \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}-updates([[:space:]]|$)/ s#https?://[^[:space:]]+#${mirror}#" \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+\[[^]]*\][[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}([[:space:]]|$)/ s#https?://[^[:space:]]+#${mirror}#" \
                    -e "/^[[:space:]]*(deb|deb-src)[[:space:]]+\[[^]]*\][[:space:]]+https?:\/\/[^[:space:]]+[[:space:]]+${OS_CODENAME}-updates([[:space:]]|$)/ s#https?://[^[:space:]]+#${mirror}#" \
                    "$file" || true
                ;;
            *.sources)
                tmp="${file}.junk-main.$$"
                awk -v newurl="$mirror" -v codename="$OS_CODENAME" '
                    BEGIN { RS=""; ORS="\n\n" }
                    {
                        n=split($0, lines, "\n")
                        suites=""
                        for (i=1; i<=n; i++) {
                            if (lines[i] ~ /^[[:space:]]*Suites:[[:space:]]*/) {
                                suites=lines[i]
                                sub(/^[[:space:]]*Suites:[[:space:]]*/, "", suites)
                                break
                            }
                        }
                        ismain = (suites ~ "(^|[[:space:]])" codename "([[:space:]]|$)" || suites ~ "(^|[[:space:]])" codename "-updates([[:space:]]|$)")
                        issecurity = (suites ~ "(^|[[:space:]])" codename "-security([[:space:]]|$)")
                        if (ismain && !issecurity) {
                            for (i=1; i<=n; i++) {
                                if (lines[i] ~ /^[[:space:]]*URIs:[[:space:]]*/) lines[i]="URIs: " newurl
                            }
                        }
                        for (i=1; i<=n; i++) print lines[i]
                    }
                ' "$file" > "$tmp" && mv "$tmp" "$file" || rm -f "$tmp"
                ;;
        esac
    done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) -print0)

    save_selected_mirror "$mirror"
    ok "Ubuntu mirror changed to $mirror"
}

# Configure security separately from the main archive. The user can keep the
# official security service or use the selected mirror when it actually hosts
# the matching security tree. If it does not, we automatically fall back to
# the official security service.
replace_security_sources() {
    local new_url="$1" file tmp
    new_url="${new_url%/}"
    while IFS= read -r -d '' file; do
        case "$file" in
            *.list)
                # One-line APT entries: only rewrite lines that actually target
                # a security suite, never ordinary archive repositories.
                sed -i -E "/(^|[[:space:]])[[:alnum:]_.:-]+-security([[:space:]]|$)/ s#https?://[^[:space:]#]+#${new_url}#g" "$file" || true
                ;;
            *.sources)
                # Deb822 source stanzas: rewrite URI only inside stanzas whose
                # Suites field contains a security suite.
                tmp="${file}.junk-security.$$"
                awk -v newurl="$new_url" '
                    BEGIN { RS=""; ORS="\n\n" }
                    {
                        block=$0
                        if (block ~ /(^|\n)[[:space:]]*Suites:[^\n]*-security([[:space:]]|$)/) {
                            gsub(/(^|\n)[[:space:]]*URIs:[[:space:]]*[^[:space:]]+/, "\\1URIs: " newurl, block)
                        }
                        print block
                    }
                ' "$file" > "$tmp" && mv "$tmp" "$file" || rm -f "$tmp"
                ;;
        esac
    done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) -print0)
}

set_debian_security() {
    local security_url="$1"
    security_url="${security_url%/}"
    replace_security_sources "$security_url"
    SELECTED_SECURITY_MIRROR="$security_url"
    SECURITY_MODE="mirror"
    save_selected_mirror "${SELECTED_MIRROR:-https://deb.debian.org/debian}"
    ok "Debian security mirror changed to $security_url"
}

set_ubuntu_security() {
    local security_url="$1"
    security_url="${security_url%/}"
    replace_security_sources "$security_url"
    replace_urls_in_sources 'security\.ubuntu\.com/ubuntu' "$security_url"
    replace_urls_in_sources 'linux-mirror\.liara\.ir/repository/ubuntu-security' "$security_url"
    SELECTED_SECURITY_MIRROR="$security_url"
    SECURITY_MODE="mirror"
    save_selected_mirror "${SELECTED_MIRROR:-https://archive.ubuntu.com/ubuntu}"
    ok "Ubuntu security mirror changed to $security_url"
}

configure_security_mirror() {
    local base="$1" security_url speed arch answer
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    echo -e "\n${CYAN}🔐 Security repository${NC}"
    if [[ "$OS_ID" == "debian" ]]; then
        echo "  1) Official Debian security"
        echo "  2) Use selected mirror if its security repository is available"
        echo "  S) Skip this stage"
        while true; do
            read -r -p $'🔹 Choice [1]: ' answer; answer="${answer:-1}"
            case "$answer" in
                1|[Ss]|[Ss][Kk][Ii][Pp])
                    if [[ "$answer" == "1" ]]; then
                        security_url="https://security.debian.org/debian-security"
                        replace_security_sources "$security_url"
                        SELECTED_SECURITY_MIRROR="$security_url"; SECURITY_MODE="official"
                        save_selected_mirror "$base"; ok "Using official Debian security repository."
                    else info "Skipping security repository configuration."; fi
                    return ;;
                2)
                    if [[ "$base" == *"/debian" ]]; then
                        security_url="${base%/debian}/debian-security"
                    else
                        security_url="${base%/}/debian-security"
                    fi
                    # Liara follows repository/debian-security; ParsPack's
                    # security tree is accepted only if the benchmark succeeds.
                    if speed="$(mirror_test "$security_url" "$OS_CODENAME" "$arch" "$OS_ID" security)"; then
                        info "Selected mirror security repository: $security_url (${speed} MB/s)"
                        set_debian_security "$security_url"; return
                    fi
                    warn "Selected mirror does not provide a usable Debian security repository."
                    warn "Falling back to official Debian security."
                    security_url="https://security.debian.org/debian-security"
                    replace_security_sources "$security_url"
                    SELECTED_SECURITY_MIRROR="$security_url"; SECURITY_MODE="official"
                    save_selected_mirror "$base"; ok "Using official Debian security repository."; return ;;
                *) warn "Invalid choice. Enter 1, 2 or S.";;
            esac
        done
    else
        echo "  1) Official Ubuntu security"
        echo "  2) Use selected mirror if its security repository is available"
        echo "  S) Skip this stage"
        while true; do
            read -r -p $'🔹 Choice [1]: ' answer; answer="${answer:-1}"
            case "$answer" in
                1|[Ss]|[Ss][Kk][Ii][Pp])
                    if [[ "$answer" == "1" ]]; then
                        security_url="https://security.ubuntu.com/ubuntu"
                        replace_urls_in_sources 'security\.ubuntu\.com/ubuntu' "$security_url"
                        SELECTED_SECURITY_MIRROR="$security_url"; SECURITY_MODE="official"
                        save_selected_mirror "$base"; ok "Using official Ubuntu security repository."
                    else info "Skipping security repository configuration."; fi
                    return ;;
                2)
                    if [[ "$base" == *"linux-mirror.liara.ir/repository/ubuntu"* ]]; then
                        security_url="https://linux-mirror.liara.ir/repository/ubuntu-security"
                    elif [[ "$base" == *"mirror-linux.runflare.com/ubuntu"* ]]; then
                        security_url="$base"
                    elif [[ "$base" == *"ubuntu.parspack.com/ubuntu"* ]]; then
                        security_url="$base"
                    else
                        security_url="$base"
                    fi
                    if [[ "$security_url" == "$base" ]]; then
                        # Ubuntu mirrors commonly expose -security as a suite
                        # under the same archive tree; test the selected base.
                        speed="$(mirror_test "$security_url" "$OS_CODENAME-security" "$arch" "$OS_ID" main 2>/dev/null || true)"
                    else
                        speed="$(mirror_test "$security_url" "$OS_CODENAME" "$arch" "$OS_ID" security 2>/dev/null || true)"
                    fi
                    if [[ -n "$speed" ]]; then
                        info "Selected mirror security repository: $security_url (${speed} MB/s)"
                        set_ubuntu_security "$security_url"; return
                    fi
                    warn "Selected mirror does not provide a usable Ubuntu security repository."
                    warn "Falling back to official Ubuntu security."
                    security_url="https://security.ubuntu.com/ubuntu"
                    replace_urls_in_sources 'security\.ubuntu\.com/ubuntu' "$security_url"
                    SELECTED_SECURITY_MIRROR="$security_url"; SECURITY_MODE="official"
                    save_selected_mirror "$base"; ok "Using official Ubuntu security repository."; return ;;
                *) warn "Invalid choice. Enter 1, 2 or S.";;
            esac
        done
    fi
}

configure_mirror() {
    while true; do
        echo -e "\n${CYAN}🌐 APT mirror${NC}"; get_selected_mirror
        [[ -n "$SELECTED_MIRROR" ]] && echo "Saved mirror: $SELECTED_MIRROR"
        [[ -n "$SELECTED_SECURITY_MIRROR" ]] && echo "Security mirror: $SELECTED_SECURITY_MIRROR ($SECURITY_MODE)"
        local candidates=()
        add_country_mirrors candidates

        if ((${#candidates[@]} == 0)); then
            warn "No official local mirror was discovered for ${GEO_COUNTRY_NAME:-the detected country}."
            echo "  C) Custom mirror URL"
            echo "  S) Skip this stage"
        else
            echo "  0) Keep current"
            local i=1 item name url choice
            for item in "${candidates[@]}"; do
                name="${item%%|*}"
                url="${item#*|}"
                echo "  $i) $name - $url"
                ((i+=1))
            done
            echo "  T) Benchmark all local mirrors (download speed)"
            echo "  A) Automatically select fastest local mirror"
            echo "  C) Custom mirror URL"
            echo "  S) Skip this stage"
        fi
        read -r -p $'🔹 Choice [0]: ' choice; choice="${choice:-0}"

        if is_skip "$choice"; then info "Skipping mirror configuration."; return; fi
        if [[ "$choice" == "0" ]]; then info "Keeping current mirror configuration."; return; fi

        if [[ "$choice" =~ ^[TtAa]$ ]]; then
            local best_url="" best_speed=0 speed arch
            arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
            echo; echo "Testing IPv4 download throughput for $OS_CODENAME/$arch..."
            printf '%-42s %12s\n' "Mirror" "Speed"
            printf '%-42s %12s\n' "------------------------------------------" "------------"
            for item in "${candidates[@]}"; do
                name="${item%%|*}"; url="${item#*|}"; printf '%-42s ' "$name"
                if speed="$(mirror_test "$url" "$OS_CODENAME" "$arch" "$OS_ID" main)"; then
                    echo "${speed} MB/s"
                    if awk -v a="$speed" -v b="$best_speed" 'BEGIN{exit !(a>b)}'; then best_speed="$speed"; best_url="$url"; fi
                else echo "unreachable / unsupported"; fi
            done
            if [[ -z "$best_url" ]]; then warn "No working mirror passed the benchmark."; continue; fi
            echo; info "Fastest tested mirror: $best_url (${best_speed} MB/s)"
            if [[ "$choice" =~ ^[Aa]$ ]]; then
                [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$best_url" || set_ubuntu_mirror "$best_url"
                configure_security_mirror "$best_url"; return
            fi
            read -r -p $'Use this fastest mirror? (Y/n, S=skip): ' use_best; use_best="${use_best:-y}"
            if is_skip "$use_best"; then info "Skipping mirror configuration."; return; fi
            if [[ "$use_best" =~ ^[Yy]$ ]]; then
                [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$best_url" || set_ubuntu_mirror "$best_url"
                configure_security_mirror "$best_url"; return
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
            warn "Invalid choice. Enter a listed number, T, A, C or S."; continue
        fi
        [[ "$OS_ID" == "debian" ]] && set_debian_mirror "$url" || set_ubuntu_mirror "$url"
        configure_security_mirror "$url"; return
    done
}

# ---------- DNS ----------
# Configure primary and secondary DNS providers independently.
configure_dns() {
    local DNS1="" DNS2="" DEFAULT_DNS1="" DEFAULT_DNS2=""

    valid_ipv4() {
        local ip="$1" octet
        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
        IFS=. read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            (( octet <= 255 )) || return 1
        done
    }

    # Get the first two DNS servers currently configured on the system.
    get_current_dns_pair() {
        local -a found=() x
        local value
        if command -v resolvectl >/dev/null 2>&1; then
            while read -r x; do
                valid_ipv4 "$x" && found+=("$x")
            done < <(resolvectl dns 2>/dev/null | awk '{for(i=2;i<=NF;i++) print $i}' | sort -u)
        fi
        if ((${#found[@]} == 0)); then
            while read -r value; do
                valid_ipv4 "$value" && found+=("$value")
            done < <(awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null)
        fi
        DEFAULT_DNS1="${found[0]:-}"
        DEFAULT_DNS2="${found[1]:-${found[0]:-}}"
    }

    choose_dns() {
        local role="$1" default_ip="$2" choice="" value=""
        while true; do
            echo
            echo "  ${role} DNS"
            echo "    1) Current/default DNS     ${default_ip:-Not detected}"
            echo "    2) Cloudflare              1.1.1.1"
            echo "    3) Google                  8.8.8.8"
            echo "    4) Quad9                   9.9.9.9"
            echo "    5) AdGuard                 94.140.14.14"
            echo "    6) Custom IPv4"
            echo "    S) Skip this stage"
            read -r -p "  Choice: " choice

            case "$choice" in
                1)
                    if [[ -n "$default_ip" ]]; then value="$default_ip"; else warn "No current/default DNS was detected."; continue; fi
                    ;;
                2) value="1.1.1.1";;
                3) value="8.8.8.8";;
                4) value="9.9.9.9";;
                5) value="94.140.14.14";;
                6)
                    while true; do
                        read -r -p "  ${role} DNS IPv4 (S=skip): " value
                        if is_skip "$value"; then return 10; fi
                        if valid_ipv4 "$value"; then break; fi
                        warn "Invalid IPv4 address. Try again."
                    done
                    ;;
                [Ss]|[Ss][Kk][Ii][Pp]) return 10;;
                *) warn "Invalid choice. Enter 1-6 or S."; continue;;
            esac
            SELECTED_DNS="$value"
            return 0
        done
    }

    echo -e "\n${CYAN}🧭 DNS configuration${NC}"
    get_dns
    get_current_dns_pair
    echo "Current DNS: $DNS_SERVERS"
    echo "Primary and secondary DNS are selected independently."

    choose_dns "Primary" "$DEFAULT_DNS1"
    local dns_status=$?
    if ((dns_status == 10)); then
        info "Skipping DNS configuration."
        return
    elif ((dns_status != 0)); then
        warn "DNS selection failed."
        return
    fi
    DNS1="$SELECTED_DNS"

    while true; do
        choose_dns "Secondary" "$DEFAULT_DNS2"
        dns_status=$?
        if ((dns_status == 10)); then
            info "Skipping DNS configuration."
            return
        elif ((dns_status != 0)); then
            warn "DNS selection failed."
            return
        fi
        DNS2="$SELECTED_DNS"
        if [[ "$DNS1" == "$DNS2" ]]; then
            warn "Secondary DNS must be different from Primary DNS."
            continue
        fi
        break
    done

    if systemctl is-active --quiet systemd-resolved 2>/dev/null && command -v resolvectl >/dev/null 2>&1; then
        if [[ -n "${DEFAULT_INTERFACE:-}" ]]; then
            resolvectl dns "$DEFAULT_INTERFACE" "$DNS1" "$DNS2" 2>/dev/null || true
        fi
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/99-junk-dns.conf <<DNS_EOF
[Resolve]
DNS=$DNS1 $DNS2
DNSStubListener=yes
DNS_EOF
        systemctl restart systemd-resolved
    else
        rm -f /etc/resolv.conf 2>/dev/null || true
        printf 'nameserver %s\nnameserver %s\n' "$DNS1" "$DNS2" > /etc/resolv.conf
        warn "NetworkManager/netplan may overwrite /etc/resolv.conf."
    fi

    ok "Primary DNS:   $DNS1"
    ok "Secondary DNS: $DNS2"
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
        public_ip="$(curl4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '\r\n' || true)"

        # 1) ipapi.co — the /timezone endpoint returns an IANA timezone as plain text.
        if [[ -n "$public_ip" ]]; then
            detected_tz="$(curl4 -fsSL --max-time 7 "https://ipapi.co/$public_ip/timezone/" 2>/dev/null | tr -d '\r\n' || true)"
            [[ "$detected_tz" == "Undefined" || "$detected_tz" == "null" ]] && detected_tz=""
        fi

        # 2) ipwho.is (JSON response).
        if [[ -z "$detected_tz" && -n "$public_ip" ]]; then
            detected_tz="$(curl4 -fsSL --max-time 7 "https://ipwho.is/$public_ip" 2>/dev/null | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*{[^}]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
        fi

        # 3) ipinfo.io (tokenless endpoint; may be unavailable in some regions).
        if [[ -z "$detected_tz" && -n "$public_ip" ]]; then
            detected_tz="$(curl4 -fsSL --max-time 7 "https://ipinfo.io/$public_ip/json" 2>/dev/null | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
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

# ---------- APT integrity / source repair ----------
repair_debian_sources() {
    [[ "$OS_ID" == "debian" ]] || return 0
    local file tmp changed=0

    # Repair malformed components left by older versions of this script.
    # Only the known truncated non-free-firmware token is changed; all other
    # source content is preserved byte-for-byte.
    while IFS= read -r -d '' file; do
        tmp="${file}.junk-repair.$$"
        if grep -qE 'non-free-firmw>' "$file" 2>/dev/null; then
            sed 's/non-free-firmw>/non-free-firmware/g' "$file" > "$tmp" && mv "$tmp" "$file" || rm -f "$tmp"
            ok "Repaired malformed Debian component in $file"
            changed=1
        fi
    done < <(find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -print0)

    # Repair malformed URI fields produced by older .sources rewriting logic.
    while IFS= read -r -d '' file; do
        tmp="${file}.junk-uri.$$"
        if grep -qE '^URIs:[[:space:]]*https?://[^[:space:]]+[<>]' "$file" 2>/dev/null; then
            sed -E 's#^(URIs:[[:space:]]*https?://[^[:space:]]+)[<>].*$#\1#' "$file" > "$tmp" && mv "$tmp" "$file" || rm -f "$tmp"
            ok "Repaired malformed URI in $file"
            changed=1
        fi
    done < <(find /etc/apt -type f -name '*.sources' -print0)

    return 0
}


# ---------- System updates / packages ----------
update_system() {
    while true; do
        echo -e "\n${CYAN}📦 System update${NC}"
        read -r -p $'🔹 Run apt update + upgrade? (Y/n, S=skip): ' answer; answer="${answer:-y}"
        if is_skip "$answer"; then info "Skipping system update."; return; fi
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            repair_debian_sources
            if ! apt4 update; then
                warn "APT update failed. No insecure GPG bypass will be attempted."
                return 1
            fi
            apt4 upgrade -y
            ok "System packages updated."; return
        fi
        if [[ "$answer" =~ ^[Nn]$ ]]; then info "Skipping system update."; return; fi
        warn "Invalid choice. Enter y, n or S."
    done
}
install_packages() {
    while true; do
        echo -e "\n${CYAN}🧰 Useful packages${NC}"
        read -r -p $'🔹 Install missing useful packages? (Y/n, S=skip): ' answer; answer="${answer:-y}"
        if is_skip "$answer"; then info "Skipping package installation."; return; fi
        if [[ "$answer" =~ ^[Yy]$ ]]; then apt4 install -y git sudo curl socat vnstat nload speedtest-cli snapd lsof unzip zip htop mtr btop ufw p7zip-full ca-certificates gnupg screen; ok "Useful packages installed."; return; fi
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
            if command -v docker >/dev/null 2>&1; then ok "Docker already installed: $(docker --version)"; else curl4 -fsSL https://get.docker.com | sh; systemctl enable --now docker; [[ -n "${SUDO_USER:-}" ]] && usermod -aG docker "$SUDO_USER"; ok "Docker installed: $(docker --version)"; fi
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
    local target="$1" mirror file
    get_selected_mirror; mirror="${SELECTED_MIRROR:-https://deb.debian.org/debian}"; mirror="${mirror%/}"
    mkdir -p /etc/apt/sources.list.d
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
    apt4 update; apt4 upgrade -y; apt4 full-upgrade -y
    prepare_debian_release_sources "$target"
    apt4 update; apt4 full-upgrade -y; apt4 autoremove -y
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
        if ! command -v do-release-upgrade >/dev/null 2>&1; then apt4 update; apt4 install -y update-manager-core; fi
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
ensure_ipv4_apt
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
    elif [[ "$cleanup" =~ ^[Yy]$ ]]; then apt4 autoremove -y; apt4 clean; break
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
