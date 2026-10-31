#!/usr/bin/env bash
# =============================================================================
# Gumpalan Installer
# Jalankan di STB/server target:
#   curl -fsSL https://raw.githubusercontent.com/gumpalan/infra-deploy/main/scripts/install.sh | bash
#   -- atau --
#   bash install.sh
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Warna dan helper UI
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║           G U M P A L A N  Installer            ║"
    echo "  ║         Super App IoT Self-Hosted Setup          ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

info()    { echo -e "  ${CYAN}→${RESET} $*"; }
success() { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()    { echo -e "  ${YELLOW}!${RESET} $*"; }
error()   { echo -e "  ${RED}✗${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# Helper membaca input interaktif, mendukung pipe 'curl ... | bash' via /dev/tty
_read() {
    if [[ -e /dev/tty ]]; then
        read "$@" < /dev/tty || true
    else
        read "$@" || true
    fi
}

ask() {
    # ask "Pertanyaan" default_value → hasil di $REPLY
    local prompt="$1" default="${2:-}"
    if [[ -n "$default" ]]; then
        echo -ne "  ${BOLD}${prompt}${RESET} [${default}]: "
    else
        echo -ne "  ${BOLD}${prompt}${RESET}: "
    fi
    _read -r REPLY
    [[ -z "$REPLY" ]] && REPLY="$default"
}

ask_secret() {
    local prompt="$1"
    echo -ne "  ${BOLD}${prompt}${RESET}: "
    _read -rs REPLY
    echo
}

# Menu pilih satu item dari array.
# Argumen: "judul" "item1" "item2" ...
# Hasil di $MENU_RESULT (nilai item yang dipilih)
menu_single() {
    local title="$1"; shift
    local items=("$@")
    echo
    echo -e "  ${BOLD}${title}${RESET}"
    local i=1
    for item in "${items[@]}"; do
        echo "    ${BOLD}${i})${RESET} ${item}"
        ((i++))
    done
    echo
    while true; do
        echo -ne "  Pilih [1-${#items[@]}]: "
        _read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            MENU_RESULT="${items[$((choice-1))]}"
            return
        fi
        warn "Pilihan tidak valid."
    done
}

# Menu pilih banyak item (spasi untuk toggle, ENTER konfirmasi).
# Argumen: "judul" "item1" "item2" ...
# Hasil: array MENU_SELECTED
menu_multi() {
    local title="$1"; shift
    local items=("$@")
    local selected=()
    for _ in "${items[@]}"; do selected+=(0); done

    while true; do
        echo
        echo -e "  ${BOLD}${title}${RESET}"
        echo -e "  ${CYAN}(ketik nomor untuk toggle, ENTER jika sudah selesai)${RESET}"
        local i=0
        for item in "${items[@]}"; do
            local mark="  "
            [[ "${selected[$i]}" == "1" ]] && mark="${GREEN}✓${RESET}"
            echo -e "    ${BOLD}$((i+1)))${RESET} [${mark}] ${item}"
            ((i++))
        done
        echo
        echo -ne "  Toggle [nomor] atau ENTER: "
        _read -r choice
        if [[ -z "$choice" ]]; then
            # Validasi minimal satu dipilih
            local any=0
            for s in "${selected[@]}"; do [[ "$s" == "1" ]] && any=1; done
            if [[ $any -eq 0 ]]; then
                warn "Pilih minimal satu modul."
                continue
            fi
            break
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            local idx=$((choice-1))
            [[ "${selected[$idx]}" == "0" ]] && selected[$idx]=1 || selected[$idx]=0
        else
            warn "Nomor tidak valid."
        fi
    done

    MENU_SELECTED=()
    local i=0
    for item in "${items[@]}"; do
        [[ "${selected[$i]}" == "1" ]] && MENU_SELECTED+=("$item")
        ((i++))
    done
}

# ---------------------------------------------------------------------------
# Konstanta path
# ---------------------------------------------------------------------------
GUMPALAN_HOME="${HOME}/.gumpalan"
BIN_DIR="${GUMPALAN_HOME}/bin"
CONFIG_DIR="${GUMPALAN_HOME}/config"
DATA_DIR="${GUMPALAN_HOME}/data"
LOG_DIR="${GUMPALAN_HOME}/logs"

SYSTEMD_DIR="/etc/systemd/system"
NGINX_CONF_DIR="/etc/nginx/conf.d/gumpalan"
GUMPALAN_ETC="/etc/gumpalan"

GITHUB_ORG="https://github.com/gumpalan"
RELEASE_API="https://api.github.com/repos/gumpalan"

# ---------------------------------------------------------------------------
# Daftar modul yang tersedia
# Tambah modul baru di sini — installer otomatis menawarkannya.
# Format: "id:Nama Tampilan:repo_github:port_default"
# ---------------------------------------------------------------------------
declare -A MODULE_NAME MODULE_REPO MODULE_PORT MODULE_DESC
AVAILABLE_MODULES=("auth" "iot")

MODULE_NAME["auth"]="svc-auth (Wajib)"
MODULE_REPO["auth"]="svc-auth"
MODULE_PORT["auth"]="8001"
MODULE_DESC["auth"]="Service autentikasi dan otorisasi. Selalu dipasang."

MODULE_NAME["iot"]="svc-iot (Modul IoT)"
MODULE_REPO["iot"]="svc-iot"
MODULE_PORT["iot"]="8002"
MODULE_DESC["iot"]="Manajemen perangkat IoT, MQTT broker, dashboard, otomasi."

# ---------------------------------------------------------------------------
# Deteksi arsitektur
# ---------------------------------------------------------------------------
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        aarch64|arm64) echo "linux-arm64" ;;
        x86_64)        echo "linux-amd64" ;;
        armv7l)        echo "linux-arm" ;;
        *)             die "Arsitektur ${arch} tidak didukung." ;;
    esac
}

