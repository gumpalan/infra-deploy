#!/usr/bin/env bash
# =============================================================================
# gumpalan — CLI helper untuk operasi sehari-hari di server
# Pasang: sudo cp gumpalan.sh /usr/local/bin/gumpalan && sudo chmod +x /usr/local/bin/gumpalan
# =============================================================================
set -euo pipefail

GUMPALAN_HOME="${HOME}/.gumpalan"
LOG_DIR="${GUMPALAN_HOME}/logs"
CONFIG_DIR="${GUMPALAN_HOME}/config"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}→${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}!${RESET} $*"; }
die()     { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }

usage() {
    cat <<EOF

${BOLD}gumpalan${RESET} — CLI helper Gumpalan Super App

${BOLD}PENGGUNAAN${RESET}
  gumpalan <perintah> [argumen]

${BOLD}PERINTAH UMUM${RESET}
  status                    Cek status semua service Gumpalan
  log <modul>               Ikuti log real-time (auth | iot)
  restart <modul>           Restart service (auth | iot | all)
  stop <modul>              Stop service
  config <modul>            Buka file .env di editor

${BOLD}AUTH — Manajemen Pengguna${RESET}
  auth user list            Daftar semua user terdaftar
  auth user show <id>       Detail satu user
  auth user delete <id>     Hapus user

${BOLD}IOT — Manajemen Perangkat${RESET}
  iot device list           Daftar semua perangkat IoT
  iot device show <id>      Detail perangkat + channel
  iot device add            Tambah perangkat baru (interaktif)
  iot device delete <id>    Hapus perangkat

${BOLD}IOT — Perizinan Perangkat${RESET}
  iot device approve <device_id>        Setujui perangkat pending
  iot device revoke  <device_id>        Cabut akses perangkat
  iot device perm list   <device_id>    Lihat daftar izin user di perangkat
  iot device perm grant  <device_id> <user_id>   Beri izin user ke perangkat
  iot device perm revoke <device_id> <user_id>   Cabut izin user

${BOLD}IOT — History Data${RESET}
  iot history sensor   <device_id> [channel_id]  Lihat log sensor terakhir
  iot history actuator <device_id> [channel_id]  Lihat log aktivasi aktuator

${BOLD}CONTOH${RESET}
  gumpalan status
  gumpalan log iot
  gumpalan iot device list
  gumpalan iot device approve esp32-living-room
  gumpalan iot device perm grant esp32-living-room usr_abc123
  gumpalan iot history sensor living-room-sensor temperature

EOF
    exit 0
}

# Baca port dari env file
get_port() {
    local mod="$1"
    local env_file="${CONFIG_DIR}/${mod}.env"
    [[ -f "$env_file" ]] && grep -E '^PORT=' "$env_file" | cut -d= -f2 | tr -d ' ' || echo ""
}

BASE_AUTH="http://127.0.0.1:$(get_port auth)"
BASE_IOT="http://127.0.0.1:$(get_port iot)"

# Ambil token CLI internal dari svc-auth (jika ada endpoint internal)
# Untuk sekarang: baca INTERNAL_TOKEN dari auth.env jika tersedia
get_internal_token() {
    local env_file="${CONFIG_DIR}/auth.env"
    [[ -f "$env_file" ]] && grep -E '^INTERNAL_CLI_TOKEN=' "$env_file" | cut -d= -f2 | tr -d ' ' || echo ""
}

INTERNAL_TOKEN="$(get_internal_token)"
AUTH_HEADER=""
[[ -n "$INTERNAL_TOKEN" ]] && AUTH_HEADER="Authorization: Bearer ${INTERNAL_TOKEN}"

call_api() {
    local method="$1" url="$2" data="${3:-}"
    local args=(-fsSL -X "$method")
    [[ -n "$AUTH_HEADER" ]] && args+=(-H "$AUTH_HEADER")
    args+=(-H "Content-Type: application/json")
    [[ -n "$data" ]] && args+=(-d "$data")
    curl "${args[@]}" "$url"
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
cmd_status() {
    echo -e "\n${BOLD}Status Service Gumpalan${RESET}\n"
    for svc in gumpalan-auth gumpalan-iot; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}●${RESET} ${svc}  ${GREEN}running${RESET}"
        elif systemctl list-unit-files --quiet "$svc.service" &>/dev/null; then
            echo -e "  ${RED}●${RESET} ${svc}  ${RED}stopped${RESET}"
        else
            echo -e "  ${YELLOW}○${RESET} ${svc}  ${YELLOW}not installed${RESET}"
        fi
    done
    echo
}

