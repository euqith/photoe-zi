github: https://github.com/euqith/photoe-zi.git

buatkan planning dan epic di github.

# Product Requirements Document (PRD) & Sprint Plan
**Project Name:** Instant Tether & Film Simulation Mobile App  (PhotoE-Zi)
**Target Platforms:** Android (API 26+) & iOS (iOS 15+) — Responsive Smartphone & Tablet  
**AI Agent Execution Rule:** Read this entire document before writing code. Execute sequentially per Sprint & Issue in Section 5. Do not move to the next issue until all Acceptance Criteria (AC) are verified.

---

## 1. Overview & Target Hardware

Aplikasi mobile *cross-platform* untuk kebutuhan *tethered shooting* portabel. Aplikasi menghubungkan kamera digital secara langsung ke smartphone/tablet agar hasil foto langsung tampil instan untuk dilihat oleh model/klien, otomatis menerapkan *Film Simulation* (3D LUT `.cube`) secara *real-time*, dan langsung mengunggah hasil jepretan ke Google Drive.

### Target Cameras & Protocol Realities
| Kamera | Koneksi USB (Kabel) | Koneksi Wi-Fi | Catatan Teknis Implementasi |
| :--- | :--- | :--- | :--- |
| **Canon EOS 6D** | **Support penuh (PTP/USB)** | **Support (PTP/IP)** | Paling stabil untuk *wired tethering* via protokol PTP standar. |
| **Canon EOS M100** | **Support terbatas (PTP/USB)** | **Support (PTP/IP)** | Menarik foto baru via PTP Event (`ObjectAdded`). |
| **Fujifilm X-T10** | **Tidak support USB Tethering** | **Support (Fujifilm Wi-Fi Protocol)** | X-T10 mengunci tombol *shutter* jika dicolok USB (mode Mass Storage). Wajib menggunakan jalur **Wi-Fi (PTP/IP proprietary Fujifilm)**. |

---

## 2. Core Features & Functional Requirements

### A. Camera Connection & Instant Capture (Tethering Engine)
- **Dual Connection Support:**
  - *USB-OTG (Wired):* Auto-detect saat kabel USB kamera dicolok (Android via `UsbManager`, iOS via `ImageCaptureCore`).
  - *Wi-Fi (Wireless):* Auto-discover IP kamera saat perangkat terhubung ke Wi-Fi/Hotspot kamera.
- **Fast Preview Pipeline:**
  - Mendengarkan event `ObjectAdded` dari kamera.
  - Tahap 1: Tarik *embedded thumbnail/preview* JPEG terlebih dahulu (< 1 detik) agar layar langsung merespons.
  - Tahap 2: Tarik file JPEG resolusi penuh di *background* dan ganti preview secara *seamless*.
- **Mock Camera Mode (Development):**
  - Mode simulasi yang otomatis memasukkan foto sampel dari penyimpanan lokal setiap 3 detik untuk pengujian UI, LUT, dan Google Drive tanpa memerlukan kamera fisik.

### B. Instant Film Simulation Engine (3D LUT)
- **Real-Time Rendering:** Menggunakan GPU Shader (GLSL / CoreImage / OpenGL ES) untuk merender 3D LUT format `.cube` (17x17x17 & 33x33x33) secara non-destruktif tanpa *lag*.
- **Auto-Apply on Import:** Setiap foto baru yang masuk dari kamera langsung otomatis ditampilkan dengan *preset* Film Simulation yang sedang aktif.
- **Preset Management:**
  - Preset bawaan di `assets/luts/` (Classic Chrome, Classic Neg, Kodachrome, Japanese Airy/Bright, B&W Acros).
  - Fitur impor file `.cube` kustom dari penyimpanan perangkat.
- **Controls:**
  - Slider intensitas LUT (0% – 100%).
  - Tekan & tahan (*long-press*) pada foto untuk melihat perbandingan *Before / After* (Original vs Film Sim).
- **Fast Baking (Export):** Merender foto resolusi penuh + LUT menjadi file JPEG baru (kualitas 90–95%, mempertahankan metadata EXIF) di *background thread/isolate* sebelum diunggah ke Google Drive.

