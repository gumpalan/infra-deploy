# Catatan Integrasi Tasmota

Direktori ini mendokumentasikan pengaturan perangkat Sonoff/ESP8266/ESP32 yang diflash menggunakan firmware open-source Tasmota.

## Setelan MQTT Standar

Pada antarmuka web Tasmota (**Configuration -> Configure MQTT**):

- **Host**: IP lokal server Gumpalan (misal `192.168.1.100`)
- **Port**: `1883`
- **Client**: `DVES_%06X`
- **User**: Username MQTT yang terdaftar di Mosquitto
- **Password**: Password MQTT
- **Topic**: Identifikasi unik perangkat (contoh: `kipas1`, `saklar_tamu`)
- **Full Topic**: `%prefix%/%topic%/` (biarkan default Tasmota)

## Konvensi Topik Tasmota

1. **Kirim Perintah**:
   `cmnd/<topic>/POWER` dengan payload `ON`, `OFF`, atau `TOGGLE`.
2. **Penerimaan Status**:
   `stat/<topic>/POWER` berisi `ON` atau `OFF`.
3. **Telemetri Periodik**:
   `tele/<topic>/STATE` (JSON memuat status WiFi, relay, dan uptime).

## Catatan Lisensi

Firmware Tasmota berlisensi **GPL-3.0**.
- Menggunakan Tasmota pada perangkat otomasi pribadi sepenuhnya aman dan legal.
- Jika Anda berencana menjual perangkat keras siap pakai yang sudah diflash firmware Tasmota ke pihak lain, perhatikan kewajiban lisensi GPLv3 untuk menyediakan source code modifikasi dan instruksi instalasi firmware.
