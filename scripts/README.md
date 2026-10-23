# Rencana Skrip Deployment

Direktori ini dicadangkan untuk dokumentasi alur deployment biner ke server tujuan (Set Top Box Armbian / Single Board Computer).

## Rencana Alur Deployment (Manual / Semi-Otomatis)

1. **Build Cross-Compile di Komputer Pengembangan**:
   ```bash
   # Di svc-auth
   make build-arm64
   # Di svc-iot
   make build-arm64
   ```
2. **Transfer Biner via SCP / RSYNC**:
   Menyalin biner terkompilasi `bin/*-linux-arm64` ke `/opt/gumpalan/<service>/bin/` di server target.
3. **Penyalinan File Konfigurasi**:
   - Salin file `.service` ke `/etc/systemd/system/`
   - Salin file `.env` ke `/etc/gumpalan/`
   - Salin file Nginx config ke `/etc/nginx/conf.d/gumpalan/`
4. **Reload Systemd dan Nginx**:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart gumpalan-auth gumpalan-iot
   sudo nginx -s reload
   ```

*Catatan: Sesuai prinsip keamanan perancangan, repositori ini tidak menyertakan skrip otomatis yang langsung mengeksekusi perintah SSH ke server target.*