### C. Direct Google Drive Cloud Sync (Auto-Upload)
- **Authentication:** Integrasi Google Sign-In (OAuth 2.0) dengan scope `https://www.googleapis.com/auth/drive.file`.
- **Automatic Session Folder:**
  - Saat fotografer membuat sesi baru (misal: `"Studio_A"`), aplikasi otomatis membuat struktur folder di Google Drive: `TetherApp / YYYY-MM-DD_NamaSesi`.
  - Opsi memilih folder tujuan kustom di Google Drive.
- **Auto-Upload Modes:**
  - *Auto-Upload All:* Setiap foto masuk langsung masuk antrean unggah.
  - *Upload Favorites Only:* Hanya mengunggah foto yang ditandai *Love/Favorite* oleh model/fotografer.
  - *Manual Upload:* Unggah foto tertentu secara manual.
- **File Variant Selection:**
  - *Baked Film Sim (JPEG):* Mengunggah hasil yang sudah diaplikasikan LUT (siap pakai/posting).
  - *Original JPEG:* Mengunggah file asli dari kamera.
  - *Both:* Mengunggah keduanya ke subfolder terpisah (`/Original` dan `/Edited`).
- **Resilient Background Upload Queue:**
  - Menggunakan *Resumable Upload API* Google Drive dengan antrean persisten di SQLite lokal.
  - Jika koneksi internet putus/lambat (misal HP sedang terhubung ke Wi-Fi kamera), foto tetap antre dan otomatis lanjut mengunggah saat koneksi internet kembali tersedia.
- **Instant Client Share (QR Code):**
  - Tombol untuk mengubah *permission* folder sesi menjadi *"Anyone with the link can view"* dan menampilkan **QR Code** di layar agar model/klien bisa langsung *scan* dan mengunduh foto di lokasi.

---

## 3. UI/UX Layout Specification — Pro Tether Workspace

Menggunakan tema *neutral dark studio* ala **Photoshop / Capture One / Lightroom** agar warna foto dan simulasi film (LUT) tidak terdistorsi oleh warna UI.

### Color Palette & Typography
- **Canvas Background:** `#0F0F10` (Hitam pekat netral di belakang foto utama)
- **Panel / Toolbar Surface:** `#1A1A1D` (Abu gelap untuk Top Bar, Right Inspector, dan Filmstrip)
- **Panel Border / Divider:** `#2A2A2E` (Garis tipis 1px pemisah antar panel)
- **Active Selection Accent:** `#F59E0B` (Amber) atau `#FFFFFF` (Border 2px pada thumbnail foto yang sedang dipilih)
- **Typography:** Monospace untuk angka EXIF & persentase (`ISO 400 · 1/250s · f/1.8`), Sans-serif bersih untuk label UI.

### Desktop / Tablet Landscape Layout (Primary Pro Workspace)
```text
+-----------------------------------------------------------------------------------+
| [<] Session: Studio_A   [● Canon 6D USB]   [Zen] [Before/After]   [☁️ 14/15] [QR] |  <- Top Bar (48px)
+---------------------------------------------------------------+-------------------+
|                                                               |  HISTOGRAM (RGB)  |
|                                                               |  [  /\   /\_   ]  |
|                                                               +-------------------+
|                                                               |  FILM SIMULATION  |
|                                                               |  [Classic Chrome] |
|                     MAIN PHOTO CANVAS                         |  [Classic Neg   ] |
|                 (Foto Terakhir / Terpilih)                    |  [Japanese Airy ] |
|                                                               |  [+ Import .cube] |
|              • Pinch-to-Zoom & Pan (up to 400%)               |  Intensity: 85%   |
|              • Long-press untuk Before/After                  |  [=======o--]     |
|                                                               +-------------------+
|                                                               |  INFO & EXIF      |
|  [♥ Fav]  [✕ Reject]                f/1.8 · 1/250s · ISO 200  |  IMG_4021.JPG     |
+---------------------------------------------------------------+  Canon EOS 6D     |
| Filter: [All (24)] [♥ 8] [Lock Latest: ON]                    |  Drive: Synced ✓  |
| +--------+ +--------+ +--------+ +--------+ +--------+        |  [Upload Now]     |
| | IMG_20 | | IMG_21 | | IMG_22 | | IMG_23 | |[IMG_24]|  -->   |                   |
| |   ✓    | |  ♥ ✓   | |   ✓    | |  ♥ ↻   | | *NEW*  |        |                   |
| +--------+ +--------+ +--------+ +--------+ +--------+        +-------------------+
   ^-- Bottom Filmstrip (List Foto Sebelumnya, Height ~105px)     ^-- Right Inspector
                                                                      (Collapsible, ~280px)
```

