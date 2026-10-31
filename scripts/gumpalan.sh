#!/usr/bin/env bash
# =============================================================================
# gumpalan — CLI helper administrasi server Gumpalan Super App
# =============================================================================
set -uo pipefail

GUMPALAN_HOME="${HOME}/.gumpalan"
LOG_DIR="${GUMPALAN_HOME}/logs"
CONFIG_DIR="${GUMPALAN_HOME}/config"
DATA_DIR="${GUMPALAN_HOME}/data"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

info()    { echo -e "  ${CYAN}→${RESET} $*"; }
success() { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()    { echo -e "  ${YELLOW}!${RESET} $*"; }
die()     { echo -e "  ${RED}✗${RESET} $*" >&2; exit 1; }

usage() {
    cat <<EOF

${BOLD}gumpalan${RESET} — CLI helper Administrasi Gumpalan Super App

${BOLD}PENGGUNAAN${RESET}
  gumpalan <perintah> [sub-perintah] [argumen...]

${BOLD}PERINTAH UMUM${RESET}
  status                             Cek status service (systemd)
  log <auth|iot>                     Pantau log real-time (tail -f)
  restart <auth|iot|all>             Restart service
  stop <auth|iot|all>                Hentikan service
  config <auth|iot|devices>          Buka berkas konfigurasi di editor

${BOLD}MODUL AUTH (svc-auth)${RESET}
  ${CYAN}Persetujuan Perangkat Klien (Smartphone / Hardware Token):${RESET}
    auth device list                 Daftar perangkat klien (pending / approved)
    auth device approve <device_id>  Setujui perangkat klien agar dapat token aktif
    auth device revoke  <device_id>  Cabut otorisasi perangkat & hapus token sesi

  ${CYAN}Manajemen Akun Pengguna:${RESET}
    auth user list                   Daftar pengguna terdaftar beserta role
    auth user create <user> <pass> [role] [nama]
                                     Buat pengguna baru langsung ke basis data
    auth user reset-password <user> <new_password>
                                     Reset kata sandi pengguna

  ${CYAN}Manajemen Peran (RBAC):${RESET}
    auth role list                   Daftar role dan modul yang diizinkan
    auth role create <nama> <modul_koma> [deskripsi]
                                     Contoh: auth role create operator iot "Operator IoT"

${BOLD}MODUL IOT (svc-iot)${RESET}
  ${CYAN}Daftar Perangkat IoT Fisik:${RESET}
    iot device list                  Daftar perangkat & channel dari devices.yaml

  ${CYAN}Izin Kontrol Perangkat (Sharing Antar-Pengguna):${RESET}
    iot perm list [device_id]        Daftar izin akses perangkat
    iot perm grant <device_id> <user_id|role> [--role] [--readonly]
                                     Beri izin kontrol perangkat ke user/role
    iot perm revoke <perm_id>        Cabut baris izin akses

  ${CYAN}Aturan Otomasi:${RESET}
    iot rule list                    Daftar aturan otomasi sensor-aktuator
    iot rule toggle <rule_id> [on|off]
                                     Aktifkan / nonaktifkan aturan otomasi
    iot rule delete <rule_id>        Hapus aturan otomasi

  ${CYAN}Riwayat Data (History):${RESET}
    iot history sensor   <device_id> [channel_id]  Lihat log metrik sensor terakhir
    iot history actuator <device_id> [channel_id]  Lihat log aktivasi aktuator

EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Runner biner internal dengan .env termuat
# ---------------------------------------------------------------------------
run_auth_bin() {
    local bin="${GUMPALAN_HOME}/bin/svc-auth/bin/auth"
    [[ -f "$bin" ]] || bin="${GUMPALAN_HOME}/bin/svc-auth/auth"
    [[ -f "$bin" ]] || die "Binary svc-auth tidak ditemukan di ${GUMPALAN_HOME}/bin/svc-auth/"

    local env_file="${CONFIG_DIR}/auth.env"
    if [[ -f "$env_file" ]]; then
        (
            set -a
            # shellcheck disable=SC1090
            source "$env_file"
            set +a
            "$bin" "$@"
        )
    else
        "$bin" "$@"
    fi
}

run_iot_bin() {
    local bin="${GUMPALAN_HOME}/bin/svc-iot/bin/iot"
    [[ -f "$bin" ]] || bin="${GUMPALAN_HOME}/bin/svc-iot/iot"
    [[ -f "$bin" ]] || die "Binary svc-iot tidak ditemukan di ${GUMPALAN_HOME}/bin/svc-iot/"

    local env_file="${CONFIG_DIR}/iot.env"
    if [[ -f "$env_file" ]]; then
        (
            set -a
            # shellcheck disable=SC1090
            source "$env_file"
            set +a
            "$bin" "$@"
        )
    else
        "$bin" "$@"
    fi
}

# ---------------------------------------------------------------------------
# Perintah Umum
# ---------------------------------------------------------------------------
cmd_status() {
    echo -e "\n${BOLD}Status Service Gumpalan${RESET}\n"
    for svc in gumpalan-auth gumpalan-iot; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}●${RESET} ${svc}  ${GREEN}running (aktif)${RESET}"
        elif systemctl list-unit-files --quiet "$svc.service" &>/dev/null; then
            echo -e "  ${RED}●${RESET} ${svc}  ${RED}stopped (berhenti)${RESET}"
        else
            echo -e "  ${YELLOW}○${RESET} ${svc}  ${YELLOW}not installed (belum terpasang)${RESET}"
        fi
    done
    echo
}

cmd_log() {
    local mod="${1:-}"
    [[ -z "$mod" ]] && die "Tentukan modul: gumpalan log <auth|iot>"
    local log_file="${LOG_DIR}/${mod}.log"
    [[ -f "$log_file" ]] || die "File log tidak ditemukan: ${log_file}"
    info "Mengikuti log ${mod} (tekan Ctrl+C untuk keluar)..."
    tail -f "$log_file"
}

cmd_restart() {
    local mod="${1:-all}"
    if [[ "$mod" == "all" ]]; then
        sudo systemctl restart gumpalan-auth gumpalan-iot 2>/dev/null || true
        success "Semua service Gumpalan berhasil di-restart."
    else
        sudo systemctl restart "gumpalan-${mod}"
        success "gumpalan-${mod} berhasil di-restart."
    fi
}

cmd_stop() {
    local mod="${1:-}"
    [[ -z "$mod" ]] && die "Tentukan modul: gumpalan stop <auth|iot|all>"
    if [[ "$mod" == "all" ]]; then
        sudo systemctl stop gumpalan-auth gumpalan-iot 2>/dev/null || true
        success "Semua service Gumpalan dihentikan."
    else
        sudo systemctl stop "gumpalan-${mod}"
        success "Service gumpalan-${mod} dihentikan."
    fi
}

cmd_config() {
    local mod="${1:-}"
    [[ -z "$mod" ]] && die "Tentukan berkas: gumpalan config <auth|iot|devices>"
    local target_file=""
    case "$mod" in
        devices|devices.yaml) target_file="${CONFIG_DIR}/devices.yaml" ;;
        auth|auth.env)       target_file="${CONFIG_DIR}/auth.env" ;;
        iot|iot.env)         target_file="${CONFIG_DIR}/iot.env" ;;
        *)                   target_file="${CONFIG_DIR}/${mod}" ;;
    esac
    [[ -f "$target_file" ]] || die "Berkas tidak ditemukan: ${target_file}"
    "${EDITOR:-nano}" "$target_file"
}

