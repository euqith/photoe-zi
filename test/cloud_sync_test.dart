import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/features/cloud_sync/data/cloud_sync_service.dart';
import 'package:photoe_zi/features/cloud_sync/data/google_drive_cloud_sync_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_baker_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_preset_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LutPresetManager lutManager;
  late GoogleDriveCloudSyncService syncService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_sync_test_');
    db = AppDatabase(NativeDatabase.memory());
    lutManager = LutPresetManager(customLutDirProvider: () async => tempDir);
    syncService = GoogleDriveCloudSyncService(
      db: db,
      lutManager: lutManager,
      lutBaker: const LutBakerService(),
      chunkDelay: const Duration(milliseconds: 10),
      maxRetries: 2,
    );
  });

  tearDown(() async {
    syncService.dispose();
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> createSampleJpegFile(String name) async {
    final sampleImg = img.Image(width: 120, height: 80);
    for (int y = 0; y < 80; y++) {
      for (int x = 0; x < 120; x++) {
        sampleImg.setPixelRgb(x, y, 140, 120, 100);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(sampleImg, quality: 90));
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  group('Issue #3.1 — Google Sign-In OAuth 2.0 & Auto Session Folder Tests',
      () {
    test(
        'signs in/out, creates TetherApp/YYYY-MM-DD_SessionName folder, and supports custom parent folder & link extraction',
        () async {
      await syncService.signOut();
      expect(syncService.isSignedIn, isFalse);

      final signedIn =
          await syncService.signIn(email: 'client.studio@gmail.com');
      expect(signedIn, isTrue);
      expect(syncService.currentUser?.email, 'client.studio@gmail.com');
      expect(
        syncService.currentUser?.scope,
        'https://www.googleapis.com/auth/drive.file',
      );

      final folderId = await syncService.createSessionFolder('Studio_A');
      expect(folderId, contains('TetherApp'));
      expect(folderId, contains('Studio_A'));

      // Custom parent folder from full Google Drive URL
      syncService.setCustomParentFolder(
        'https://drive.google.com/drive/folders/1CustomParentFolder999?usp=sharing',
      );
      expect(syncService.customParentFolderId, '1CustomParentFolder999');

      final customSessionFolder =
          await syncService.createSessionFolder('Wedding_B');
      expect(customSessionFolder, contains('1CustomParentFolder999'));
      expect(customSessionFolder, contains('Wedding_B'));
    });
  });

  group(
      'Issue #3.2 & #3.3 — Resilient Resumable Upload Queue, Offline Auto-Resume & Variants',
      () {
    test(
        'pauses upload queue when offline and automatically resumes to completion when back online',
        () async {
      final samplePath = await createSampleJpegFile('IMG_5001.JPG');
      await db.createSession(
        SessionsCompanion.insert(
          id: 's1',
          name: 'Studio_A',
          createdAt: DateTime.now(),
        ),
      );
      await db.upsertPhoto(
        PhotosCompanion.insert(
          id: 'p_5001',
          sessionId: 's1',
          fileName: 'IMG_5001.JPG',
          fullResPath: Value(samplePath),
          capturedAt: DateTime.now(),
        ),
      );

      // Go offline before enqueuing
      syncService.setOfflineMode(true);
      await syncService.enqueuePhoto(
        localPhotoId: 'p_5001',
        driveFolderId: 'folder_studio_a',
        variant: UploadVariant.bakedLut,
        activeLutId: 'classic_chrome',
      );

      var items = await db.getUploadQueueForPhoto('p_5001');
      expect(items.single.status, 'pending');

      // Reconnect to internet -> queue should auto-resume, bake LUT, and complete upload
      final progressEvents = <double>[];
      final sub = syncService.uploadProgressStream.listen((map) {
        if (map.containsKey('p_5001')) {
          progressEvents.add(map['p_5001']!);
        }
      });

      syncService.setOfflineMode(false);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      items = await db.getUploadQueueForPhoto('p_5001');
      expect(items.single.status, 'completed');
      expect(items.single.progress, 1.0);
      expect(items.single.remoteFileId, contains('Edited_p_5001'));
      expect(progressEvents, contains(1.0));

      await sub.cancel();
    });

    test('handles Both variant (/Edited & /Original) and exponential backoff retry',
        () async {
      final samplePath = await createSampleJpegFile('IMG_5002.JPG');
      await db.createSession(
        SessionsCompanion.insert(
          id: 's1',
          name: 'Studio_A',
          createdAt: DateTime.now(),
        ),
      );
      await db.upsertPhoto(
        PhotosCompanion.insert(
          id: 'p_5002',
          sessionId: 's1',
          fileName: 'IMG_5002.JPG',
          fullResPath: Value(samplePath),
          capturedAt: DateTime.now(),
        ),
      );

      // Simulate one transient network failure to test automatic exponential backoff retry
      syncService.debugSimulateNextUploadFailure();
      await syncService.enqueuePhoto(
        localPhotoId: 'p_5002',
        driveFolderId: 'folder_studio_a',
        variant: UploadVariant.both,
        activeLutId: 'classic_chrome',
      );

      await Future<void>.delayed(const Duration(milliseconds: 450));

      final items = await db.getUploadQueueForPhoto('p_5002');
      expect(items.single.status, 'completed');
      expect(items.single.retryCount, greaterThanOrEqualTo(1));
      expect(items.single.remoteFileId, contains('EditedAndOriginal_p_5002'));
    });
  });

  group('Issue #3.4 — Instant QR Code Share Link & Permissions Tests', () {
    test(
        'sets folder permission to Anyone with the link (Viewer) and formats shareable URL',
        () async {
      const rawDriveLink =
          'https://drive.google.com/drive/folders/1StudioShareFolderXYZ?usp=drive_link';
      final shareUrl =
          await syncService.generateShareableFolderLink(rawDriveLink);

      expect(shareUrl, contains('1StudioShareFolderXYZ'));
      expect(
        syncService.isFolderPubliclyShared('1StudioShareFolderXYZ'),
        isTrue,
      );
    });
  });
}