# ---------------------------------------------------------------------------
# Cek dependensi sistem
# ---------------------------------------------------------------------------
check_deps() {
    local missing=()
    for cmd in curl tar systemctl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Dependensi tidak ditemukan: ${missing[*]}. Pasang terlebih dahulu."
    fi
}

# ---------------------------------------------------------------------------
# Download release dari GitHub
# Argumen: repo_name arch version → unduh ke $BIN_DIR/<repo>
# ---------------------------------------------------------------------------
download_release() {
    local repo="$1" arch="$2" version="$3"
    local download_url=""

    info "Mencari release ${repo} (${arch}, versi: ${version})..."

    # 1. Coba cari via GitHub Releases API (mendukung nama dengan atau tanpa versi)
    local api_url="${RELEASE_API}/${repo}/releases/latest"
    [[ "$version" != "latest" ]] && api_url="${RELEASE_API}/${repo}/releases/tags/${version}"

    local release_json
    release_json=$(curl -fsSL "$api_url" 2>/dev/null || true)

    if [[ -n "$release_json" ]]; then
        # Cocokkan URL asset yang mengandung nama repo dan arsitektur .tar.gz
        download_url=$(echo "$release_json" \
            | grep -o '"browser_download_url": *"[^"]*"' \
            | sed 's/.*"\(https[^"]*\)".*/\1/' \
            | grep "${arch}\.tar\.gz" \
            | head -1 || true)
    fi

    # 2. Fallback URL langsung jika API gagal / limit
    if [[ -z "$download_url" ]]; then
        local candidate_urls=(
            "${GITHUB_ORG}/${repo}/releases/download/${version}/${repo}-${version}-${arch}.tar.gz"
            "${GITHUB_ORG}/${repo}/releases/download/${version}/${repo}-${arch}.tar.gz"
        )
        for u in "${candidate_urls[@]}"; do
            if curl -fsIL "$u" &>/dev/null; then
                download_url="$u"
                break
            fi
        done
    fi

    [[ -z "$download_url" ]] && die "Asset release untuk ${repo} (${arch}) tidak ditemukan di GitHub Releases."

    info "Mengunduh dari: ${download_url}"
    local tmp_file="${GUMPALAN_HOME}/tmp/${repo}.tar.gz"
    mkdir -p "${GUMPALAN_HOME}/tmp"
    curl -fsSL -o "$tmp_file" "$download_url" || die "Gagal unduh ${repo}."

    mkdir -p "${BIN_DIR}/${repo}"
    tar -xzf "$tmp_file" -C "${BIN_DIR}/${repo}" || die "Gagal ekstrak ${repo}."
    rm -f "$tmp_file"

    # Normalisasi lokasi binary jika di-pack tanpa subfolder bin/
    local mod="$repo"
    [[ "$repo" == "svc-auth" ]] && mod="auth"
    [[ "$repo" == "svc-iot" ]] && mod="iot"

    if [[ -f "${BIN_DIR}/${repo}/${mod}" && ! -f "${BIN_DIR}/${repo}/bin/${mod}" ]]; then
        mkdir -p "${BIN_DIR}/${repo}/bin"
        mv "${BIN_DIR}/${repo}/${mod}" "${BIN_DIR}/${repo}/bin/${mod}"
    fi

    if [[ -f "${BIN_DIR}/${repo}/bin/${mod}" ]]; then
        chmod +x "${BIN_DIR}/${repo}/bin/${mod}"
    fi

    success "Binary ${repo} siap di ${BIN_DIR}/${repo}/"
}