### Perilaku Interaksi Utama
1. **Main Photo Canvas (Dominan ~75% layar):**
   - Menampilkan foto terbaru secara otomatis jika toggle **`Lock Latest`** aktif.
   - Jika fotografer/model mengklik foto lama di *filmstrip*, canvas berpindah ke foto tersebut dan **`Lock Latest`** sementara berhenti (tersedia tombol cepat *"Jump to Latest"* saat foto baru masuk).
   - Overlay tipis di sudut bawah canvas (bisa di-hide): tombol cepat **Favorite (♥)**, **Reject (✕)**, dan ringkasan EXIF 1 baris.
2. **Bottom Filmstrip (Daftar Foto Sebelumnya):**
   - Barisan *thumbnail* horizontal yang bisa di-scroll mulus (dengan opsi *toggle* pindah ke sisi kiri secara vertikal).
   - Foto aktif ditandai dengan *border* terang 2px.
   - *Micro-badges* di sudut tiap thumbnail: Kiri atas untuk ikon **♥** (atau opacity 40% jika di-reject); Kanan bawah untuk status Google Drive (`✓` hijau = synced, spinner = uploading, `•` abu = queued, `!` merah = failed).
3. **Right Inspector Panel (Collapsible ~280px):**
   - Bisa disembunyikan dengan 1 klik agar *Main Photo Canvas* melebar penuh.
   - Berisi: **RGB Histogram**, **Film Simulation (LUT) Selector + Intensity Slider**, **EXIF Detail**, dan **Google Drive Sync Control**.
4. **Zen / Model Clean Mode (1-Tap Toggle di Top Bar):**
   - Menyembunyikan *Right Inspector* dan meredupkan *Top Bar*, menyisakan **Main Photo Canvas** (besar penuh) dan opsional *Bottom Filmstrip* tipis agar model bisa melihat hasil jepretan tanpa gangguan panel teknis.
5. **Smartphone Portrait Layout (Responsive Fallback):**
   - **Top Bar (Compact):** Status Kamera, tombol Zen Mode, Status Drive & QR Share.
   - **Main Photo Canvas:** Mengambil ~65% tinggi layar di bagian tengah.
   - **Bottom Filmstrip:** Tepat di bawah foto utama (height ~85px).
   - **Right Inspector:** Berubah menjadi **Draggable Bottom Sheet** yang dipicu dari tab kecil di bawah filmstrip (`[Film Sim]`, `[Histogram/EXIF]`, `[Drive Sync]`).

---

## 4. Tech Stack, Architecture & Core Contracts

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod (`flutter_riverpod`)
- **Routing:** `go_router`
- **Local Database:** Drift (SQLite)
- **Camera Native Bridge:** Flutter `MethodChannel` & `EventChannel`
  - *Android:* Kotlin (`android.hardware.usb` untuk PTP USB, Kotlin Coroutines Socket untuk PTP/IP).
  - *iOS:* Swift (`ImageCaptureCore` untuk USB, `Network.framework` untuk PTP/IP).
- **Image/LUT Processing:** Flutter Fragment Shader / Native GPU (`CIColorCube` iOS, OpenGL ES Android).
- **Cloud Sync:** `google_sign_in`, `googleapis` (Drive API v3), `workmanager` / background isolate, `qr_flutter`.

