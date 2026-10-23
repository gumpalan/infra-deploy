# Panduan Memilih dan Mengonfigurasi Database

Gumpalan mendukung 4 jenis mesin database melalui konfigurasi environment `DB_CONNECTION`: `sqlite`, `mysql`, `mariadb`, `pgsql`.

## Panduan Memilih Mesin

| Mesin | Rekomendasi Penggunaan | Konsumsi RAM | Karakteristik |
| --- | --- | --- | --- |
| **SQLite** *(Default)* | Perangkat kecil (STB Armbian, Raspberry Pi 2/3/4/Zero, mini PC) | Sangat hemat (~10 MB) | Tanpa daemon terpisah, tersimpan dalam berkas tunggal, mode WAL aktif |
| **MariaDB / MySQL** | VPS kecil/sedang atau server rumahan bersama aplikasi lain | Sedang (~150-300 MB) | Skalabilitas multi-klien kuat, ekosistem administrasi umum (phpMyAdmin, DBeaver) |
| **PostgreSQL** | Server mandiri dengan beban tinggi / analitik jangka panjang | Sedang-Tinggi (~200-400 MB) | Integritas data sangat ketat, dukungan konkurensi tinggi |

> **Peringatan RAM**: Jika Anda menjalankan Gumpalan pada Set Top Box (STB) berbasis Armbian dengan total RAM 1GB - 2GB, **sangat disarankan tetap menggunakan SQLite**. Menjalankan MySQL/PostgreSQL daemon di perangkat tersebut akan menghabiskan 20-30% memori yang tersedia hanya untuk engine database.

---

## Contoh Pembuatan Database dan User

### MariaDB / MySQL

Jalankan perintah SQL berikut melalui terminal `mysql -u root -p`:

```sql
-- Database dan User untuk svc-auth
CREATE DATABASE gumpalan_auth CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'gumpalan_auth_user'@'127.0.0.1' IDENTIFIED BY 'ganti_dengan_kata_sandi_kuat';
GRANT ALL PRIVILEGES ON gumpalan_auth.* TO 'gumpalan_auth_user'@'127.0.0.1';

-- Database dan User untuk svc-iot
CREATE DATABASE gumpalan_iot CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'gumpalan_iot_user'@'127.0.0.1' IDENTIFIED BY 'ganti_dengan_kata_sandi_kuat';
GRANT ALL PRIVILEGES ON gumpalan_iot.* TO 'gumpalan_iot_user'@'127.0.0.1';

FLUSH PRIVILEGES;
```

### PostgreSQL

Jalankan perintah berikut melalui terminal `sudo -u postgres psql`:

```sql
-- Database dan User untuk svc-auth
CREATE USER gumpalan_auth_user WITH PASSWORD 'ganti_dengan_kata_sandi_kuat';
CREATE DATABASE gumpalan_auth OWNER gumpalan_auth_user;

-- Database dan User untuk svc-iot
CREATE USER gumpalan_iot_user WITH PASSWORD 'ganti_dengan_kata_sandi_kuat';
CREATE DATABASE gumpalan_iot OWNER gumpalan_iot_user;
```

---

## Catatan Isolasi Data

Secara default, masing-masing service (`svc-auth` dan `svc-iot`) memiliki database terpisah. Namun berkat konvensi prefix tabel (`auth_*`, `iot_*`), kedua service dapat diarahkan ke satu database MariaDB atau PostgreSQL yang sama jika ingin menghemat jumlah database pada server kecil.
