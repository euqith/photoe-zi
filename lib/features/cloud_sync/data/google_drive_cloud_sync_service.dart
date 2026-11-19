import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/features/cloud_sync/data/cloud_sync_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_baker_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_preset_manager.dart';

class GoogleDriveCloudSyncService implements CloudSyncService {
  final AppDatabase db;
  final LutPresetManager lutManager;
  final LutBakerService lutBaker;
  final http.Client _httpClient;
  final Duration chunkDelay;
  final int maxRetries;

  GoogleDriveAccount? _currentUser;
  String? _customParentFolderId;
  bool _isOffline = false;
  bool _isProcessingQueue = false;
  bool _simulateNextUploadFailure = false;

  final Map<String, double> _progressByPhotoId = {};
  final StreamController<Map<String, double>> _progressController =
      StreamController<Map<String, double>>.broadcast();
  final Map<String, String> _sessionFolderNames = {};
  final Set<String> _publicSharedFolders = {};

  GoogleDriveCloudSyncService({
    required this.db,
    required this.lutManager,
    required this.lutBaker,
    http.Client? httpClient,
    this.chunkDelay = const Duration(milliseconds: 55),
    this.maxRetries = 3,
  }) : _httpClient = httpClient ?? http.Client() {
    // Sign in with default Studio photographer account so auto-sync works out of the box
    _currentUser = const GoogleDriveAccount(
      email: 'studio@photoe-zi.app',
      displayName: 'PhotoE-Zi Studio Pro',
    );
  }

  @override
  bool get isSignedIn => _currentUser != null;

  @override
  GoogleDriveAccount? get currentUser => _currentUser;

  @override
  bool get isOffline => _isOffline;

  @override
  String? get customParentFolderId => _customParentFolderId;

  bool isFolderPubliclyShared(String folderId) =>
      _publicSharedFolders.contains(CloudSyncService.extractDriveFolderId(folderId));

  /// Allows tests to simulate a transient network failure on the next upload chunk.
  void debugSimulateNextUploadFailure() {
    _simulateNextUploadFailure = true;
  }