# ---------------------------------------------------------------------------
# Setup env file interaktif
# Argumen: module_id
# ---------------------------------------------------------------------------
setup_env_auth() {
    local env_file="${CONFIG_DIR}/auth.env"
    [[ -f "$env_file" ]] && { warn "auth.env sudah ada, dilewati. Edit manual: ${env_file}"; return; }

    echo
    echo -e "  ${BOLD}Konfigurasi svc-auth${RESET}"

    ask "Port svc-auth" "8001";           local port="$REPLY"
    ask "Jenis database (sqlite/mysql/mariadb/pgsql)" "sqlite"; local db_conn="$REPLY"

    local db_host db_port db_user db_pass db_name db_sslmode
    db_host="127.0.0.1"; db_port="3306"; db_user=""; db_pass=""; db_sslmode="disable"

    if [[ "$db_conn" == "sqlite" ]]; then
        db_name="${DATA_DIR}/auth.db"
    else
        ask "Nama database" "gumpalan_auth";   db_name="$REPLY"
        ask "Host database" "127.0.0.1";       db_host="$REPLY"
        ask "Port database" "3306";            db_port="$REPLY"
        ask "Username database" "gumpalan";    db_user="$REPLY"
        ask_secret "Password database";        db_pass="$REPLY"
        [[ "$db_conn" == "pgsql" ]] && { ask "SSL Mode (disable/require)" "disable"; db_sslmode="$REPLY"; }
    fi

    mkdir -p "$CONFIG_DIR"
    cat > "$env_file" <<EOF
PORT=${port}

DB_CONNECTION=${db_conn}
DB_DATABASE=${db_name}
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_USERNAME=${db_user}
DB_PASSWORD=${db_pass}
DB_SSLMODE=${db_sslmode}
DB_AUTO_MIGRATE=true
EOF
    success "auth.env ditulis ke ${env_file}"
}

