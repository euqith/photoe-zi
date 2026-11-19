import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';

class _SampleGenerationTask {
  final int index;
  final int width;
  final int height;
  final int quality;

  const _SampleGenerationTask({
    required this.index,
    required this.width,
    required this.height,
    required this.quality,
  });
}

Uint8List _generateStudioSampleJpeg(_SampleGenerationTask task) {
  final image = img.Image(width: task.width, height: task.height);
  final variant = task.index % 5;
  final cx = task.width * 0.5;
  final cy = task.height * 0.45;
  final maxDist = math.sqrt(cx * cx + cy * cy);

  for (int y = 0; y < task.height; y++) {
    final ny = y / task.height;
    for (int x = 0; x < task.width; x++) {
      final nx = x / task.width;
      final dx = x - cx;
      final dy = y - cy;
      final dist = math.sqrt(dx * dx + dy * dy) / maxDist;
      final vignette = (1.0 - (dist * dist * 0.65)).clamp(0.2, 1.0);

      double r = 0;
      double g = 0;
      double b = 0;

      switch (variant) {
        case 0: // Warm Editorial Portrait Tone
          r = (225 * (1.0 - ny * 0.35) + 40 * nx) * vignette;
          g = (170 * (1.0 - ny * 0.4) + 30 * (1.0 - nx)) * vignette;
          b = (135 * (1.0 - ny * 0.5) + 55 * ny) * vignette;
          break;
        case 1: // Cool Studio Neon / Cyberpunk
          r = (75 + 165 * nx * (1.0 - dist)) * vignette;
          g = (95 + 130 * (1.0 - ny)) * vignette;
          b = (180 + 70 * ny) * vignette;
          break;
        case 2: // Natural Golden Hour Landscape
          r = (240 * (1.0 - ny * 0.45)) * vignette;
          g = (185 * (1.0 - ny * 0.3) + 40 * nx) * vignette;
          b = (110 + 95 * (1.0 - ny)) * vignette;
          break;
        case 3: // High-Contrast Monochrome / Fine Art
          final lum =
              ((math.sin(nx * math.pi * 2.5) * 0.25 + 0.65 - ny * 0.3) * 245) *
                  vignette;
          r = lum;
          g = lum * 0.98;
          b = lum * 0.95;
          break;
        default: // Emerald & Amber Fashion Studio
          r = (110 + 130 * math.exp(-dist * 2.4)) * vignette;
          g = (165 * (1.0 - ny * 0.25)) * vignette;
          b = (145 * nx + 50) * vignette;
          break;
      }

      // Draw a subtle studio subject silhouette / key-light circle in the center
      final subjectRadius = math.min(task.width, task.height) * 0.24;
      final rawDist = math.sqrt(dx * dx + dy * dy);
      if (rawDist < subjectRadius) {
        final factor = 1.0 - (rawDist / subjectRadius);
        r = (r + 55 * factor).clamp(0, 255);
        g = (g + 42 * factor).clamp(0, 255);
        b = (b + 30 * factor).clamp(0, 255);
      }

      image.setPixelRgb(
        x,
        y,
        r.round().clamp(0, 255),
        g.round().clamp(0, 255),
        b.round().clamp(0, 255),
      );
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: task.quality));
}

class MockCameraDriver implements BaseCameraDriver {
  final Duration captureInterval;
  final Duration fullResDelay;
  final Future<Directory> Function()? storageDirProvider;

  final StreamController<CameraConnectionState> _connectionController =
      StreamController<CameraConnectionState>.broadcast();
  final StreamController<IncomingPhoto> _photoController =
      StreamController<IncomingPhoto>.broadcast();

  CameraConnectionState _state = CameraConnectionState.disconnected;
  Timer? _captureTimer;
  int _shotCounter = 4020;
  final Map<String, int> _photoShotIndices = {};
  final Map<int, Uint8List> _previewCache = {};
  final Map<int, Uint8List> _fullResCache = {};

  MockCameraDriver({
    this.captureInterval = const Duration(seconds: 3),
    this.fullResDelay = const Duration(milliseconds: 500),
    this.storageDirProvider,
  });

  CameraConnectionState get currentState => _state;

  @override
  String get driverName => 'Canon EOS 6D (Mock Simulator)';

  @override
  CameraConnectionType get connectionType => CameraConnectionType.mock;

  @override
  Stream<CameraConnectionState> get connectionStateStream =>
      _connectionController.stream;

  @override
  Stream<IncomingPhoto> get onNewPhotoStream => _photoController.stream;

