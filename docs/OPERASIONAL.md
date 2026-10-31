# Dokumentasi Operasional Gumpalan

Panduan lengkap instalasi, arsitektur modul, manajemen perangkat, perizinan, dan panggilan API antar-layanan.

---

## 1. Arsitektur Port & Jaringan

```
                         Internet / Klien
                                │
                                ▼
                       [ Nginx :8080 ]
                                │
        ┌───────────────────────┴───────────────────────┐
        │                                               │
   /auth/v1/*                                      /iot/v1/*
        │                                               │
        │                                         (auth_request)
        │                                               │
        ▼                                               ▼
 [ svc-auth :8001 ]                             [ svc-iot :8002 ]
  - JWT Issue & Verify                           - StateHub & Inbound MQTT
  - User CRUD                                    - Automation Engine
  - Device Approval                              - History Data (DB)
        │                                               │
        ▼                                               ▼
  [ SQLite / MySQL ]                              [ SQLite / MySQL ]
  auth.db                                        iot.db
                                                        │
                                                        ▼
                                                [ Mosquitto :1883 ]
                                                Broker MQTT Lokal
```

- **Nginx (8080)**: Satu-satunya port yang di-expose ke publik atau tunnel (Cloudflare).
- **svc-auth (8001)**: Private, hanya diakses oleh Nginx dan internal script.
- **svc-iot (8002)**: Private, hanya diakses oleh Nginx setelah lolos `auth_request /_verify`.
- **Mosquitto (1883)**: Broker MQTT lokal, diakses oleh `svc-iot` dan perangkat IoT di LAN.

---

## 2. Struktur Folder `~/.gumpalan`

Semua artefak runtime berada di dalam direktori `~/.gumpalan/` di home user yang menjalankan service:

```
~/.gumpalan/
├── bin/                       # Binary hasil download dari GitHub Releases
│   ├── svc-auth/bin/auth      # Binary svc-auth
│   └── svc-iot/bin/iot        # Binary svc-iot
├── config/                    # File lingkungan (.env) aktif
│   ├── auth.env               # Konfigurasi svc-auth
│   └── iot.env                # Konfigurasi svc-iot
├── data/                      # File database SQLite lokal
│   ├── auth.db                # User, token, session
│   └── iot.db                 # Device, channel, rule, dashboard, history
└── logs/                      # Log eksekusi service
    ├── auth.log
    ├── auth-error.log
    ├── iot.log
    └── iot-error.log
```

---

## 3. Instalasi Cepat (STB / Server Baru)

```bash
# 1. Download installer
curl -fsSL https://raw.githubusercontent.com/gumpalan/infra-deploy/main/scripts/install.sh -o install.sh

# 2. Jalankan installer interaktif
bash install.sh
```

Installer akan memandu:
1. Pilihan versi release (`latest` atau tag tertentu).
2. Pilihan modul (`svc-auth` wajib, `svc-iot` opsional, modul lain di masa depan).
3. Pilihan webserver (`nginx` otomatis setup reverse proxy + WebSocket map).
4. Konfigurasi database per modul (SQLite default, atau MySQL/Postgres).
5. Konfigurasi MQTT broker dan mode history untuk `svc-iot`.
6. Download binary release per arsitektur (`linux-arm64`, `linux-amd64`).
7. Pemasangan service systemd dan aktivasi otomatis.

---

## 4. CLI Helper `gumpalan`

Setelah instalasi, perintah `gumpalan` tersedia di terminal server.

### Status & Log

```bash
# Cek apakah service berjalan
gumpalan status

# Pantau log secara real-time
gumpalan log iot
gumpalan log auth

# Restart service
gumpalan restart iot
gumpalan restart all

# Buka file .env di editor
gumpalan config iot
```

### Manajemen User (svc-auth)

```bash
# Daftar seluruh user
gumpalan auth user list

# Detail user tertentu
gumpalan auth user show usr_abc123

# Hapus user
gumpalan auth user delete usr_abc123
```

### Manajemen Perangkat IoT (svc-iot)

```bash
# Daftar semua perangkat yang terdaftar
gumpalan iot device list

# Detail perangkat beserta channel-nya
gumpalan iot device show living-room-sensor

# Setujui perangkat baru yang statusnya pending
gumpalan iot device approve esp32-kamar

# Cabut akses perangkat (device tidak bisa publish/subscribe lagi)
gumpalan iot device revoke esp32-kamar

# Hapus total perangkat dari database
gumpalan iot device delete esp32-kamar
```

### Manajemen Izin Perangkat (Sharing Antar-Pengguna)