setup_env_iot() {
    local env_file="${CONFIG_DIR}/iot.env"
    [[ -f "$env_file" ]] && { warn "iot.env sudah ada, dilewati. Edit manual: ${env_file}"; return; }

    echo
    echo -e "  ${BOLD}Konfigurasi svc-iot${RESET}"

    ask "Port svc-iot" "8002";                      local port="$REPLY"
    ask "Jenis database (sqlite/mysql/mariadb/pgsql)" "sqlite"; local db_conn="$REPLY"

    local db_host db_port db_user db_pass db_name db_sslmode
    db_host="127.0.0.1"; db_port="3306"; db_user=""; db_pass=""; db_sslmode="disable"

    if [[ "$db_conn" == "sqlite" ]]; then
        db_name="${DATA_DIR}/iot.db"
    else
        ask "Nama database" "gumpalan_iot";        db_name="$REPLY"
        ask "Host database" "127.0.0.1";           db_host="$REPLY"
        ask "Port database" "3306";                db_port="$REPLY"
        ask "Username database" "gumpalan";        db_user="$REPLY"
        ask_secret "Password database";            db_pass="$REPLY"
        [[ "$db_conn" == "pgsql" ]] && { ask "SSL Mode (disable/require)" "disable"; db_sslmode="$REPLY"; }
    fi

    ask "MQTT Broker URL" "tcp://127.0.0.1:1883";  local mqtt_broker="$REPLY"
    ask "MQTT Username" "";                         local mqtt_user="$REPLY"
    ask_secret "MQTT Password (kosong jika tanpa auth)"; local mqtt_pass="$REPLY"

    echo
    echo -e "  ${BOLD}History data sensor/aktuator${RESET}"
    echo -e "  ${CYAN}Pilihan: none | sensor | actuator | all${RESET}"
    ask "HISTORY_MODE" "none";                      local hist_mode="$REPLY"
    ask "HISTORY_RETENTION_DAYS (0 = selamanya)" "0"; local hist_ret="$REPLY"

    mkdir -p "$CONFIG_DIR"
    local dev_yaml="${CONFIG_DIR}/devices.yaml"
    cat > "$env_file" <<EOF
PORT=${port}

DB_CONNECTION=${db_conn}
DB_DATABASE=${db_name}
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_USERNAME=${db_user}
DB_PASSWORD=${db_pass}
DB_SSLMODE=${db_sslmode}
DB_AUTO_MIGRATE=true

DEVICES_CONFIG_PATH=${dev_yaml}

MQTT_BROKER=${mqtt_broker}
MQTT_CLIENT_ID=
MQTT_USERNAME=${mqtt_user}
MQTT_PASSWORD=${mqtt_pass}

HISTORY_MODE=${hist_mode}
HISTORY_RETENTION_DAYS=${hist_ret}
EOF
    success "iot.env ditulis ke ${env_file}"

    # Siapkan devices.yaml jika belum ada
    if [[ ! -f "$dev_yaml" ]]; then
        if [[ -f "${BIN_DIR}/svc-iot/config/devices.example.yaml" ]]; then
            cp "${BIN_DIR}/svc-iot/config/devices.example.yaml" "$dev_yaml"
        elif [[ -f "${BIN_DIR}/svc-iot/config/devices.yaml" ]]; then
            cp "${BIN_DIR}/svc-iot/config/devices.yaml" "$dev_yaml"
        else
            cat > "$dev_yaml" <<'DEV_EOF'
devices:
  - id: "living-room-sensor"
    name: "Sensor Ruang Tamu"
    driver: "custom"
    channels:
      - id: "temperature"
        name: "Suhu"
        direction: "input"
        topic: "gumpalan/device/living-room/tele/temp"
        type: "number"
        unit: "°C"
        min: 0
        max: 50
        ui_hint: "gauge"

      - id: "humidity"
        name: "Kelembaban"
        direction: "input"
        topic: "gumpalan/device/living-room/tele/humidity"
        type: "number"
        unit: "%"
        min: 0
        max: 100
        ui_hint: "value_display"

  - id: "lampu-kamar"
    name: "Lampu Kamar Tidur"
    driver: "tasmota"
    topic: "lampu_kamar"
    channels:
      - id: "power"
        name: "Power Lampu"
        direction: "bidirectional"
        command_topic: "cmnd/lampu_kamar/POWER"
        state_topic: "stat/lampu_kamar/POWER"
        type: "boolean"
        ui_hint: "toggle"
DEV_EOF
        fi
        success "devices.yaml template disiapkan di ${dev_yaml}"
    fi
}

# ---------------------------------------------------------------------------
# Setup systemd unit
# Argumen: module_id
# ---------------------------------------------------------------------------
install_systemd_unit() {
    local mod="$1"
    local repo="${MODULE_REPO[$mod]}"
    local bin_path="${BIN_DIR}/${repo}/bin/${mod}"
    local env_path="${CONFIG_DIR}/${mod}.env"
    local unit_file="${SYSTEMD_DIR}/gumpalan-${mod}.service"
    local after_deps="network.target"
    [[ "$mod" == "iot" ]] && after_deps="network.target gumpalan-auth.service"

    info "Memasang unit systemd gumpalan-${mod}..."

    sudo tee "$unit_file" > /dev/null <<EOF
[Unit]
Description=Gumpalan ${MODULE_NAME[$mod]}
After=${after_deps}

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=${BIN_DIR}/${repo}
EnvironmentFile=${env_path}
ExecStart=${bin_path}
Restart=on-failure
RestartSec=5s
StandardOutput=append:${LOG_DIR}/${mod}.log
StandardError=append:${LOG_DIR}/${mod}-error.log
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "gumpalan-${mod}.service"
    success "Service gumpalan-${mod} terpasang dan diaktifkan."
}