# ---------------------------------------------------------------------------
# log
# ---------------------------------------------------------------------------
cmd_log() {
    local mod="${1:-}"
    [[ -z "$mod" ]] && die "Tentukan modul: gumpalan log <auth|iot>"
    local log_file="${LOG_DIR}/${mod}.log"
    [[ -f "$log_file" ]] || die "Log tidak ditemukan: ${log_file}"
    info "Ikuti log ${mod} (Ctrl+C untuk berhenti)..."
    tail -f "$log_file"
}

# ---------------------------------------------------------------------------
# restart / stop
# ---------------------------------------------------------------------------
cmd_restart() {
    local mod="${1:-all}"
    if [[ "$mod" == "all" ]]; then
        sudo systemctl restart gumpalan-auth gumpalan-iot
        success "Semua service di-restart."
    else
        sudo systemctl restart "gumpalan-${mod}"
        success "gumpalan-${mod} di-restart."
    fi
}

cmd_stop() {
    local mod="${1:-}"
    [[ -z "$mod" ]] && die "Tentukan modul: gumpalan stop <auth|iot|all>"
    [[ "$mod" == "all" ]] && mod="gumpalan-auth gumpalan-iot"
    sudo systemctl stop $mod
    success "Dihentikan."
}

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------
cmd_config() {
    local mod="${1:-}"
    [[ -z "$mod" ]] && die "Tentukan file: gumpalan config <auth|iot|devices>"
    local target_file=""
    case "$mod" in
        devices|devices.yaml)
            target_file="${CONFIG_DIR}/devices.yaml"
            ;;
        auth|auth.env)
            target_file="${CONFIG_DIR}/auth.env"
            ;;
        iot|iot.env)
            target_file="${CONFIG_DIR}/iot.env"
            ;;
        *)
            target_file="${CONFIG_DIR}/${mod}"
            ;;
    esac
    [[ -f "$target_file" ]] || die "File tidak ditemukan: ${target_file}"
    "${EDITOR:-nano}" "$target_file"
}

# ---------------------------------------------------------------------------
# auth user
# ---------------------------------------------------------------------------
cmd_auth_user() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)
            call_api GET "${BASE_AUTH}/auth/v1/users" | python3 -m json.tool 2>/dev/null || \
            call_api GET "${BASE_AUTH}/auth/v1/users"
            ;;
        show)
            local id="${1:-}"; [[ -z "$id" ]] && die "Perlu user ID"
            call_api GET "${BASE_AUTH}/auth/v1/users/${id}" | python3 -m json.tool 2>/dev/null || \
            call_api GET "${BASE_AUTH}/auth/v1/users/${id}"
            ;;
        delete)
            local id="${1:-}"; [[ -z "$id" ]] && die "Perlu user ID"
            echo -ne "${YELLOW}Hapus user ${id}? [y/N]:${RESET} "; read -r c
            [[ "$c" =~ ^[Yy]$ ]] || { info "Dibatalkan."; return; }
            call_api DELETE "${BASE_AUTH}/auth/v1/users/${id}"
            success "User ${id} dihapus."
            ;;
        *) die "Sub-perintah tidak dikenal: auth user ${sub}" ;;
    esac
}

