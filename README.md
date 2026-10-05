# Kasir Men Gede

Aplikasi kasir Android untuk Warung Babi Guling Men Gede. Data menu, transaksi, dan laporan disimpan di backend Laravel ([pos-backend](https://github.com/AdityaPramadiksa/pos-backend)). Cara memasang backend di hosting ada di `DEPLOY.md` repo itu.

Fitur utama:

- Pesanan makan di sini, bungkus, dan ojol (GoFood, GrabFood, ShopeeFood).
- Bill meja, termasuk menambah pesanan ke bill yang masih terbuka.
- Struk dan tiket dapur lewat printer Bluetooth (satu atau dua printer).
- Kas keluar, rekap shift, dan tutup shift dengan cetak settlement.
- **Mode offline**: kasir tetap berjalan saat sinyal hilang. Transaksi dikirim otomatis saat online lagi.

## Menjalankan saat pengembangan

```bash
flutter pub get
flutter run
```

Alamat server diatur dari halaman login (**Server … · Ubah**):

- IP laptop di WiFi yang sama, misalnya `192.168.1.10`. Port 8000 dipakai otomatis.
- Alamat hosting, misalnya `pos.namawarung.com`. Otomatis memakai https.

## Tes

```bash
flutter test
```

Uji ujung-ke-ujung terhadap server sungguhan (database uji, punya kasir PIN 1111):

```bash
flutter test test/e2e_offline_server_test.dart --dart-define=E2E_SERVER=127.0.0.1:8001
```

## Membuat APK rilis

APK ditandatangani dengan kunci rilis. Lokasi kunci diatur di `android/key.properties`; file itu tidak ikut git.

```bash
flutter build apk --release --split-per-abi
```

Hasilnya ada di `build/app/outputs/flutter-apk/`. Untuk HP/tablet Android modern, pakai `app-arm64-v8a-release.apk`. Kalau ragu, `flutter build apk --release` membuat satu APK untuk semua jenis HP, tapi ukurannya lebih besar.

Sebelum membuat versi baru, naikkan nomor versi di `pubspec.yaml`, misalnya `1.0.0+1` menjadi `1.0.1+2`. Angka setelah `+` wajib naik supaya APK bisa dipasang menimpa versi lama.

### Kunci rilis (penting)

File `kasir-men-gede.jks` dan `kasir-men-gede.key.properties` ada di `C:\Users\ASUS\keystores\`. **Simpan cadangannya** di tempat lain, misalnya Google Drive pribadi atau flashdisk.

Tanpa kunci yang sama, versi berikutnya tidak bisa dipasang menimpa aplikasi lama. Kasir harus menghapus aplikasi dulu, dan transaksi offline yang belum terkirim ikut hilang.

### Memasang di HP kasir

1. Salin APK ke HP, buka file itu, lalu izinkan "Instal aplikasi tidak dikenal" bila diminta.
2. Versi pengembangan lama (`pos_babi_guling`) adalah aplikasi yang berbeda. Hapus setelah aplikasi baru berjalan.
3. Buka **Kasir Men Gede**, atur alamat server, tekan **Tes koneksi**, lalu masuk dengan PIN saat online.
4. Atur printer di menu **Printer**.
