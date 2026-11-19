import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get driveFolderId => text().nullable()();
  TextColumn get activeLutId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Photos extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get previewPath => text().nullable()();
  TextColumn get fullResPath => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isRejected => boolean().withDefault(const Constant(false))();
  TextColumn get exifJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get capturedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class UploadQueue extends Table {
  TextColumn get id => text()();
  TextColumn get photoId =>
      text().references(Photos, #id, onDelete: KeyAction.cascade)();
  TextColumn get variant => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get remoteFileId => text().nullable()();
  RealColumn get progress => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Sessions, Photos, UploadQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'photoe_zi_db');
  }

  // --- Sessions CRUD ---
  Future<List<Session>> getAllSessions() =>
      (select(sessions)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Stream<List<Session>> watchAllSessions() =>
      (select(sessions)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<Session?> getSessionById(String id) =>
      (select(sessions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> createSession(SessionsCompanion entry) =>
      into(sessions).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateSessionActiveLut(String sessionId, String? lutId) =>
      (update(sessions)..where((t) => t.id.equals(sessionId)))
          .write(SessionsCompanion(activeLutId: Value(lutId)));

  Future<void> updateSessionDriveFolder(String sessionId, String? folderId) =>
      (update(sessions)..where((t) => t.id.equals(sessionId)))
          .write(SessionsCompanion(driveFolderId: Value(folderId)));

  // --- Photos CRUD ---
  Future<List<Photo>> getPhotosForSession(String sessionId) => (select(photos)
        ..where((t) => t.sessionId.equals(sessionId))
        ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
      .get();

  Stream<List<Photo>> watchPhotosForSession(String sessionId) => (select(photos)
        ..where((t) => t.sessionId.equals(sessionId))
        ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
      .watch();

  Future<Photo?> getPhotoById(String id) =>
      (select(photos)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertPhoto(PhotosCompanion entry) =>
      into(photos).insertOnConflictUpdate(entry);

  Future<void> updatePhotoFullResPath(String photoId, String fullResPath) =>
      (update(photos)..where((t) => t.id.equals(photoId)))
          .write(PhotosCompanion(fullResPath: Value(fullResPath)));

  Future<void> togglePhotoFavorite(String photoId, bool isFavorite) =>
      (update(photos)..where((t) => t.id.equals(photoId))).write(
        PhotosCompanion(
          isFavorite: Value(isFavorite),
          isRejected: isFavorite ? const Value(false) : const Value.absent(),
        ),
      );

  Future<void> togglePhotoRejected(String photoId, bool isRejected) =>
      (update(photos)..where((t) => t.id.equals(photoId))).write(
        PhotosCompanion(
          isRejected: Value(isRejected),
          isFavorite: isRejected ? const Value(false) : const Value.absent(),
        ),
      );

  // --- UploadQueue CRUD ---
  Future<void> enqueueUpload(UploadQueueCompanion entry) =>
      into(uploadQueue).insertOnConflictUpdate(entry);

  Stream<List<UploadQueueData>> watchUploadQueue() => select(uploadQueue).watch();

  Future<List<UploadQueueData>> getUploadQueueForPhoto(String photoId) =>
      (select(uploadQueue)..where((t) => t.photoId.equals(photoId))).get();

  Future<List<UploadQueueData>> getAllUploadQueueItems() =>
      select(uploadQueue).get();

  Future<List<UploadQueueData>> getPendingOrFailedUploads() =>
      (select(uploadQueue)
            ..where((t) =>
                t.status.equals('pending') |
                t.status.equals('bakingLut') |
                t.status.equals('uploading') |
                t.status.equals('failed')))
          .get();

  Future<void> resetFailedUploadsToPending() =>
      (update(uploadQueue)..where((t) => t.status.equals('failed'))).write(
        const UploadQueueCompanion(
          status: Value('pending'),
          progress: Value(0.0),
          retryCount: Value(0),
        ),
      );

  Future<void> updateUploadStatus({
    required String id,
    required String status,
    double? progress,
    int? retryCount,
    String? remoteFileId,
  }) {
    return (update(uploadQueue)..where((t) => t.id.equals(id))).write(
      UploadQueueCompanion(
        status: Value(status),
        progress: progress != null ? Value(progress) : const Value.absent(),
        retryCount:
            retryCount != null ? Value(retryCount) : const Value.absent(),
        remoteFileId:
            remoteFileId != null ? Value(remoteFileId) : const Value.absent(),
      ),
    );
  }
}