# ---------------------------------------------------------------------------
# iot device
# ---------------------------------------------------------------------------
cmd_iot_device() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)
            call_api GET "${BASE_IOT}/iot/v1/devices" | python3 -m json.tool 2>/dev/null || \
            call_api GET "${BASE_IOT}/iot/v1/devices"
            ;;
        show)
            local id="${1:-}"; [[ -z "$id" ]] && die "Perlu device ID"
            call_api GET "${BASE_IOT}/iot/v1/devices/${id}" | python3 -m json.tool 2>/dev/null || \
            call_api GET "${BASE_IOT}/iot/v1/devices/${id}"
            ;;
        approve)
            local id="${1:-}"; [[ -z "$id" ]] && die "Perlu device ID"
            call_api POST "${BASE_IOT}/iot/v1/devices/${id}/approve" | python3 -m json.tool 2>/dev/null
            success "Perangkat ${id} disetujui."
            ;;
        revoke)
            local id="${1:-}"; [[ -z "$id" ]] && die "Perlu device ID"
            echo -ne "${YELLOW}Cabut akses perangkat ${id}? [y/N]:${RESET} "; read -r c
            [[ "$c" =~ ^[Yy]$ ]] || { info "Dibatalkan."; return; }
            call_api POST "${BASE_IOT}/iot/v1/devices/${id}/revoke"
            success "Akses perangkat ${id} dicabut."
            ;;
        delete)
            local id="${1:-}"; [[ -z "$id" ]] && die "Perlu device ID"
            echo -ne "${YELLOW}Hapus perangkat ${id}? [y/N]:${RESET} "; read -r c
            [[ "$c" =~ ^[Yy]$ ]] || { info "Dibatalkan."; return; }
            call_api DELETE "${BASE_IOT}/iot/v1/devices/${id}"
            success "Perangkat ${id} dihapus."
            ;;
        perm)
            local psub="${1:-list}"; shift || true
            case "$psub" in
                list)
                    local did="${1:-}"; [[ -z "$did" ]] && die "Perlu device ID"
                    call_api GET "${BASE_IOT}/iot/v1/devices/${did}/permissions" | python3 -m json.tool 2>/dev/null || \
                    call_api GET "${BASE_IOT}/iot/v1/devices/${did}/permissions"
                    ;;
                grant)
                    local did="${1:-}" uid="${2:-}"
                    [[ -z "$did" || -z "$uid" ]] && die "Perlu device ID dan user ID"
                    call_api POST "${BASE_IOT}/iot/v1/devices/${did}/permissions" \
                        "{\"user_id\":\"${uid}\"}" | python3 -m json.tool 2>/dev/null
                    success "Izin diberikan: user ${uid} → perangkat ${did}."
                    ;;
                revoke)
                    local did="${1:-}" uid="${2:-}"
                    [[ -z "$did" || -z "$uid" ]] && die "Perlu device ID dan user ID"
                    echo -ne "${YELLOW}Cabut izin user ${uid} dari perangkat ${did}? [y/N]:${RESET} "; read -r c
                    [[ "$c" =~ ^[Yy]$ ]] || { info "Dibatalkan."; return; }
                    call_api DELETE "${BASE_IOT}/iot/v1/devices/${did}/permissions/${uid}"
                    success "Izin user ${uid} dari perangkat ${did} dicabut."
                    ;;
                *) die "Sub-perintah tidak dikenal: iot device perm ${psub}" ;;
            esac
            ;;
        *) die "Sub-perintah tidak dikenal: iot device ${sub}" ;;
    esac
}

# ---------------------------------------------------------------------------
# iot history
# ---------------------------------------------------------------------------
cmd_iot_history() {
    local sub="${1:-}"; shift || true
    [[ -z "$sub" ]] && die "Tentukan tipe: gumpalan iot history <sensor|actuator> <device_id> [channel_id]"
    local did="${1:-}"; shift || true
    local cid="${1:-}"; shift || true
    [[ -z "$did" ]] && die "Perlu device ID"

    local url="${BASE_IOT}/iot/v1/devices/${did}/history/${sub}?limit=20"
    [[ -n "$cid" ]] && url="${url}&channel=${cid}"

    call_api GET "$url" | python3 -m json.tool 2>/dev/null || call_api GET "$url"
}

# ---------------------------------------------------------------------------
# Router utama
# ---------------------------------------------------------------------------
[[ $# -eq 0 ]] && usage

cmd="$1"; shift || true

case "$cmd" in
    status)         cmd_status ;;
    log)            cmd_log "$@" ;;
    restart)        cmd_restart "$@" ;;
    stop)           cmd_stop "$@" ;;
    config)         cmd_config "$@" ;;
    auth)
        sub="${1:-}"; shift || true
        case "$sub" in
            user) cmd_auth_user "$@" ;;
            *)    die "Sub-perintah tidak dikenal: auth ${sub}" ;;
        esac
        ;;
    iot)
        sub="${1:-}"; shift || true
        case "$sub" in
            device)  cmd_iot_device "$@" ;;
            history) cmd_iot_history "$@" ;;
            *)       die "Sub-perintah tidak dikenal: iot ${sub}" ;;
        esac
        ;;
    help|--help|-h) usage ;;
    *)              die "Perintah tidak dikenal: ${cmd}. Coba: gumpalan help" ;;
esac