### Folder Structure
```text
lib/
├── core/
│   ├── constants/         # Dark studio theme, colors, constants
│   ├── database/          # Drift schemas (Sessions, Photos, UploadQueue)
│   └── utils/
├── features/
│   ├── camera/
│   │   ├── domain/        # BaseCameraDriver interface & IncomingPhoto model
│   │   ├── data/          # MockCameraDriver, CanonPtpDriver, FujiWifiDriver
│   │   └── presentation/  # Connection status modal & camera selector
│   ├── tether_view/
│   │   └── presentation/  # Main canvas, bottom filmstrip, right inspector, EXIF, RGB Histogram
│   ├── film_sim/
│   │   ├── domain/        # CubeLutParser & LutPreset model
│   │   └── data/          # GPU Shader renderer & LutBakerService
│   └── cloud_sync/
│       ├── data/          # GoogleDriveService & ResumableUploadQueue
│       └── presentation/  # Sync status panel, Drive settings, QR Share modal
└── main.dart
```

### Core Interface: `BaseCameraDriver`
```dart
enum CameraConnectionType { usb, wifi, mock }
enum CameraConnectionState { disconnected, connecting, connected, error }

class IncomingPhoto {
  final String id;
  final String fileName;
  final Uint8List? previewBytes;    // Fast embedded thumbnail
  final String? fullResLocalPath;   // Saved full-res path
  final Map<String, dynamic> exifData;
  final DateTime capturedAt;

  IncomingPhoto({
    required this.id,
    required this.fileName,
    this.previewBytes,
    this.fullResLocalPath,
    required this.exifData,
    required this.capturedAt,
  });
}

abstract class BaseCameraDriver {
  String get driverName;
  CameraConnectionType get connectionType;

  Stream<CameraConnectionState> get connectionStateStream;
  Stream<IncomingPhoto> get onNewPhotoStream;

  Future<bool> connect({String? ipAddress, int? port});
  Future<void> disconnect();
  Future<String> downloadFullResolution(String photoId, String targetDir);
}
```

### Core Interface: `CloudSyncService`
```dart
enum UploadStatus { pending, bakingLut, uploading, completed, failed }
enum UploadVariant { bakedLut, original, both }

abstract class CloudSyncService {
  Future<bool> signIn();
  Future<void> signOut();
  Future<String> createSessionFolder(String sessionName);
  Future<void> enqueuePhoto({
    required String localPhotoId,
    required String driveFolderId,
    required UploadVariant variant,
    String? activeLutId,
  });
  Future<String> generateShareableFolderLink(String driveFolderId);
  Stream> get uploadProgressStream; // photoId -> 0.0 to 1.0
}
```

---

## 5. Development Roadmap & GitHub Sprint Planning

### SPRINT 1 — Epic #1: Core Foundation, Local DB & Mock Tethering UI
**Goal:** Aplikasi sudah bisa dijalankan di emulator/HP dengan alur tethering lengkap bergaya Photoshop menggunakan `MockCameraDriver`.

#### Issue #1.1: Project Initialization & Clean Architecture Setup
- **Labels:** `epic-1`, `setup`, `architecture`
- **Description:** Inisialisasi proyek Flutter dengan struktur folder sesuai Section 4, setup `flutter_riverpod`, routing (`go_router`), dan tema *neutral dark studio*.
- **Acceptance Criteria:**
  - [ ] Proyek Flutter terinisialisasi untuk target Android (minSdk 26) & iOS (15.0+).
  - [ ] Struktur folder `core/` dan `features/` (`camera`, `tether_view`, `film_sim`, `cloud_sync`) terbentuk.
  - [ ] Tema UI *neutral dark studio* (`#0F0F10` canvas, `#1A1A1D` panel, `#2A2A2E` border) aktif secara default.

