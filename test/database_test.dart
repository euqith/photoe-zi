import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoe_zi/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase CRUD Tests (Issue #1.2)', () {
    test('creates and retrieves a shooting session', () async {
      final now = DateTime(2026, 11, 19, 23, 30);
      await db.createSession(
        SessionsCompanion.insert(
          id: 'session_studio_a',
          name: 'Studio_A',
          createdAt: now,
          driveFolderId: const Value('drive_123'),
          activeLutId: const Value('classic_chrome'),
        ),
      );

      final session = await db.getSessionById('session_studio_a');
      expect(session, isNotNull);
      expect(session!.name, 'Studio_A');
      expect(session.driveFolderId, 'drive_123');
      expect(session.activeLutId, 'classic_chrome');
    });

    test('inserts photo, updates full-res path, and toggles favorite/rejected',
        () async {
      final now = DateTime.now();
      await db.createSession(
        SessionsCompanion.insert(
          id: 'session_1',
          name: 'Outdoor_Portrait',
          createdAt: now,
        ),
      );

      await db.upsertPhoto(
        PhotosCompanion.insert(
          id: 'photo_1',
          sessionId: 'session_1',
          fileName: 'IMG_4021.JPG',
          previewPath: const Value('/tmp/preview_4021.jpg'),
          exifJson: const Value('{"iso":200,"aperture":"f/1.8"}'),
          capturedAt: now,
        ),
      );

      var photos = await db.getPhotosForSession('session_1');
      expect(photos.length, 1);
      expect(photos.first.fileName, 'IMG_4021.JPG');
      expect(photos.first.fullResPath, isNull);
      expect(photos.first.isFavorite, isFalse);

      // Update full-res path
      await db.updatePhotoFullResPath('photo_1', '/tmp/full_4021.jpg');
      // Mark favorite
      await db.togglePhotoFavorite('photo_1', true);

      final updated = await db.getPhotoById('photo_1');
      expect(updated!.fullResPath, '/tmp/full_4021.jpg');
      expect(updated.isFavorite, isTrue);
      expect(updated.isRejected, isFalse);

      // Rejecting clears favorite
      await db.togglePhotoRejected('photo_1', true);
      final rejected = await db.getPhotoById('photo_1');
      expect(rejected!.isRejected, isTrue);
      expect(rejected.isFavorite, isFalse);
    });

    test('enqueues and updates upload queue items', () async {
      final now = DateTime.now();
      await db.createSession(
        SessionsCompanion.insert(
          id: 'session_1',
          name: 'Studio_A',
          createdAt: now,
        ),
      );
      await db.upsertPhoto(
        PhotosCompanion.insert(
          id: 'photo_1',
          sessionId: 'session_1',
          fileName: 'IMG_4021.JPG',
          capturedAt: now,
        ),
      );

      await db.enqueueUpload(
        UploadQueueCompanion.insert(
          id: 'upload_1',
          photoId: 'photo_1',
          variant: 'bakedLut',
        ),
      );

      var queueItems = await db.getUploadQueueForPhoto('photo_1');
      expect(queueItems.length, 1);
      expect(queueItems.first.status, 'pending');
      expect(queueItems.first.progress, 0.0);

      await db.updateUploadStatus(
        id: 'upload_1',
        status: 'completed',
        progress: 1.0,
        remoteFileId: 'gdrive_file_999',
      );

      queueItems = await db.getUploadQueueForPhoto('photo_1');
      expect(queueItems.first.status, 'completed');
      expect(queueItems.first.progress, 1.0);
      expect(queueItems.first.remoteFileId, 'gdrive_file_999');
    });
  });
}