  static const List<Map<String, dynamic>> _sampleExifPresets = [
    {
      'cameraModel': 'Canon EOS 6D',
      'lens': 'EF 50mm f/1.8 STM',
      'aperture': 'f/1.8',
      'shutterSpeed': '1/250s',
      'iso': 200,
      'focalLength': '50mm',
      'resolution': '5472 × 3648 (20.0 MP)',
    },
    {
      'cameraModel': 'Canon EOS 6D',
      'lens': 'EF 85mm f/1.4L IS USM',
      'aperture': 'f/2.0',
      'shutterSpeed': '1/500s',
      'iso': 400,
      'focalLength': '85mm',
      'resolution': '5472 × 3648 (20.0 MP)',
    },
    {
      'cameraModel': 'Canon EOS M100',
      'lens': 'EF-M 22mm f/2 STM',
      'aperture': 'f/2.8',
      'shutterSpeed': '1/160s',
      'iso': 100,
      'focalLength': '22mm',
      'resolution': '6000 × 4000 (24.2 MP)',
    },
    {
      'cameraModel': 'Fujifilm X-T10',
      'lens': 'XF 35mm f/1.4 R',
      'aperture': 'f/1.4',
      'shutterSpeed': '1/1000s',
      'iso': 640,
      'focalLength': '35mm',
      'resolution': '4896 × 3264 (16.3 MP)',
    },
    {
      'cameraModel': 'Canon EOS 6D',
      'lens': 'EF 24-70mm f/2.8L II USM',
      'aperture': 'f/4.0',
      'shutterSpeed': '1/125s',
      'iso': 800,
      'focalLength': '35mm',
      'resolution': '5472 × 3648 (20.0 MP)',
    },
  ];

  void _setState(CameraConnectionState newState) {
    _state = newState;
    if (!_connectionController.isClosed) {
      _connectionController.add(newState);
    }
  }

  @override
  Future<bool> connect({String? ipAddress, int? port}) async {
    if (_state == CameraConnectionState.connected) {
      return true;
    }
    _setState(CameraConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _setState(CameraConnectionState.connected);

    // Trigger an immediate first shot so the user sees instant feedback,
    // then continue periodically every 3 seconds.
    unawaited(_simulateCapture());
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(captureInterval, (_) {
      if (_state == CameraConnectionState.connected) {
        unawaited(_simulateCapture());
      }
    });
    return true;
  }

  @override
  Future<void> disconnect() async {
    _captureTimer?.cancel();
    _captureTimer = null;
    _setState(CameraConnectionState.disconnected);
  }

  Future<void> triggerManualShot() async {
    if (_state == CameraConnectionState.connected) {
      await _simulateCapture();
    }
  }

  Future<Directory> _resolveStorageDir() async {
    if (storageDirProvider != null) {
      return storageDirProvider!();
    }
    final dir =
        Directory(p.join(Directory.systemTemp.path, 'photoe_zi_mock_captures'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Uint8List> _getPreviewBytes(int variantIndex) async {
    final key = variantIndex % 5;
    if (_previewCache.containsKey(key)) {
      return _previewCache[key]!;
    }
    final bytes = _generateStudioSampleJpeg(
      _SampleGenerationTask(
        index: key,
        width: 360,
        height: 240,
        quality: 82,
      ),
    );
    _previewCache[key] = bytes;
    return bytes;
  }

  Future<Uint8List> _getFullResBytes(int variantIndex) async {
    final key = variantIndex % 5;
    if (_fullResCache.containsKey(key)) {
      return _fullResCache[key]!;
    }
    final bytes = _generateStudioSampleJpeg(
      _SampleGenerationTask(
        index: key,
        width: 960,
        height: 640,
        quality: 94,
      ),
    );
    _fullResCache[key] = bytes;
    return bytes;
  }

  Future<void> _simulateCapture() async {
    if (_state != CameraConnectionState.connected) return;

    _shotCounter++;
    final shotNum = _shotCounter;
    final photoId = 'mock_img_$shotNum';
    final fileName = 'IMG_$shotNum.JPG';
    final capturedAt = DateTime.now();
    final exif = Map<String, dynamic>.from(
      _sampleExifPresets[shotNum % _sampleExifPresets.length],
    );
    _photoShotIndices[photoId] = shotNum;

    // Stage 1: Emit fast embedded thumbnail preview (< 1s)
    final previewBytes = await _getPreviewBytes(shotNum);
    final stage1Photo = IncomingPhoto(
      id: photoId,
      fileName: fileName,
      previewBytes: previewBytes,
      fullResLocalPath: null,
      exifData: exif,
      capturedAt: capturedAt,
    );

    if (!_photoController.isClosed &&
        _state == CameraConnectionState.connected) {
      _photoController.add(stage1Photo);
    }

    // Stage 2: Pull full-resolution JPEG in background after 500ms and emit update
    Future<void>.delayed(fullResDelay, () async {
      if (_state != CameraConnectionState.connected ||
          _photoController.isClosed) {
        return;
      }
      final dir = await _resolveStorageDir();
      final fullPath = await downloadFullResolution(photoId, dir.path);
      final stage2Photo = stage1Photo.copyWith(fullResLocalPath: fullPath);
      if (!_photoController.isClosed &&
          _state == CameraConnectionState.connected) {
        _photoController.add(stage2Photo);
      }
    });
  }

  @override
  Future<String> downloadFullResolution(
      String photoId, String targetDir) async {
    final shotNum = _photoShotIndices[photoId] ?? _shotCounter;
    final bytes = await _getFullResBytes(shotNum);
    final outDir = Directory(targetDir);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final filePath = p.join(targetDir, '$photoId.jpg');
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  void dispose() {
    _captureTimer?.cancel();
    _connectionController.close();
    _photoController.close();
  }
}