#### Issue #1.2: Local Database Schema (Sessions, Photos & Upload Queue)
- **Labels:** `epic-1`, `database`
- **Description:** Implementasi database lokal menggunakan Drift (SQLite) untuk menyimpan sesi pemotretan, foto masuk, status *culling*, LUT aktif, dan antrean Google Drive.
- **Acceptance Criteria:**
  - [ ] Tabel `Sessions` (`id`, `name`, `createdAt`, `driveFolderId`, `activeLutId`).
  - [ ] Tabel `Photos` (`id`, `sessionId`, `fileName`, `previewPath`, `fullResPath`, `isFavorite`, `isRejected`, `exifJson`, `capturedAt`).
  - [ ] Tabel `UploadQueue` (`id`, `photoId`, `variant`, `status`, `retryCount`, `remoteFileId`, `progress`).
  - [ ] CRUD dasar dan unit test sederhana untuk pembuatan sesi & penyimpanan foto berjalan sukses.

#### Issue #1.3: `BaseCameraDriver` Contract & `MockCameraDriver`
- **Labels:** `epic-1`, `camera`, `testing`
- **Description:** Buat *abstract interface* `BaseCameraDriver` dan implementasikan `MockCameraDriver` yang mensimulasikan kamera memotret setiap 3 detik (mengirim preview dulu, lalu full-res 500ms kemudian).
- **Acceptance Criteria:**
  - [ ] `BaseCameraDriver` memiliki stream `connectionStateStream` dan `onNewPhotoStream`.
  - [ ] `MockCameraDriver` bisa di-toggle Connect/Disconnect dari UI.
  - [ ] Foto dummy otomatis tersimpan ke storage lokal & tercatat di database saat mode Mock aktif.

#### Issue #1.4: Pro Tether Workspace UI (Photoshop-Style Canvas, Filmstrip & Responsive Inspector)
- **Labels:** `epic-1`, `ui`, `tether-view`
- **Description:** Bangun layar utama pemotretan mengacu pada Section 3 dengan tata letak ala Photoshop/Capture One: foto utama berukuran besar di tengah, daftar thumbnail foto sebelumnya di filmstrip bawah, dan panel inspector yang bisa disembunyikan di sisi kanan.
- **Acceptance Criteria:**
  - [ ] Tema *neutral dark studio* (`#0F0F10` canvas, `#1A1A1D` panel, `#2A2A2E` border) diterapkan.
  - [ ] **Main Photo Canvas:** Menampilkan foto terbaru/terpilih dengan dukungan *pinch-to-zoom* (hingga 400%), *pan*, *double-tap zoom*, dan toggle `Lock Latest` (otomatis menampilkan foto baru yang masuk + tombol *"Jump to Latest"* jika sedang melihat foto lama).
  - [ ] **Bottom Filmstrip:** Menampilkan seluruh foto sebelumnya dalam sesi, otomatis *auto-scroll* ke foto terbaru, highlight border 2px pada foto aktif, filter (`All` / `Favorites`), serta *micro-badges* untuk status Favorite dan Google Drive sync.
  - [ ] **Right Inspector Panel (Collapsible):** Pada Tablet/Landscape tampil di sisi kanan (~280px, bisa di-hide); pada HP Portrait otomatis berubah menjadi *Draggable Bottom Sheet*.
  - [ ] **Zen / Model Mode:** Tombol 1-tap untuk menyembunyikan panel teknis sehingga fokus penuh pada foto utama dan navigasi foto untuk model.

#### Issue #1.5: EXIF Metadata Reader & Real-Time RGB Histogram
- **Labels:** `epic-1`, `ui`, `image-processing`
- **Description:** Implementasikan widget EXIF dan grafik Histogram RGB di dalam Right Inspector Panel (dan Bottom Sheet pada mode Portrait).
- **Acceptance Criteria:**
  - [ ] Membaca dan menampilkan Aperture (`f/`), Shutter Speed, ISO, Focal Length, dan Camera Model dengan font monospace.
  - [ ] Menghitung dan merender grafik Histogram RGB (Red, Green, Blue, Luminance) di *background isolate* agar UI tetap 60fps.

---

### SPRINT 2 — Epic #2: Instant Film Simulation Engine (3D LUT)
**Goal:** Foto yang masuk langsung tampil dengan simulasi film `.cube` secara instan di GPU dan bisa di-*bake* menjadi JPEG siap unggah.

