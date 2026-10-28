# Panduan Test Integrasi Lokal Gumpalan

Panduan ini menjelaskan cara menjalankan test integrasi lokal: `svc-auth` + nginx + Flutter di HP Android via ADB.

---

## Prasyarat

- `go` tersedia di PATH
- `flutter` tersedia di PATH
- `nginx` terinstall di mesin
- HP Android terhubung ke komputer via USB (ADB aktif)
- HP dan komputer berada di **jaringan yang sama** (WiFi atau LAN)

Cek perangkat ADB:

```bash
adb devices
```

Harus muncul setidaknya satu perangkat.

---

## Informasi Jaringan

IP mesin dev (digunakan Flutter di HP untuk akses server):

```bash
ip route get 1 | awk '{print $7; exit}'
```

Catat IP tersebut. Panduan ini menggunakan `<IP_MESIN>` sebagai placeholder.
Contoh nyata di mesin ini: `172.16.0.2`

---

## Langkah 1 — Jalankan svc-auth

Buka terminal baru, jalankan:

```bash
cd ~/Documents/Gumpalan/svc-auth
go run ./cmd/auth
```

Server berjalan di `http://127.0.0.1:8001`.

---

## Langkah 1b — Jalankan svc-iot

Buka terminal baru, jalankan:

```bash
cd ~/Documents/Gumpalan/svc-iot
go run ./cmd/iot
```

Server berjalan di `http://127.0.0.1:8002` (memuat konfigurasi `config/devices.yaml` dan auto-migrate database SQLite `data/iot.db`).

---

## Langkah 2 — Jalankan nginx

Buka terminal baru, jalankan:

```bash
nginx -c /home/anomali99/Documents/Gumpalan/infra-deploy/nginx/local-test.conf
```

Nginx akan berjalan di port `8080` sebagai reverse proxy.

Verifikasi berjalan:

```bash
curl -s http://127.0.0.1:8080/healthz
```

Harus mengembalikan `{"status":"ok"}`.

Untuk menghentikan nginx:

```bash
nginx -c /home/anomali99/Documents/Gumpalan/infra-deploy/nginx/local-test.conf -s quit
```

---

## Langkah 3 — Jalankan Flutter di HP via ADB

Buka terminal baru, jalankan:

```bash
cd ~/Documents/Gumpalan/app-shell
flutter run
```

Flutter akan build dan install APK ke HP secara otomatis via ADB.

---

## Langkah 4 — Skenario Test Registrasi Perangkat

### Lewat UI Flutter (end-to-end)

1. Buka app di HP.
2. Tap ikon **registrasi** (pojok kanan atas AppBar).
3. Isi nama perangkat (contoh: `HP Ruang Tamu`).
4. Tap **"Kirim Permintaan Pendaftaran"**.
5. Layar menampilkan **Device ID** dan instruksi terminal.
6. Di terminal mesin dev, jalankan:
   ```bash
   cd ~/Documents/Gumpalan/svc-auth
   go run ./cmd/auth device list
   ```
   Salin `DEVICE ID` perangkat yang statusnya `pending`.
7. Setujui perangkat:
   ```bash
   go run ./cmd/auth device approve <DEVICE_ID>
   ```
   Terminal mencetak token `tok_...` baru.
8. Di HP, tap **"Cek Status Persetujuan"**.
9. App otomatis redirect ke Home screen — token tersimpan, perangkat aktif.

### Lewat curl (verifikasi langsung tanpa UI)

**Daftar perangkat baru:**

```bash
curl -s -X POST http://127.0.0.1:8080/auth/v1/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test curl","publicKey":"dummy_key"}' | jq .
```

**Cek status perangkat:**

```bash
curl -s http://127.0.0.1:8080/auth/v1/register/<DEVICE_ID>/status | jq .
```

**Approve via CLI:**

```bash
cd ~/Documents/Gumpalan/svc-auth
go run ./cmd/auth device approve <DEVICE_ID>
```

**Verifikasi token (simulasi nginx auth_request):**

```bash
curl -i -H "Authorization: Bearer <TOKEN>" \
  http://127.0.0.1:8080/auth/v1/verify
```

Response harus `200 OK` dan header `X-Device-Id: <DEVICE_ID>`.

**Revoke perangkat:**

```bash
go run ./cmd/auth device revoke <DEVICE_ID>
```

**Verifikasi token setelah revoke:**

```bash
curl -i -H "Authorization: Bearer <TOKEN>" \
  http://127.0.0.1:8080/auth/v1/verify
```

Response harus `401 Unauthorized`.

---

## Langkah 5 — Skenario Test Modul IoT (Kustomisasi Dashboard & MQTT)

### 1. Test Endpoint REST svc-iot via curl

Gunakan token perangkat yang telah disetujui (`<TOKEN>`):

**Ambil daftar perangkat dan status channel:**
```bash
curl -s -H "Authorization: Bearer <TOKEN>" \
  http://127.0.0.1:8080/iot/v1/devices | jq .
```