# ---------------------------------------------------------------------------
# Setup nginx
# ---------------------------------------------------------------------------
setup_nginx() {
    local selected_modules=("$@")
    local nginx_main_conf="/etc/nginx/conf.d/gumpalan.conf"

    info "Menyiapkan konfigurasi nginx..."
    sudo mkdir -p "$NGINX_CONF_DIR"

    # WebSocket map — harus di level http
    sudo tee "/etc/nginx/conf.d/gumpalan-ws-map.conf" > /dev/null <<'EOF'
map $http_upgrade $connection_upgrade {
    default   "upgrade";
    ""        "close";
}
EOF

    # Server block utama dengan /_verify
    sudo tee "$nginx_main_conf" > /dev/null <<'EOF'
server {
    listen 8080;
    server_name _;

    # Titik verifikasi token internal
    location = /_verify {
        internal;
        proxy_pass http://127.0.0.1:8001/auth/v1/verify;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
        proxy_set_header Authorization $http_authorization;
    }

    include /etc/nginx/conf.d/gumpalan/*.conf;
}
EOF

    # Conf per modul
    for mod in "${selected_modules[@]}"; do
        local port="${MODULE_PORT[$mod]}"
        local prefix="/iot/v1/"
        [[ "$mod" == "auth" ]] && prefix="/auth/v1/"

        if [[ "$mod" == "auth" ]]; then
            sudo tee "${NGINX_CONF_DIR}/auth.conf" > /dev/null <<EOF
# Rute svc-auth — tanpa auth_request (ini endpoint autentikasi itu sendiri)
location /auth/v1/ {
    proxy_pass http://127.0.0.1:${port}/auth/v1/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF
        elif [[ "$mod" == "iot" ]]; then
            sudo tee "${NGINX_CONF_DIR}/iot.conf" > /dev/null <<EOF
# Rute svc-iot — dilindungi auth_request
location /iot/v1/ {
    auth_request /_verify;

    auth_request_set \$saved_device_id \$upstream_http_x_device_id;
    proxy_set_header X-Device-Id \$saved_device_id;

    auth_request_set \$saved_user_id \$upstream_http_x_user_id;
    proxy_set_header X-User-Id \$saved_user_id;

    auth_request_set \$saved_user_role \$upstream_http_x_user_role;
    proxy_set_header X-User-Role \$saved_user_role;

    proxy_pass http://127.0.0.1:${port}/iot/v1/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}
EOF
        fi
        success "Nginx conf untuk ${mod} ditulis."
    done

    # Test dan reload
    if sudo nginx -t 2>/dev/null; then
        sudo nginx -s reload 2>/dev/null || sudo systemctl restart nginx
        success "Nginx reload berhasil."
    else
        warn "Nginx test gagal. Periksa konfigurasi secara manual: sudo nginx -t"
    fi
}

setup_apache() {
    warn "Dukungan Apache belum diimplementasi. Silakan konfigurasi manual."
    warn "Panduan: lihat docs/webserver-apache.md di repo infra-deploy."
}

# ---------------------------------------------------------------------------
# Buat folder ~/.gumpalan
# ---------------------------------------------------------------------------
init_gumpalan_home() {
    info "Membuat direktori ${GUMPALAN_HOME}..."
    mkdir -p "${BIN_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}"

    # README kecil agar user tahu fungsi tiap folder
    cat > "${GUMPALAN_HOME}/README.txt" <<'EOF'
~/.gumpalan/
├── bin/          Binary service yang diunduh dari GitHub Releases
│   ├── svc-auth/ Binary svc-auth
│   └── svc-iot/  Binary svc-iot
├── config/       File konfigurasi (.env) per modul
│   ├── auth.env
│   └── iot.env
├── data/         Data SQLite (jika DB_CONNECTION=sqlite)
│   ├── auth.db
│   └── iot.db
└── logs/         Log output service
    ├── auth.log
    ├── auth-error.log
    ├── iot.log
    └── iot-error.log

Edit konfigurasi:
  nano ~/.gumpalan/config/iot.env

Cek log:
  tail -f ~/.gumpalan/logs/iot.log
  tail -f ~/.gumpalan/logs/iot-error.log

Status service:
  sudo systemctl status gumpalan-auth
  sudo systemctl status gumpalan-iot

Restart service:
  sudo systemctl restart gumpalan-iot
EOF
    success "Direktori ${GUMPALAN_HOME} siap."
}

# ---------------------------------------------------------------------------
# Start service
# ---------------------------------------------------------------------------
start_services() {
    local selected_modules=("$@")
    echo
    info "Menjalankan service..."
    for mod in "${selected_modules[@]}"; do
        if sudo systemctl start "gumpalan-${mod}.service" 2>/dev/null; then
            success "gumpalan-${mod} berjalan."
        else
            warn "gumpalan-${mod} gagal start. Cek: journalctl -u gumpalan-${mod} -n 30"
        fi
    done
}

# ---------------------------------------------------------------------------
# Ringkasan akhir
# ---------------------------------------------------------------------------
print_summary() {
    local selected_modules=("$@")
    echo
    echo -e "${GREEN}${BOLD}  ══════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}    Instalasi selesai!${RESET}"
    echo -e "${GREEN}${BOLD}  ══════════════════════════════════════════${RESET}"
    echo
    echo -e "  ${BOLD}Modul terpasang:${RESET}"
    for mod in "${selected_modules[@]}"; do
        echo "    • ${MODULE_NAME[$mod]}  →  port ${MODULE_PORT[$mod]}"
    done
    echo
    echo -e "  ${BOLD}Direktori kerja:${RESET}  ${GUMPALAN_HOME}"
    echo -e "  ${BOLD}Konfigurasi:${RESET}      ${CONFIG_DIR}/"
    echo -e "  ${BOLD}Log:${RESET}              ${LOG_DIR}/"
    echo
    echo -e "  ${BOLD}Perintah berguna:${RESET}"
    echo "    gumpalan status          → cek status semua service"
    echo "    gumpalan log iot         → ikuti log svc-iot"
    echo "    gumpalan iot device list → daftar perangkat IoT"
    echo "    gumpalan auth user list  → daftar user"
    echo
    echo -e "  ${CYAN}Lihat dokumentasi lengkap:${RESET}"
    echo "    ${GUMPALAN_HOME}/README.txt"
    echo "    ${GITHUB_ORG}/infra-deploy"
    echo
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
main() {
    print_header
    check_deps

    local arch
    arch=$(detect_arch)
    info "Terdeteksi arsitektur: ${arch}"

    # ── 1. Pilih versi ──────────────────────────────────────────────────────
    echo
    ask "Versi yang akan dipasang (contoh: v1.0.0, atau 'latest')" "latest"
    local version="$REPLY"

    # ── 2. Pilih modul ──────────────────────────────────────────────────────
    # svc-auth selalu wajib; modul opsional ditawarkan
    echo
    echo -e "  ${BOLD}svc-auth${RESET} selalu dipasang (wajib)."

    local optional_modules=("iot")
    local optional_labels=()
    for mod in "${optional_modules[@]}"; do
        optional_labels+=("${MODULE_NAME[$mod]} — ${MODULE_DESC[$mod]}")
    done

    menu_multi "Pilih modul opsional yang ingin dipasang:" "${optional_labels[@]}"
    local selected_optional=()
    # Map label kembali ke id
    for label in "${MENU_SELECTED[@]}"; do
        for mod in "${optional_modules[@]}"; do
            [[ "$label" == "${MODULE_NAME[$mod]}"* ]] && selected_optional+=("$mod")
        done
    done

    local all_modules=("auth" "${selected_optional[@]}")

    # ── 3. Pilih webserver ──────────────────────────────────────────────────
    menu_single "Pilih webserver:" "nginx" "apache" "skip (konfigurasi manual)"
    local webserver="$MENU_RESULT"

    # ── 4. Konfirmasi ───────────────────────────────────────────────────────
    echo
    echo -e "  ${BOLD}Ringkasan instalasi:${RESET}"
    echo "    Versi    : ${version}"
    echo "    Modul    : ${all_modules[*]}"
    echo "    Webserver: ${webserver}"
    echo "    Lokasi   : ${GUMPALAN_HOME}"
    echo
    echo -ne "  Lanjutkan? [y/N]: "
    _read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Instalasi dibatalkan."; exit 0; }

    # ── 5. Eksekusi ─────────────────────────────────────────────────────────
    echo
    echo -e "  ${BOLD}Memulai instalasi...${RESET}"

    init_gumpalan_home

    for mod in "${all_modules[@]}"; do
        local repo="${MODULE_REPO[$mod]}"
        download_release "$repo" "$arch" "$version"
    done

    for mod in "${all_modules[@]}"; do
        "setup_env_${mod}"
    done

    for mod in "${all_modules[@]}"; do
        install_systemd_unit "$mod"
    done

    case "$webserver" in
        nginx)  setup_nginx "${all_modules[@]}" ;;
        apache) setup_apache ;;
        skip*)  warn "Konfigurasi webserver dilewati. Lakukan secara manual." ;;
    esac

    start_services "${all_modules[@]}"
    print_summary "${all_modules[@]}"

    # Pasang CLI helper jika ada
    if [[ -f "$(dirname "$0")/gumpalan.sh" ]]; then
        sudo cp "$(dirname "$0")/gumpalan.sh" /usr/local/bin/gumpalan
        sudo chmod +x /usr/local/bin/gumpalan
        success "CLI 'gumpalan' terpasang di /usr/local/bin/gumpalan"
    fi
}

main "$@"