#### Issue #2.1: `.cube` 3D LUT Parser & Preset Manager
- **Labels:** `epic-2`, `film-sim`
- **Description:** Bangun parser untuk membaca file standar 3D LUT format `.cube` (17x17x17 & 33x33x33) serta manajemen daftar preset.
- **Acceptance Criteria:**
  - [ ] Parser berhasil mengonversi file `.cube` menjadi data tekstur 3D/2D LUT siap baca GPU.
  - [ ] Menyertakan minimal 4 preset bawaan di `assets/luts/` (Classic Chrome, Classic Neg, Japanese Airy, B&W Acros).
  - [ ] Fitur tombol "Import `.cube`" dari penyimpanan perangkat ke direktori preset aplikasi.

#### Issue #2.2: Real-Time GPU LUT Renderer & Preview Controls
- **Labels:** `epic-2`, `film-sim`, `gpu`
- **Description:** Implementasikan shader GPU untuk menerapkan LUT secara *real-time* non-destruktif pada Main Photo Canvas.
- **Acceptance Criteria:**
  - [ ] Pergantian antar preset LUT di layar terasa instan (< 100ms).
  - [ ] Slider intensitas LUT (0% – 100%) bekerja mulus secara *real-time*.
  - [ ] Fitur *Long-press* pada foto langsung menampilkan gambar Original (*Before*), dan kembali ke Film Sim (*After*) saat dilepas.

#### Issue #2.3: Auto-Apply on Import & Background JPEG Baker
- **Labels:** `epic-2`, `film-sim`, `performance`
- **Description:** Setiap foto baru yang masuk otomatis menggunakan LUT aktif sesi, dan sistem menyediakan `LutBakerService` untuk merender LUT ke file JPEG resolusi penuh di *background*.
- **Acceptance Criteria:**
  - [ ] Foto baru dari `onNewPhotoStream` langsung tampil dengan LUT yang sedang dipilih.
  - [ ] `LutBakerService` menghasilkan file JPEG baru (kualitas 90–95%, mempertahankan EXIF) di *background thread/isolate*.
  - [ ] Waktu *baking* untuk foto ~20MP di bawah 1 detik pada perangkat mid-range.

---

### SPRINT 3 — Epic #3: Direct Google Drive Auto-Upload & Client Share
**Goal:** Foto hasil jepretan otomatis terunggah ke folder sesi Google Drive secara persisten (tahan putus koneksi) dan bisa dibagikan ke model via QR Code.

#### Issue #3.1: Google Sign-In OAuth 2.0 & Auto Session Folder
- **Labels:** `epic-3`, `gdrive`, `auth`
- **Description:** Integrasi login akun Google dengan scope `drive.file` dan pembuatan folder otomatis di Google Drive setiap kali sesi baru dimulai.
- **Acceptance Criteria:**
  - [ ] User bisa login/logout akun Google di Settings & melihat status akun.
  - [ ] Saat membuat sesi baru (dengan Cloud Sync aktif), aplikasi otomatis membuat folder `TetherApp/YYYY-MM-DD_NamaSesi` di Google Drive dan menyimpan `driveFolderId` ke DB lokal.
  - [ ] Tersedia opsi memilih folder parent kustom di Google Drive.

#### Issue #3.2: Resilient Background Resumable Upload Queue
- **Labels:** `epic-3`, `gdrive`, `background`
- **Description:** Bangun *upload manager* berbasis antrean SQLite (`UploadQueue`) menggunakan Google Drive Resumable Upload API.
- **Acceptance Criteria:**
  - [ ] Mendukung *resumable upload* dengan pelaporan progress (`0.0` – `1.0`) secara *real-time*.
  - [ ] Jika internet putus (offline), antrean otomatis *pause* dan langsung *auto-resume* saat internet kembali tersedia.
  - [ ] Mekanisme *exponential backoff retry* jika error, plus tombol manual "Retry Failed".

