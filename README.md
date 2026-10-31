# infra-deploy

Konfigurasi deployment, reverse proxy Nginx modular, unit systemd, broker Mosquitto, Cloudflare Tunnel, dan panduan basis data untuk super app Gumpalan.

## Struktur Direktori

```
infra-deploy/
├── cloudflared/
│   └── config.example.yml         # Konfigurasi ingress Cloudflare Tunnel ke port 8080
├── db/
│   └── README.md                  # Panduan pemilihan database & template pembuatan user
├── env/
│   ├── auth.env.example           # Contoh variabel lingkungan svc-auth
│   └── iot.env.example            # Contoh variabel lingkungan svc-iot
├── mosquitto/
│   └── mosquitto.conf.example     # Konfigurasi listener lokal & password file
├── nginx/
│   ├── gumpalan.conf              # Entry point server 8080 & rute internal /_verify
│   └── conf.d/
│       ├── auth.conf              # Proxy rute /auth/v1/ ke :8001
│       └── iot.conf               # auth_request + proxy rute /iot/v1/ ke :8002
├── scripts/
│   └── README.md                  # Rencana dan langkah deployment cross-compile ARM64
├── systemd/
│   ├── gumpalan-auth.service      # Unit file systemd untuk svc-auth
│   └── gumpalan-iot.service       # Unit file systemd untuk svc-iot
└── tasmota/
    └── README.md                  # Catatan konfigurasi MQTT perangkat Tasmota
```

## Instalasi Cepat (STB / Server Target)

Jalankan perintah berikut di mesin target (Armbian / Ubuntu / Debian):

```bash
# Unduh dan jalankan wizard instalasi interaktif
curl -fsSL https://raw.githubusercontent.com/gumpalan/infra-deploy/main/scripts/install.sh | bash
```

Installer akan memandu pemilihan modul, webserver, database, konfigurasi `.env`, dan mengunduh binary release langsung ke `~/.gumpalan/`.

Setelah selesai, kelola service menggunakan CLI:
```bash
gumpalan status
gumpalan log iot
gumpalan iot device list
```

Dokumentasi lengkap: baca [docs/OPERASIONAL.md](docs/OPERASIONAL.md).

---

## Struktur Direktori

Arsitektur Nginx dan backend dirancang modular:

### Hanya Mengaktifkan svc-auth:
1. Pasang `nginx/gumpalan.conf` dan hanya sertakan berkas `nginx/conf.d/auth.conf`.
2. Jangan pasang `nginx/conf.d/iot.conf`.
3. Jalankan hanya service `gumpalan-auth.service`.
4. Permintaan ke `/iot/v1/*` otomatis menghasilkan HTTP 404 dari Nginx tanpa membebani resource.

### Menambahkan Modul Baru di Masa Depan:
1. Buat service backend baru (misal `svc-billing`).
2. Buat file rute Nginx baru di `conf.d/billing.conf` dengan menyertakan direktif `auth_request /_verify;`.
3. Muat ulang konfigurasi Nginx via `sudo nginx -s reload`.

## Lisensi dan Dependensi

Lisensi repositori ini **belum ditentukan**. Berisi berkas konfigurasi murni dan panduan operasional.