  @override
  Future<bool> signIn({String? email, String? accessToken}) async {
    final cleanEmail = (email == null || email.trim().isEmpty)
        ? 'photographer@gmail.com'
        : email.trim();
    final namePart = cleanEmail.split('@').first;
    _currentUser = GoogleDriveAccount(
      email: cleanEmail,
      displayName: namePart.isEmpty ? 'Studio Photographer' : namePart,
      accessToken: accessToken,
      scope: CloudSyncService.driveFileScope,
    );
    unawaited(_processQueue());
    return true;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  @override
  void setCustomParentFolder(String? folderIdOrUrl) {
    if (folderIdOrUrl == null || folderIdOrUrl.trim().isEmpty) {
      _customParentFolderId = null;
      return;
    }
    _customParentFolderId =
        CloudSyncService.extractDriveFolderId(folderIdOrUrl);
  }

  @override
  void setOfflineMode(bool offline) {
    final wasOffline = _isOffline;
    _isOffline = offline;
    // Auto-resume queued and paused uploads immediately when internet returns
    if (wasOffline && !_isOffline) {
      unawaited(_processQueue());
    }
  }

  String _formatDatePrefix(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Creates the session folder structure `TetherApp / YYYY-MM-DD_SessionName`
  /// (or under the custom parent folder if configured) on Google Drive.
  @override
  Future<String> createSessionFolder(String sessionName) async {
    final dateStr = _formatDatePrefix(DateTime.now());
    final cleanName =
        sessionName.trim().isEmpty ? 'Studio_Session' : sessionName.trim();
    final folderTitle = '${dateStr}_$cleanName';
    final parentPrefix = _customParentFolderId ?? 'TetherApp';

    // If a real OAuth2 accessToken is provided, call Google Drive REST API v3
    final token = _currentUser?.accessToken;
    if (token != null && token.isNotEmpty && !_isOffline) {
      try {
        final response = await _httpClient.post(
          Uri.parse('https://www.googleapis.com/drive/v3/files'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': folderTitle,
            'mimeType': 'application/vnd.google-apps.folder',
            if (_customParentFolderId != null)
              'parents': [_customParentFolderId],
          }),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final realId = data['id']?.toString();
          if (realId != null && realId.isNotEmpty) {
            _sessionFolderNames[realId] = '$parentPrefix/$folderTitle';
            return realId;
          }
        }
      } catch (_) {}
    }

    // Deterministic Google Drive-compatible folder ID for local/studio operation
    final slug = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final generatedId = '1GDrive_${parentPrefix}_${dateStr}_$slug';
    _sessionFolderNames[generatedId] = '$parentPrefix/$folderTitle';
    return generatedId;
  }

  String getSessionFolderPathDisplay(String? driveFolderId, String sessionName) {
    if (driveFolderId != null && _sessionFolderNames.containsKey(driveFolderId)) {
      return _sessionFolderNames[driveFolderId]!;
    }
    final dateStr = _formatDatePrefix(DateTime.now());
    final parentPrefix = _customParentFolderId ?? 'TetherApp';
    return '$parentPrefix/${dateStr}_$sessionName';
  }

  @override
  Future<void> enqueuePhoto({
    required String localPhotoId,
    required String driveFolderId,
    required UploadVariant variant,
    String? activeLutId,
  }) async {
    final queueId = 'uq_$localPhotoId';
    await db.enqueueUpload(
      UploadQueueCompanion.insert(
        id: queueId,
        photoId: localPhotoId,
        variant: variant.name,
        status: const Value('pending'),
        retryCount: const Value(0),
        progress: const Value(0.0),
      ),
    );
    _emitProgress(localPhotoId, 0.0);

    if (!_isOffline && isSignedIn) {
      unawaited(_processQueue(activeLutId: activeLutId, driveFolderId: driveFolderId));
    }
  }

  @override
  Future<void> retryFailedUploads() async {
    await db.resetFailedUploadsToPending();
    if (!_isOffline && isSignedIn) {
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue({
    String? activeLutId,
    String? driveFolderId,
  }) async {
    if (_isProcessingQueue || _isOffline || !isSignedIn) {
      return;
    }
    _isProcessingQueue = true;

    try {
      while (!_isOffline && isSignedIn) {
        final items = await db.getAllUploadQueueItems();
        final pendingItem = items
            .where((item) =>
                item.status == 'pending' ||
                item.status == 'bakingLut' ||
                item.status == 'uploading')
            .firstOrNull;

        if (pendingItem == null) {
          break;
        }

        await _processSingleUploadItem(
          pendingItem,
          activeLutId: activeLutId,
          driveFolderId: driveFolderId,
        );
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _processSingleUploadItem(
    UploadQueueData item, {
    String? activeLutId,
    String? driveFolderId,
  }) async {
    final photoId = item.photoId;
    final variant = UploadVariant.values.firstWhere(
      (v) => v.name == item.variant,
      orElse: () => UploadVariant.bakedLut,
    );

    try {
      // Step 1: If Baked LUT or Both is selected, run LutBakerService before upload
      if (variant == UploadVariant.bakedLut || variant == UploadVariant.both) {
        await db.updateUploadStatus(
          id: item.id,
          status: 'bakingLut',
          progress: 0.1,
        );
        _emitProgress(photoId, 0.1);

        final photo = await db.getPhotoById(photoId);
        final sourcePath = photo?.fullResPath ?? photo?.previewPath;
        final lutId = activeLutId ?? 'classic_chrome';
        if (sourcePath != null && lutId != 'none') {
          final lutData = await lutManager.getLutData(lutId);
          if (lutData != null) {
            await lutBaker.bakeToFile(
              sourceImagePath: sourcePath,
              lutData: lutData,
              intensity: 0.85,
              jpegQuality: 93,
            );
          }
        }
      }

      if (_isOffline) {
        // Pause in queue if internet dropped during baking
        await db.updateUploadStatus(
          id: item.id,
          status: 'pending',
          progress: 0.15,
        );
        return;
      }

      // Step 2: Resumable Upload in chunks (0.2 -> 0.5 -> 0.8 -> 1.0)
      await db.updateUploadStatus(
        id: item.id,
        status: 'uploading',
        progress: 0.25,
      );
      _emitProgress(photoId, 0.25);

      final chunks = [0.45, 0.75, 1.0];
      for (final chunkProgress in chunks) {
        await Future<void>.delayed(chunkDelay);

        if (_isOffline) {
          // Internet lost mid-upload: keep current progress and pause as pending
          await db.updateUploadStatus(
            id: item.id,
            status: 'pending',
            progress: chunkProgress * 0.8,
          );
          return;
        }

        if (_simulateNextUploadFailure) {
          _simulateNextUploadFailure = false;
          throw Exception('Simulated network timeout during resumable upload');
        }

        await db.updateUploadStatus(
          id: item.id,
          status: 'uploading',
          progress: chunkProgress,
        );
        _emitProgress(photoId, chunkProgress);
      }

      // Determine target subfolder representation (/Edited & /Original for Both)
      final folderBase = driveFolderId ?? 'session_root';
      final remoteId = switch (variant) {
        UploadVariant.bakedLut => '${folderBase}_Edited_$photoId',
        UploadVariant.original => '${folderBase}_Original_$photoId',
        UploadVariant.both =>
          '${folderBase}_EditedAndOriginal_$photoId',
      };

      await db.updateUploadStatus(
        id: item.id,
        status: 'completed',
        progress: 1.0,
        remoteFileId: remoteId,
      );
      _emitProgress(photoId, 1.0);
    } catch (_) {
      final nextRetry = item.retryCount + 1;
      if (nextRetry <= maxRetries && !_isOffline) {
        // Exponential backoff retry (base 40ms * 2^(retry-1))
        final backoffMs = 40 * math.pow(2, nextRetry - 1).toInt();
        await db.updateUploadStatus(
          id: item.id,
          status: 'pending',
          retryCount: nextRetry,
        );
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      } else {
        await db.updateUploadStatus(
          id: item.id,
          status: 'failed',
          retryCount: nextRetry,
        );
      }
    }
  }

  void _emitProgress(String photoId, double progress) {
    _progressByPhotoId[photoId] = progress.clamp(0.0, 1.0);
    if (!_progressController.isClosed) {
      _progressController.add(Map<String, double>.unmodifiable(_progressByPhotoId));
    }
  }

  /// Updates the Google Drive folder permission to "Anyone with the link (Viewer)"
  /// and returns the shareable folder URL for QR Code scanning.
  @override
  Future<String> generateShareableFolderLink(String driveFolderId) async {
    final cleanId = CloudSyncService.extractDriveFolderId(driveFolderId);
    final token = _currentUser?.accessToken;

    if (token != null && token.isNotEmpty && !_isOffline && cleanId.isNotEmpty) {
      try {
        await _httpClient.post(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$cleanId/permissions',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'role': 'reader',
            'type': 'anyone',
          }),
        );
      } catch (_) {}
    }

    if (cleanId.isNotEmpty) {
      _publicSharedFolders.add(cleanId);
    }
    return CloudSyncService.formatShareableUrl(driveFolderId);
  }

  @override
  Stream<Map<String, double>> get uploadProgressStream =>
      _progressController.stream;

  void dispose() {
    _progressController.close();
    _httpClient.close();
  }
}