#### Issue #3.3: Auto-Upload Triggers & File Variant Selector
- **Labels:** `epic-3`, `gdrive`, `film-sim`
- **Description:** Hubungkan pipeline kamera & `LutBakerService` dengan `UploadQueue` sesuai preferensi fotografer.
- **Acceptance Criteria:**
  - [ ] Pilihan mode unggah: **Auto-Upload All**, **Favorites Only** (otomatis masuk antrean begitu tombol *♥* ditekan), atau **Manual**.
  - [ ] Pilihan varian file: **Baked Film Sim (JPEG)**, **Original JPEG**, atau **Both** (masuk ke subfolder `/Edited` dan `/Original`).
  - [ ] Jika varian *Baked* dipilih, sistem otomatis menjalankan `LutBakerService` sebelum memulai upload.

#### Issue #3.4: Filmstrip Sync Badges & Instant QR Code Share
- **Labels:** `epic-3`, `gdrive`, `ui`
- **Description:** Tampilkan status sinkronisasi per foto secara visual dan sediakan modal QR Code untuk akses folder klien.
- **Acceptance Criteria:**
  - [ ] Setiap thumbnail di *filmstrip* menampilkan *micro-badge* status: `Queued`, `Uploading`, `Synced ✓`, `Failed !`.
  - [ ] Tombol "QR / Share Session" di Top Bar mengubah permission folder sesi di Drive menjadi *Anyone with the link (Viewer)* dan memunculkan dialog **QR Code** besar + tombol *Copy Link*.

---

### SPRINT 4 — Epic #4: Native Camera Bridge — Canon EOS 6D & M100
**Goal:** Aplikasi terhubung ke kamera Canon fisik via kabel USB-OTG dan Wi-Fi menggunakan protokol PTP.

#### Issue #4.1: Native Platform Channel Scaffolding (Kotlin & Swift)
- **Labels:** `epic-4`, `native-android`, `native-ios`, `camera`
- **Description:** Buat jembatan komunikasi Flutter `MethodChannel` & `EventChannel` beserta konfigurasi permission native.
- **Acceptance Criteria:**
  - [ ] Kontrak payload antara Dart, Kotlin, dan Swift terdokumentasi dan teruji dengan dummy event.
  - [ ] Permission Android (`USB_PERMISSION`, `ACCESS_WIFI_STATE`, `CHANGE_NETWORK_STATE`) dan iOS (`NSLocalNetworkUsageDescription`) terkonfigurasi.

#### Issue #4.2: Android Wired USB-OTG Driver (Canon PTP)
- **Labels:** `epic-4`, `native-android`, `canon`
- **Description:** Implementasikan driver PTP over USB menggunakan `android.hardware.usb.UsbManager` untuk Canon EOS 6D dan M100.
- **Acceptance Criteria:**
  - [ ] Auto-detect saat Canon 6D / M100 dicolok via kabel USB-OTG & meminta izin USB.
  - [ ] Berhasil melakukan PTP `OpenSession` dan mendengarkan event `0x4002` (`ObjectAdded`) / Canon EOS Event.
  - [ ] Menarik *thumbnail* terlebih dahulu (`GetThumb`), lalu *full-res* (`GetObject`) tanpa mengunci *shutter*.

#### Issue #4.3: Cross-Platform Wi-Fi PTP/IP Driver (Canon 6D & M100)
- **Labels:** `epic-4`, `native-android`, `native-ios`, `canon`
- **Description:** Implementasikan protokol PTP/IP via TCP Socket (port `15740`) di Kotlin (Android) dan Swift `Network.framework` (iOS).
- **Acceptance Criteria:**
  - [ ] Berhasil melakukan `Init_Command_Request` & `Init_Event_Request` ke IP kamera Canon saat terhubung ke Wi-Fi kamera.
  - [ ] Berhasil menangkap foto baru secara otomatis baik di Android maupun iOS.

#### Issue #4.4: iOS USB Tethering Bridge (`ImageCaptureCore`)
- **Labels:** `epic-4`, `native-ios`, `canon`
- **Description:** Implementasikan pembacaan kamera USB untuk iPadOS/iOS menggunakan framework Apple `ImageCaptureCore`.
- **Acceptance Criteria:**
  - [ ] Mendeteksi Canon 6D/M100 yang terhubung via kabel USB-C ke iPad/iPhone.
  - [ ] Callback `cameraDevice(_:didAdd:)` langsung memicu alur preview cepat & download ke Flutter.

