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
Output normal:

```
2026/xx/xx xx:xx:xx Server svc-auth berjalan di http://127.0.0.1:8001
```

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

## Referensi Port

| Komponen | Alamat             | Keterangan                        |
| -------- | ------------------ | --------------------------------- |
| nginx    | `127.0.0.1:8080`   | Reverse proxy, entry point utama  |
| svc-auth | `127.0.0.1:8001`   | Backend autentikasi perangkat     |
| svc-iot  | `127.0.0.1:8002`   | Backend IoT (belum dijalankan)    |
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