**Kirim perintah kontrol ke channel perangkat:**
```bash
curl -s -X POST http://127.0.0.1:8080/iot/v1/devices/lampu-kamar/command \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"channel":"power","value":true}' | jq .
```

**Buat layout dashboard baru:**
```bash
curl -s -X POST http://127.0.0.1:8080/iot/v1/dashboards \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Ruang Tamu Saya",
    "isPublic": true,
    "layoutJson": "[{\"id\":\"w1\",\"widgetType\":\"toggle\",\"title\":\"Power Lampu\",\"deviceId\":\"lampu-kamar\",\"channelId\":\"power\"}]",
    "deviceIds": ["lampu-kamar"]
  }' | jq .
```

---

### 2. Test Lewat UI Flutter Mobile (Blynk-Style Customization)

1. Buka aplikasi Gumpalan di HP (pastikan status perangkat sudah disetujui).
2. Di tab utama **Dashboard IoT**, saat pertama kali dibuka akan muncul state kosong:
   - Teks: *"Dashboard IoT Belum Diatur"*.
   - Tombol **"Atur Dashboard Baru"** dan **"Jelajahi Layout Pengguna Lain"**.
3. Tap **"Atur Dashboard Baru"**:
   - Masukkan nama dashboard (contoh: `Kamar & Sensor`).
   - Aktifkan toggle *"Publikasikan Layout"* jika ingin dapat dilihat pengguna lain.
   - Tap **"Tambah Widget"**:
     - Pilih perangkat (misal `Sensor Ruang Tamu` atau `Lampu Kamar Tidur`).
     - Pilih channel (misal `Suhu`, `Power Lampu`, atau `Power Kipas`).
     - Tipe widget akan terdeteksi otomatis (Toggle untuk saklar, Slider untuk pengatur kecerahan/nilai, Gauge untuk telemetri suhu).
     - Atur label judul widget lalu tap **"Tambahkan Widget"**.
   - Tambahkan widget lain sesuai kebutuhan.
   - Atur urutan posisi widget dengan drag handle di sebelah kanan.
   - Tap **"Simpan"** di pojok kanan atas.
4. Kanvas dashboard aktif akan langsung menampilkan widget yang baru dibuat.
5. Tap saklar toggle atau geser slider: perintah dikirim ke MQTT broker dan state terupdate seketika via WebSocket stream (`/iot/v1/ws`).
6. Tap ikon **Jelajahi Layout Lain** untuk melihat dan menerapkan tata letak milik pengguna lain yang memiliki akses ke perangkat yang sama.

---

## Referensi Port

| Komponen | Alamat             | Keterangan                        |
| -------- | ------------------ | --------------------------------- |
| nginx    | `127.0.0.1:8080`   | Reverse proxy, entry point utama  |
| svc-auth | `127.0.0.1:8001`   | Backend autentikasi perangkat     |
| svc-iot  | `127.0.0.1:8002`   | Backend IoT, MQTT & WebSocket     |
| Flutter  | HP Android via ADB | App shell, akses via IP LAN mesin |

---

## Referensi Perintah CLI svc-auth

| Perintah                                | Fungsi                              |
| --------------------------------------- | ----------------------------------- |
| `go run ./cmd/auth`                     | Jalankan server HTTP :8001          |
| `go run ./cmd/auth device list`         | Tampilkan semua perangkat terdaftar |
| `go run ./cmd/auth device approve <id>` | Setujui perangkat + buat token      |
| `go run ./cmd/auth device revoke <id>`  | Cabut akses + hapus semua token     |

---

## Referensi Perintah CLI svc-iot

| Perintah | Fungsi |
| --- | --- |
| `go run ./cmd/iot` | Jalankan server HTTP & WebSocket :8002 |
| `go run ./cmd/iot device list` | Tampilkan perangkat dari config YAML |
| `go run ./cmd/iot perm list [dev_id]` | Tampilkan izin akses perangkat |
| `go run ./cmd/iot perm grant <dev_id> <target> [--role] [--readonly]` | Beri izin akses ke user / role |
| `go run ./cmd/iot perm revoke <perm_id>` | Cabut izin akses |

---

## Troubleshooting

**HP tidak bisa akses server:**

- Pastikan HP dan mesin di jaringan yang sama.
- Cek IP mesin: `ip route get 1 | awk '{print $7; exit}'`
- Cek firewall: `sudo ufw status` — port 8080 harus boleh masuk.
  Jika terblokir: `sudo ufw allow 8080/tcp`

**ADB tidak mendeteksi HP:**

- Aktifkan **USB Debugging** di HP (Pengaturan > Opsi Developer).
- Cabut dan pasang ulang kabel USB.
- Jalankan `adb kill-server && adb start-server`.

**Port 8080 sudah dipakai:**

```bash
ss -tlnp | grep 8080
```

Hentikan proses yang menempati port tersebut sebelum menjalankan nginx.

**nginx gagal start:**

```bash
nginx -t -c /home/anomali99/Documents/Gumpalan/infra-deploy/nginx/local-test.conf
```

Periksa log error: `cat /tmp/gumpalan-nginx-error.log`