---

### SPRINT 5 — Epic #5: Native Camera Bridge — Fujifilm X-T10 (Wi-Fi)
**Goal:** Fujifilm X-T10 bisa melakukan *wireless tethering* mulus ke Android & iOS tanpa mengunci tombol shutter.

#### Issue #5.1: Fujifilm X-T10 Wi-Fi Handshake & Registration
- **Labels:** `epic-5`, `native-android`, `native-ios`, `fujifilm`
- **Description:** Implementasikan protokol proprietary Wi-Fi TCP/IP Fujifilm di Kotlin & Swift.
- **Acceptance Criteria:**
  - [ ] Auto-detect koneksi ke SSID Wi-Fi Fujifilm X-T10 (default gateway `192.168.0.1`).
  - [ ] Berhasil menyelesaikan proses *client registration handshake* agar kamera mengenali HP/tablet sebagai penerima foto.

#### Issue #5.2: Fujifilm Auto-Pull Image Pipeline
- **Labels:** `epic-5`, `native-android`, `native-ios`, `fujifilm`
- **Description:** Implementasikan listener untuk menerima/menarik foto baru dari Fujifilm X-T10 begitu tombol *shutter* ditekan atau dikirim dari kamera.
- **Acceptance Criteria:**
  - [ ] Foto baru dari Fujifilm X-T10 langsung muncul di Main Photo Canvas + otomatis ter-apply LUT + masuk antrean Google Drive.
  - [ ] Menangani *auto-reconnect* jika koneksi Wi-Fi kamera sempat terputus/sleep.

---

### SPRINT 6 — Epic #6: Field Hardening, Dual-Network & Release
**Goal:** Aplikasi stabil dipakai kerja di lapangan (sesi foto berjam-jam, ratusan foto, kombinasi Wi-Fi kamera + jaringan seluler).

#### Issue #6.1: Memory & Cache Management (Burst Shooting Stress Test)
- **Labels:** `epic-6`, `performance`, `testing`
- **Description:** Optimasi penggunaan RAM saat memuat ratusan foto 20MP+ dan *burst shooting* agar bebas *Out-Of-Memory (OOM)* crash.
- **Acceptance Criteria:**
  - [ ] *Filmstrip* hanya memuat thumbnail terkompresi (max 300px) dengan *LRU Memory Cache*.
  - [ ] Lulus tes simulasi 100 foto beruntun tanpa *crash* dan penggunaan RAM tetap stabil.

#### Issue #6.2: Smart Dual-Network Handling (Wi-Fi Camera + Cellular Drive Sync)
- **Labels:** `epic-6`, `networking`, `ux`
- **Description:** Tangani kasus nyata di lapangan saat HP konek ke Wi-Fi kamera (yang tidak punya akses internet).
- **Acceptance Criteria:**
  - [ ] Di Android: mengarahkan *socket* kamera ke interface Wi-Fi dan *request* Google Drive ke interface Seluler via `ConnectivityManager.requestNetwork` (jika didukung device), atau menahan antrean dengan banner *"Connected to Camera Wi-Fi — Drive Sync Paused (X queued)"*.
  - [ ] Di iOS/fallback: otomatis melanjutkan upload begitu HP kembali ke jaringan internet.

#### Issue #6.3: Field Testing & Release Packaging
- **Labels:** `epic-6`, `qa`, `release`
- **Description:** Uji coba lapangan lengkap dengan ketiga kamera fisik (Canon 6D, Canon M100, Fujifilm X-T10) dan siapkan build rilis.
- **Acceptance Criteria:**
  - [ ] Checklist E2E lulus untuk 3 kamera: Connect -> Shoot -> Instant Preview -> LUT Apply -> Auto-Upload Google Drive -> Scan QR di HP lain.
  - [ ] Build Android APK/AAB dan iOS IPA (TestFlight) berhasil dikompilasi tanpa error.