# ---------------------------------------------------------------------------
# Dispatcher auth (meneruskan langsung ke biner svc-auth CLI)
# ---------------------------------------------------------------------------
cmd_auth() {
    [[ $# -eq 0 ]] && { run_auth_bin help; return; }
    run_auth_bin "$@"
}

# ---------------------------------------------------------------------------
# Dispatcher iot (meneruskan ke biner svc-iot CLI & query history)
# ---------------------------------------------------------------------------
cmd_iot() {
    [[ $# -eq 0 ]] && { run_iot_bin help; return; }
    local sub="$1"; shift || true

    case "$sub" in
        device|perm|permission|rule|automation)
            run_iot_bin "$sub" "$@"
            ;;
        history)
            cmd_iot_history "$@"
            ;;
        *)
            run_iot_bin "$sub" "$@"
            ;;
    esac
}

cmd_iot_history() {
    local type="${1:-}"; shift || true
    local dev_id="${1:-}"; shift || true
    local ch_id="${1:-}"; shift || true

    [[ -z "$type" || -z "$dev_id" ]] && die "Penggunaan: gumpalan iot history <sensor|actuator> <device_id> [channel_id]"

    local db_file="${DATA_DIR}/iot.db"
    if command -v sqlite3 &>/dev/null && [[ -f "$db_file" ]]; then
        if [[ "$type" == "sensor" ]]; then
            local sql="SELECT datetime(recorded_at, 'unixepoch', 'localtime') AS waktu, channel_id, value, unit FROM iot_sensor_logs WHERE device_id = '${dev_id}'"
            [[ -n "$ch_id" ]] && sql="${sql} AND channel_id = '${ch_id}'"
            sql="${sql} ORDER BY recorded_at DESC LIMIT 20;"
            sqlite3 -header -column "$db_file" "$sql"
        else
            local sql="SELECT datetime(recorded_at, 'unixepoch', 'localtime') AS waktu, channel_id, value, source, COALESCE(actor_name, actor_id, '-') AS actor FROM iot_actuator_logs WHERE device_id = '${dev_id}'"
            [[ -n "$ch_id" ]] && sql="${sql} AND channel_id = '${ch_id}'"
            sql="${sql} ORDER BY recorded_at DESC LIMIT 20;"
            sqlite3 -header -column "$db_file" "$sql"
        fi
    else
        # Fallback via HTTP API internal
        local env_file="${CONFIG_DIR}/iot.env"
        local port="8002"
        [[ -f "$env_file" ]] && port=$(grep -E '^PORT=' "$env_file" | cut -d= -f2 | tr -d ' ' || echo "8002")
        local url="http://127.0.0.1:${port}/iot/v1/devices/${dev_id}/history/${type}?limit=20"
        [[ -n "$ch_id" ]] && url="${url}&channel=${ch_id}"
        curl -fsSL "$url" | python3 -m json.tool 2>/dev/null || curl -fsSL "$url"
    fi
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
[[ $# -eq 0 ]] && usage

cmd="$1"; shift || true

case "$cmd" in
    status)           cmd_status ;;
    log)              cmd_log "$@" ;;
    restart)          cmd_restart "$@" ;;
    stop)             cmd_stop "$@" ;;
    config)           cmd_config "$@" ;;
    auth)             cmd_auth "$@" ;;
    iot)              cmd_iot "$@" ;;
    help|--help|-h)   usage ;;
    *)                die "Perintah tidak dikenal: ${cmd}. Jalankan 'gumpalan help' untuk panduan." ;;
esac