```bash
# Lihat siapa saja yang punya akses ke perangkat
gumpalan iot device perm list esp32-kamar

# Beri akses perangkat ke user lain
gumpalan iot device perm grant esp32-kamar usr_keluarga456

# Cabut akses user dari perangkat
gumpalan iot device perm revoke esp32-kamar usr_keluarga456
```

### Cek Riwayat Data (History)

```bash
# Lihat 20 log sensor terakhir
gumpalan iot history sensor living-room-sensor temperature

# Lihat 20 log aktivasi aktuator terakhir (siapa yang menyalakan, kapan, dsb)
gumpalan iot history actuator lampu-kamar power
```

---

## 5. Cara Memanggil Tiap Modul via HTTP / cURL

Jika Anda mengembangkan modul baru atau memanggil API secara langsung dari terminal:

### svc-auth API

Semua request ke svc-auth melalui Nginx menggunakan prefix `/auth/v1/`:

```bash
# Register user baru
curl -X POST http://127.0.0.1:8080/auth/v1/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"passwordrahasia","name":"Nama User"}'

# Login (mendapatkan token)
curl -X POST http://127.0.0.1:8080/auth/v1/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"passwordrahasia"}'

# Response login:
# {
#   "access_token": "eyJhbGciOi...",
#   "refresh_token": "eyJhbGciOi...",
#   "user": { "id": "usr_abc123", "email": "user@example.com", "role": "user" }
# }

# Verifikasi token (internal — dipakai Nginx auth_request)
curl -X GET http://127.0.0.1:8080/auth/v1/verify \
  -H "Authorization: Bearer <TOKEN>"
# Response header yang dikembalikan ke Nginx:
# X-User-Id: usr_abc123
# X-User-Role: user
# X-Device-Id: (jika token milik device)
```

### svc-iot API

Semua request ke svc-iot membutuhkan header `Authorization: Bearer <TOKEN>` (diverifikasi oleh Nginx via svc-auth):

```bash
TOKEN="eyJhbGciOi..."

# Cek kemampuan history server (tanpa auth pun bisa via internal)
curl -s http://127.0.0.1:8080/iot/v1/history/capabilities \
  -H "Authorization: Bearer $TOKEN"
# {"enabled":true,"sensor":true,"actuator":true,"retention_days":0}

# Ambil daftar perangkat milik user
curl -s http://127.0.0.1:8080/iot/v1/devices \
  -H "Authorization: Bearer $TOKEN"

# Kirim perintah aktuator (misal menyalakan saklar)
curl -X POST http://127.0.0.1:8080/iot/v1/devices/lampu-kamar/command \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channel_id":"power","value":true}'

# Ambil log sensor (grafik riwayat suhu)
curl -s "http://127.0.0.1:8080/iot/v1/devices/living-room-sensor/history/sensor?channel=temperature&limit=50" \
  -H "Authorization: Bearer $TOKEN"

# Ambil log aktivasi aktuator (siapa yang menyalakan saklar)
curl -s "http://127.0.0.1:8080/iot/v1/devices/lampu-kamar/history/actuator?channel=power&limit=20" \
  -H "Authorization: Bearer $TOKEN"

# Berikan izin kontrol perangkat ke user lain (hanya pemilik)
curl -X POST http://127.0.0.1:8080/iot/v1/devices/lampu-kamar/permissions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"usr_teman123"}'
```

---

## 6. Standar Penulisan Modul Baru (svc-*)

Jika membuat modul backend baru di masa depan (misal `svc-billing`, `svc-storage`):

1. **Routing Nginx**: Buat file `/etc/nginx/conf.d/gumpalan/<nama_modul>.conf`
   ```nginx
   location /<nama_modul>/v1/ {
       auth_request /_verify;
       auth_request_set $user_id $upstream_http_x_user_id;
       proxy_set_header X-User-Id $user_id;

       proxy_pass http://127.0.0.1:<PORT_MODUL>/<nama_modul>/v1/;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
   }
   ```
2. **Identitas User**: Jangan implementasi auth ulang. Baca header `X-User-Id` dan `X-User-Role` yang sudah di-injek oleh Nginx dari respons svc-auth.
3. **Database**: Dukung prefix tabel dan SQLite out-of-the-box agar ramah perangkat SBC (STB Armbian).
4. **Port**: Alokasikan port statis unik (8001: auth, 8002: iot, 8003: modul berikutnya).
5. **Daftarkan di Installer**: Tambahkan entri modul di array `AVAILABLE_MODULES` pada `scripts/install.sh`.
