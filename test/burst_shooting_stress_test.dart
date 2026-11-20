import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/sync/data/dual_network_service.dart';
import 'package:photoe_zi/features/tether/data/photo_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Epic #6: Field Hardening & Memory Management Stress Tests', () {
    late Directory tempCacheDir;

    setUp(() async {
      tempCacheDir = await Directory.systemTemp.createTemp('photo_cache_test_');
    });

    tearDown(() async {
      if (await tempCacheDir.exists()) {
        await tempCacheDir.delete(recursive: true);
      }
    });

    test('Issue #6.1 — LRU Cache & Burst Shooting 100 Photos Memory Stability', () async {
      final cacheManager = PhotoCacheManager(
        maxMemoryEntries: 25,
        cacheDir: tempCacheDir,
      );

      // Simulate a burst shooting session of 100 consecutive photos (200KB mock preview each)
      final dummyBytes = Uint8List(200 * 1024); // 200 KB dummy buffer

      for (int i = 1; i <= 100; i++) {
        final photo = IncomingPhoto(
          id: 'burst_photo_$i',
          fileName: 'IMG_$i.JPG',
          previewBytes: dummyBytes,
          capturedAt: DateTime.now(),
          exifData: {
            'cameraModel': 'Canon EOS 6D',
            'aperture': 'f/2.8',
            'shutterSpeed': '1/200s',
            'iso': '200',
            'focalLength': '50mm',
          },
        );
        cacheManager.addPhoto(photo);

        // Memory entry count must strictly stay at or below maxMemoryEntries (25)
        expect(cacheManager.cachedMemoryCount, lessThanOrEqualTo(25));
      }

      expect(cacheManager.totalTrackedPhotos, 100);
      expect(cacheManager.cachedMemoryCount, 25);

      // Accessing early evicted photo (e.g. photo #5) recovers it seamlessly from disk cache
      final retrievedPhoto5 = await cacheManager.getPreviewBytes('burst_photo_5');
      expect(retrievedPhoto5, isNotNull);
      expect(retrievedPhoto5!.length, 200 * 1024);

      // Memory count remains clamped at 25
      expect(cacheManager.cachedMemoryCount, lessThanOrEqualTo(25));
    });

    test('Issue #6.1 — ImageCache global memory thresholds', () {
      // Configured in main.dart: 150 MB max RAM cache, max 200 entries
      PaintingBinding.instance.imageCache.maximumSizeBytes = 150 << 20;
      PaintingBinding.instance.imageCache.maximumSize = 200;

      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 150 * 1024 * 1024);
      expect(PaintingBinding.instance.imageCache.maximumSize, 200);
    });

    test('Issue #6.2 — Dual-Network status payload mapping and state detection', () {
      // 1. Standard Network
      const standard = DualNetworkStatus();
      expect(standard.isWifiActive, false);
      expect(standard.isCellularActive, false);
      expect(standard.isDualNetworkActive, false);

      // 2. Camera Wi-Fi only (no internet)
      final wifiOnly = DualNetworkStatus.fromMap({
        'isWifiActive': true,
        'isCellularActive': false,
        'isDualNetworkActive': false,
        'statusDescription': 'Camera Wi-Fi Active',
      });
      expect(wifiOnly.isWifiActive, true);
      expect(wifiOnly.isCellularActive, false);
      expect(wifiOnly.isDualNetworkActive, false);

      // 3. Dual-Network active (Wi-Fi camera + Cellular upload)
      final dualActive = DualNetworkStatus.fromMap({
        'isWifiActive': true,
        'isCellularActive': true,
        'isDualNetworkActive': true,
        'statusDescription': 'Dual-Network Active: Camera Wi-Fi + Cellular Cloud Sync',
      });
      expect(dualActive.isWifiActive, true);
      expect(dualActive.isCellularActive, true);
      expect(dualActive.isDualNetworkActive, true);
    });
  });
}
