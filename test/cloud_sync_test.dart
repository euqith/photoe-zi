import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/features/cloud_sync/data/cloud_sync_service.dart';
import 'package:photoe_zi/features/cloud_sync/data/google_drive_cloud_sync_service.dart';
import 'package:photoe_zi/features/cloud_sync/data/google_oauth_config_manager.dart';
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
      startInDemoMode: true,
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

  group('Fix #3.5 — Real OAuth2 Token Auth & Google Drive API v3 Resumable Upload',
      () {
    test(
        'verifies real OAuth2 access token via /drive/v3/about and uploads JPEG bytes via /upload/drive/v3/files?uploadType=resumable',
        () async {
      final recordedRequests = <String>[];
      int uploadedByteLength = 0;

      final mockHttp = MockClient((http.Request request) async {
        recordedRequests.add('${request.method} ${request.url}');

        // 1. Token Verification: GET /drive/v3/about?fields=user
        if (request.url.path.endsWith('/drive/v3/about')) {
          expect(request.headers['Authorization'], 'Bearer ya29.live_token_123');
          return http.Response(
            jsonEncode({
              'user': {
                'emailAddress': 'real.photographer@gmail.com',
                'displayName': 'Real Photographer',
              }
            }),
            200,
          );
        }

        // 2. Resumable Upload Initiation: POST /upload/drive/v3/files?uploadType=resumable
        if (request.method == 'POST' &&
            request.url.path.endsWith('/upload/drive/v3/files') &&
            request.url.queryParameters['uploadType'] == 'resumable') {
          final meta = jsonDecode(request.body) as Map<String, dynamic>;
          expect(meta['name'], 'IMG_9001.JPG');
          expect(meta['parents'], ['1RealTargetDriveFolderID']);
          return http.Response(
            '',
            200,
            headers: {
              'location':
                  'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=session_abc_999',
            },
          );
        }

        // 3. Resumable Upload Bytes PUT
        if (request.method == 'PUT' &&
            request.url.queryParameters['upload_id'] == 'session_abc_999') {
          uploadedByteLength = request.bodyBytes.length;
          return http.Response(
            jsonEncode({
              'id': '1RealUploadedGoogleDriveFileID_9001',
              'name': 'IMG_9001.JPG',
            }),
            200,
          );
        }

        return http.Response('Not found', 404);
      });

      final realService = GoogleDriveCloudSyncService(
        db: db,
        lutManager: lutManager,
        lutBaker: const LutBakerService(),
        httpClient: mockHttp,
      );

      // Default is NOT signed in
      expect(realService.isSignedIn, isFalse);

      // Sign in with real OAuth 2.0 Access Token
      final authOk = await realService.signIn(
        accessToken: 'ya29.live_token_123',
      );
      expect(authOk, isTrue);
      expect(realService.currentUser?.email, 'real.photographer@gmail.com');
      expect(realService.currentUser?.hasRealAccessToken, isTrue);

      final samplePath = await createSampleJpegFile('IMG_9001.JPG');
      await db.createSession(
        SessionsCompanion.insert(
          id: 's_real',
          name: 'Real_Shoot',
          createdAt: DateTime.now(),
        ),
      );
      await db.upsertPhoto(
        PhotosCompanion.insert(
          id: 'p_9001',
          sessionId: 's_real',
          fileName: 'IMG_9001.JPG',
          fullResPath: Value(samplePath),
          capturedAt: DateTime.now(),
        ),
      );

      await realService.enqueuePhoto(
        localPhotoId: 'p_9001',
        driveFolderId:
            'https://drive.google.com/drive/folders/1RealTargetDriveFolderID?usp=sharing',
        variant: UploadVariant.bakedLut,
        activeLutId: 'classic_chrome',
      );

      await Future<void>.delayed(const Duration(milliseconds: 350));

      final queueItems = await db.getUploadQueueForPhoto('p_9001');
      expect(queueItems.single.status, 'completed');
      expect(
        queueItems.single.remoteFileId,
        '1RealUploadedGoogleDriveFileID_9001',
      );
      expect(uploadedByteLength, greaterThan(100));
    });

    test(
        'gracefully signs in via tokeninfo when /drive/v3/about hits 403 quota exceeded',
        () async {
      final mockHttp = MockClient((http.Request request) async {
        // Tokeninfo succeeds on oauth2.googleapis.com
        if (request.url.path.contains('tokeninfo')) {
          return http.Response(
            jsonEncode({
              'email': 'quota.rescued@gmail.com',
              'scope': 'https://www.googleapis.com/auth/drive',
              'expires_in': 3599,
            }),
            200,
          );
        }

        // /drive/v3/about returns 403 Quota exceeded
        if (request.url.path.endsWith('/drive/v3/about')) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'message':
                    "Quota exceeded for quota metric 'Queries' and limit 'Previous quota: Requests per minute' of service 'drive.googleapis.com' for consumer 'project_number:202264815644'.",
              }
            }),
            403,
          );
        }

        return http.Response('Not found', 404);
      });

      final quotaResilientService = GoogleDriveCloudSyncService(
        db: db,
        lutManager: lutManager,
        lutBaker: const LutBakerService(),
        httpClient: mockHttp,
      );

      final signedIn = await quotaResilientService.signIn(
        accessToken: 'ya29.quota_test_token',
      );
      expect(signedIn, isTrue);
      expect(quotaResilientService.currentUser?.email, 'quota.rescued@gmail.com');
      expect(quotaResilientService.currentUser?.hasRealAccessToken, isTrue);
    });
  });

  group(
      'Issue #3.11 — PhotoE-Zi Dedicated Google OAuth2 Configuration & No Rclone Fallback',
      () {
    test(
        'saves, loads, and masks dedicated PhotoE-Zi Google OAuth configuration locally',
        () async {
      final configManager = GoogleOAuthConfigManager(
        configDirProvider: () async => tempDir,
      );

      var config = await configManager.loadConfig();
      expect(config.isConfigured, isFalse);

      await configManager.saveConfig(
        clientId: 'photoezi-123456789.apps.googleusercontent.com',
        clientSecret: 'photoezi-secret-xyz',
      );

      config = await configManager.loadConfig();
      expect(config.isConfigured, isTrue);
      expect(config.clientId, 'photoezi-123456789.apps.googleusercontent.com');
      expect(config.clientSecret, 'photoezi-secret-xyz');
      expect(config.maskedClientId, contains('...'));

      await configManager.clearConfig();
      config = await configManager.loadConfig();
      expect(config.isConfigured, isFalse);
    });

    test(
        'signInWithBrowserOAuth fails gracefully with clear message when no Client ID is configured and never uses rclone',
        () async {
      final configManager = GoogleOAuthConfigManager(
        configDirProvider: () async => tempDir,
      );
      final service = GoogleDriveCloudSyncService(
        db: db,
        lutManager: lutManager,
        lutBaker: const LutBakerService(),
        oauthConfigManager: configManager,
      );

      final ok = await service.signInWithBrowserOAuth();
      expect(ok, isFalse);
      expect(
        service.lastErrorMessage,
        contains('PhotoE-Zi Google OAuth 2.0 Client ID is not configured yet'),
      );
      expect(service.lastErrorMessage, isNot(contains('rclone')));
    });
  });
}
