# PhotoE-Zi: Google Drive OAuth 2.0 Configuration Guide

Dokumen ini menjelaskan langkah mudah membuat **OAuth 2.0 Desktop Client ID** pribadi di **Google Cloud Console** agar saat login Google, nama aplikasi terdeteksi sebagai **PhotoE-Zi** (bukan rclone atau aplikasi pihak ketiga lainnya) serta menjamin kuota upload penuh (10.000.000 query/hari gratis).

---

## Langkah 1: Buat Project di Google Cloud Console

1. Buka [Google Cloud Console](https://console.cloud.google.com/).
2. Login dengan akun Google Anda (`lyvt.photo2@gmail.com`).
3. Klik dropdown project di bagian atas, pilih **New Project**.
4. Isi **Project name**: `PhotoE-Zi` (atau `PhotoE-Zi Studio`).
5. Klik **Create**.

---

## Langkah 2: Aktifkan Google Drive API

1. Masuk ke menu **APIs & Services** > **Enabled APIs & Services**.
2. Klik tombol **+ ENABLE APIS AND SERVICES** di bagian atas.
3. Cari: `Google Drive API`.
4. Klik **Google Drive API**, lalu klik tombol biru **ENABLE**.

---

## Langkah 3: Konfigurasi OAuth Consent Screen

1. Di menu sebelah kiri, klik **OAuth consent screen** (atau **Branding**).
2. Pilih User Type: **External** (lalu klik **Create**).
3. Isi informasi aplikasi:
   * **App name**: `PhotoE-Zi`
   * **User support email**: Email Anda (misal `lyvt.photo2@gmail.com`)
   * **Developer contact information**: Email Anda.
4. Klik **Save and Continue**.
5. Pada bagian **Scopes**, klik **Add or Remove Scopes**:
   * Pilih scope: `.../auth/drive` dan `.../auth/drive.file`
   * Klik **Update**, lalu **Save and Continue**.
6. Pada bagian **Test users**:
   * Tambahkan email Google Anda (`lyvt.photo2@gmail.com`) sebagai Test User.
   * Klik **Save and Continue** dan selesai.

---

## Langkah 4: Buat OAuth 2.0 Desktop Client ID

1. Di menu sebelah kiri, klik **Credentials**.
2. Klik **+ CREATE CREDENTIALS** di atas > pilih **OAuth client ID**.
3. Pada **Application type**, pilih: **Desktop app**.
4. Isi **Name**: `PhotoE-Zi Desktop App`.
5. Klik **Create**.
6. Google akan menampilkan modal berisi:
   * **Your Client ID**: (contoh: `1234567890-abcdefg.apps.googleusercontent.com`)
   * **Your Client Secret**: (contoh: `GOCSPX-xxxxxx`)

---

## Langkah 5: Masukkan ke PhotoE-Zi

Ada 2 cara praktis menggunakan Client ID tersebut di PhotoE-Zi:

### Cara A: Langsung di Aplikasi (Permanen & Tersimpan)
1. Buka PhotoE-Zi, klik icon Google Drive / **Configure**.
2. Masukkan **Client ID** dan **Client Secret** Anda di formulir Google OAuth PhotoE-Zi.
3. Klik **Save PhotoE-Zi Credentials**.
4. Kini setiap kali Anda mengklik **Sign in with Google**, pop-up browser Google akan langsung menampilkan:
   > **"Lanjutkan ke PhotoE-Zi"** / **"PhotoE-Zi ingin mengakses Akun Google Anda"**

### Cara B: Build-time Environment Variable (Production Release)
Saat melakukan build atau run aplikasi:
```bash
flutter run -d macos --dart-define=PHOTOE_ZI_GDRIVE_CLIENT_ID="YOUR_CLIENT_ID.apps.googleusercontent.com" --dart-define=PHOTOE_ZI_GDRIVE_CLIENT_SECRET="YOUR_CLIENT_SECRET"
```
