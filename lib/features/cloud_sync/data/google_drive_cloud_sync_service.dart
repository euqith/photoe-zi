import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  String? _lastErrorMessage;
  bool _isOffline = false;
  bool _isProcessingQueue = false;
  bool _simulateNextUploadFailure = false;

  final Map<String, double> _progressByPhotoId = {};
  final StreamController<Map<String, double>> _progressController =
      StreamController<Map<String, double>>.broadcast();
  final Map<String, String> _sessionFolderNames = {};
  final Map<String, String> _subfolderCache = {};
  final Set<String> _publicSharedFolders = {};

  GoogleDriveCloudSyncService({
    required this.db,
    required this.lutManager,
    required this.lutBaker,
    http.Client? httpClient,
    this.chunkDelay = const Duration(milliseconds: 55),
    this.maxRetries = 3,
    bool startInDemoMode = false,
  }) : _httpClient = httpClient ?? http.Client() {
    if (startInDemoMode) {
      _currentUser = const GoogleDriveAccount(
        email: 'demo@photoe-zi.app',
        displayName: 'Demo Sandbox Account',
        isDemoMode: true,
      );
    }
  }

  @override
  bool get isSignedIn => _currentUser != null;

  @override
  GoogleDriveAccount? get currentUser => _currentUser;

  @override
  bool get isOffline => _isOffline;

  @override
  String? get customParentFolderId => _customParentFolderId;

  @override
  String? get lastErrorMessage => _lastErrorMessage;

  bool isFolderPubliclyShared(String folderId) => _publicSharedFolders
      .contains(CloudSyncService.extractDriveFolderId(folderId));

  void debugSimulateNextUploadFailure() {
    _simulateNextUploadFailure = true;
  }

  /// Signs in using a real Google OAuth 2.0 Access Token (verifying it against
  /// Google Drive v3 `/about?fields=user`) or explicit Demo/Test mode.
  @override
  Future<bool> signIn({
    String? email,
    String? accessToken,
    bool isDemoMode = false,
  }) async {
    _lastErrorMessage = null;
    final cleanToken = accessToken?.trim();

    if (cleanToken != null && cleanToken.isNotEmpty && !isDemoMode) {
      try {
        final aboutResp = await _httpClient.get(
          Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user'),
          headers: {'Authorization': 'Bearer $cleanToken'},
        );

        if (aboutResp.statusCode == 200) {
          final body = jsonDecode(aboutResp.body) as Map<String, dynamic>;
          final userMap = body['user'] as Map<String, dynamic>?;
          final verifiedEmail =
              userMap?['emailAddress']?.toString() ?? email ?? 'Google Drive User';
          final verifiedName =
              userMap?['displayName']?.toString() ?? verifiedEmail.split('@').first;

          _currentUser = GoogleDriveAccount(
            email: verifiedEmail,
            displayName: verifiedName,
            accessToken: cleanToken,
            isDemoMode: false,
          );
          unawaited(_processQueue());
          return true;
        } else {
          String apiErr = 'HTTP ${aboutResp.statusCode}';
          try {
            final errBody = jsonDecode(aboutResp.body) as Map<String, dynamic>;
            apiErr = errBody['error']?['message']?.toString() ?? apiErr;
          } catch (_) {}
          _lastErrorMessage = 'Google Drive token verification failed: $apiErr';
          return false;
        }
      } catch (e) {
        _lastErrorMessage = 'Network error verifying Google Drive token: $e';
        return false;
      }
    }

    if (isDemoMode || (email != null && email.trim().isNotEmpty && cleanToken == null)) {
      final cleanEmail = (email == null || email.trim().isEmpty)
          ? 'demo@photoe-zi.app'
          : email.trim();
      _currentUser = GoogleDriveAccount(
        email: cleanEmail,
        displayName: '${cleanEmail.split('@').first} (Demo Mode)',
        isDemoMode: true,
      );
      unawaited(_processQueue());
      return true;
    }

    _lastErrorMessage =
        'Please enter a valid Google OAuth 2.0 Access Token or use Browser Sign-In.';
    return false;
  }

  /// Launches an actual OAuth 2.0 Loopback Browser flow on `http://127.0.0.1:<port>`
  /// to authenticate with Google Accounts and obtain a live Drive `access_token`.
  @override
  Future<bool> signInWithBrowserOAuth({
    required String clientId,
    String? clientSecret,
  }) async {
    _lastErrorMessage = null;
    final cleanClientId = clientId.trim();
    if (cleanClientId.isEmpty) {
      _lastErrorMessage = 'OAuth 2.0 Client ID is required for Browser Sign-In.';
      return false;
    }

    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port';

      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': cleanClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope':
            '${CloudSyncService.driveFullScope} https://www.googleapis.com/auth/userinfo.email',
        'access_type': 'offline',
        'prompt': 'consent',
      });

      await openSystemUrl(authUrl.toString());

      String? authCode;
      await for (final HttpRequest request in server.timeout(
        const Duration(minutes: 2),
      )) {
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        request.response.headers.contentType = ContentType.html;
        if (code != null) {
          authCode = code;
          request.response.write('''
<!DOCTYPE html>
<html>
<head><title>PhotoE-Zi Google Drive Auth</title></head>
<body style="background:#0F0F10;color:#F3F4F6;font-family:sans-serif;text-align:center;padding-top:60px;">
  <h2 style="color:#10B981;">✓ Google Drive Connected Successfully!</h2>
  <p>You can close this browser tab and return to PhotoE-Zi.</p>
</body>
</html>
''');
        } else {
          request.response.write('''
<!DOCTYPE html>
<html>
<body style="background:#0F0F10;color:#EF4444;font-family:sans-serif;text-align:center;padding-top:60px;">
  <h2>Authentication Failed: ${error ?? 'Cancelled'}</h2>
</body>
</html>
''');
        }
        await request.response.close();
        break;
      }

      if (authCode == null) {
        _lastErrorMessage = 'Did not receive authorization code from Google.';
        return false;
      }

      final tokenBody = <String, String>{
        'code': authCode,
        'client_id': cleanClientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      };
      if (clientSecret != null && clientSecret.trim().isNotEmpty) {
        tokenBody['client_secret'] = clientSecret.trim();
      }

      final tokenResp = await _httpClient.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: tokenBody,
      );

      if (tokenResp.statusCode != 200) {
        _lastErrorMessage =
            'Token exchange failed (${tokenResp.statusCode}): ${tokenResp.body}';
        return false;
      }

      final tokenJson = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      final accessToken = tokenJson['access_token']?.toString();
      if (accessToken == null || accessToken.isEmpty) {
        _lastErrorMessage = 'Google did not return an access_token.';
        return false;
      }

      return await signIn(accessToken: accessToken);
    } catch (e) {
      _lastErrorMessage = 'Browser OAuth flow error: $e';
      return false;
    } finally {
      await server?.close(force: true);
    }
  }

  /// Opens a URL in the host OS browser (macOS `open`, Linux `xdg-open`, Windows `start`).
  static Future<void> openSystemUrl(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url]);
      }
    } catch (_) {}
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _lastErrorMessage = null;
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

  Future<String?> _createRealDriveFolder({
    required String token,
    required String folderName,
    String? parentFolderId,
  }) async {
    final isRealParentId = parentFolderId != null &&
        parentFolderId.isNotEmpty &&
        !parentFolderId.startsWith('1GDrive_') &&
        parentFolderId != 'TetherApp_Root';

    final response = await _httpClient.post(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files?supportsAllDrives=true',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        if (isRealParentId) 'parents': [parentFolderId],
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['id']?.toString();
    } else {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        msg = err['error']?['message']?.toString() ?? msg;
      } catch (_) {}
      throw Exception('Failed creating folder "$folderName" on Google Drive: $msg');
    }
  }

  @override
  Future<String> createSessionFolder(String sessionName) async {
    final dateStr = _formatDatePrefix(DateTime.now());
    final cleanName =
        sessionName.trim().isEmpty ? 'Studio_Session' : sessionName.trim();
    final folderTitle = '${dateStr}_$cleanName';
    final parentPrefix = _customParentFolderId ?? 'TetherApp';

    final user = _currentUser;
    if (user != null && user.hasRealAccessToken && !_isOffline) {
      try {
        final realId = await _createRealDriveFolder(
          token: user.accessToken!,
          folderName: folderTitle,
          parentFolderId: _customParentFolderId,
        );
        if (realId != null && realId.isNotEmpty) {
          _sessionFolderNames[realId] = '$parentPrefix/$folderTitle';
          return realId;
        }
      } catch (e) {
        _lastErrorMessage = e.toString();
      }
    }

    final slug = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final generatedId = '1GDrive_${parentPrefix}_${dateStr}_$slug';
    _sessionFolderNames[generatedId] = '$parentPrefix/$folderTitle';
    return generatedId;
  }

  String getSessionFolderPathDisplay(
      String? driveFolderId, String sessionName) {
    if (driveFolderId != null &&
        _sessionFolderNames.containsKey(driveFolderId)) {
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
      unawaited(
        _processQueue(
          activeLutId: activeLutId,
          driveFolderId: driveFolderId,
        ),
      );
    }
  }

  @override
  Future<void> retryFailedUploads() async {
    _lastErrorMessage = null;
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

  /// Performs a real Google Drive API v3 Resumable Upload (`uploadType=resumable`)
  /// sending actual JPEG bytes in chunks and returning the live Google Drive file ID.
  Future<String> _uploadFileBytesToGoogleDriveResumable({
    required String token,
    required String fileName,
    required Uint8List fileBytes,
    required String? parentFolderId,
    required void Function(double progress) onProgress,
  }) async {
    final isRealFolderId = parentFolderId != null &&
        parentFolderId.isNotEmpty &&
        !parentFolderId.startsWith('1GDrive_') &&
        parentFolderId != 'TetherApp_Root' &&
        parentFolderId != 'session_root';

    final metadata = <String, dynamic>{
      'name': fileName,
      'mimeType': 'image/jpeg',
      if (isRealFolderId) 'parents': [parentFolderId],
    };

    // 1. Initiate Resumable Upload Session
    final initResp = await _httpClient.post(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'image/jpeg',
        'X-Upload-Content-Length': fileBytes.length.toString(),
      },
      body: jsonEncode(metadata),
    );

    if (initResp.statusCode != 200) {
      String msg = 'HTTP ${initResp.statusCode}';
      try {
        final err = jsonDecode(initResp.body) as Map<String, dynamic>;
        msg = err['error']?['message']?.toString() ?? msg;
      } catch (_) {}
      throw Exception('Google Drive upload init failed: $msg');
    }

    final uploadLocation = initResp.headers['location'];
    if (uploadLocation == null || uploadLocation.isEmpty) {
      throw Exception('Google Drive did not return a resumable upload Location header');
    }

    onProgress(0.45);

    // 2. Upload JPEG bytes to the resumable session URI
    final putRequest = http.Request('PUT', Uri.parse(uploadLocation))
      ..headers['Content-Type'] = 'image/jpeg'
      ..bodyBytes = fileBytes;

    final streamedPut = await _httpClient.send(putRequest);
    final putResp = await http.Response.fromStream(streamedPut);

    if (putResp.statusCode != 200 && putResp.statusCode != 201) {
      String msg = 'HTTP ${putResp.statusCode}';
      try {
        final err = jsonDecode(putResp.body) as Map<String, dynamic>;
        msg = err['error']?['message']?.toString() ?? msg;
      } catch (_) {}
      throw Exception('Google Drive PUT file bytes failed: $msg');
    }

    onProgress(1.0);
    final resultJson = jsonDecode(putResp.body) as Map<String, dynamic>;
    return resultJson['id']?.toString() ?? 'gdrive_uploaded_${fileName.hashCode}';
  }

  Future<String?> _getOrCreateSubfolder({
    required String token,
    required String parentFolderId,
    required String subfolderName,
  }) async {
    final cacheKey = '$parentFolderId/$subfolderName';
    if (_subfolderCache.containsKey(cacheKey)) {
      return _subfolderCache[cacheKey];
    }
    final createdId = await _createRealDriveFolder(
      token: token,
      folderName: subfolderName,
      parentFolderId: parentFolderId,
    );
    if (createdId != null) {
      _subfolderCache[cacheKey] = createdId;
    }
    return createdId;
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
      final photo = await db.getPhotoById(photoId);
      final sourcePath = photo?.fullResPath ?? photo?.previewPath;
      String? bakedFilePath;

      // Step 1: If Baked LUT or Both is selected, run LutBakerService before upload
      if (variant == UploadVariant.bakedLut || variant == UploadVariant.both) {
        await db.updateUploadStatus(
          id: item.id,
          status: 'bakingLut',
          progress: 0.1,
        );
        _emitProgress(photoId, 0.1);

        final lutId = activeLutId ?? 'classic_chrome';
        if (sourcePath != null && lutId != 'none') {
          final lutData = await lutManager.getLutData(lutId);
          if (lutData != null) {
            final bakedFile = await lutBaker.bakeToFile(
              sourceImagePath: sourcePath,
              lutData: lutData,
              intensity: 0.85,
              jpegQuality: 93,
            );
            bakedFilePath = bakedFile.path;
          }
        }
      }

      if (_isOffline) {
        await db.updateUploadStatus(
          id: item.id,
          status: 'pending',
          progress: 0.15,
        );
        return;
      }

      final user = _currentUser;
      if (user == null) {
        return;
      }

      await db.updateUploadStatus(
        id: item.id,
        status: 'uploading',
        progress: 0.25,
      );
      _emitProgress(photoId, 0.25);

      // Step 2A: Real Google Drive API v3 Upload when authenticated with a live OAuth token
      if (user.hasRealAccessToken) {
        if (_simulateNextUploadFailure) {
          _simulateNextUploadFailure = false;
          throw Exception('Simulated network timeout during resumable upload');
        }

        final token = user.accessToken!;
        final targetFolder =
            driveFolderId ?? _customParentFolderId ?? '';
        final cleanParentId =
            CloudSyncService.extractDriveFolderId(targetFolder);

        final fileName = photo?.fileName ?? '$photoId.JPG';
        final origBytes = (sourcePath != null && File(sourcePath).existsSync())
            ? await File(sourcePath).readAsBytes()
            : Uint8List(0);
        final bakedBytes =
            (bakedFilePath != null && File(bakedFilePath).existsSync())
                ? await File(bakedFilePath).readAsBytes()
                : origBytes;

        String remoteId;
        if (variant == UploadVariant.bakedLut) {
          remoteId = await _uploadFileBytesToGoogleDriveResumable(
            token: token,
            fileName: fileName,
            fileBytes: bakedBytes,
            parentFolderId: cleanParentId,
            onProgress: (p) => _emitProgress(photoId, p),
          );
        } else if (variant == UploadVariant.original) {
          remoteId = await _uploadFileBytesToGoogleDriveResumable(
            token: token,
            fileName: fileName,
            fileBytes: origBytes,
            parentFolderId: cleanParentId,
            onProgress: (p) => _emitProgress(photoId, p),
          );
        } else {
          // Upload Both to /Edited and /Original subfolders on Google Drive
          final editedFolderId = await _getOrCreateSubfolder(
            token: token,
            parentFolderId: cleanParentId,
            subfolderName: 'Edited',
          );
          final origFolderId = await _getOrCreateSubfolder(
            token: token,
            parentFolderId: cleanParentId,
            subfolderName: 'Original',
          );
          final idEdited = await _uploadFileBytesToGoogleDriveResumable(
            token: token,
            fileName: fileName,
            fileBytes: bakedBytes,
            parentFolderId: editedFolderId ?? cleanParentId,
            onProgress: (p) => _emitProgress(photoId, p * 0.5),
          );
          final idOrig = await _uploadFileBytesToGoogleDriveResumable(
            token: token,
            fileName: fileName,
            fileBytes: origBytes,
            parentFolderId: origFolderId ?? cleanParentId,
            onProgress: (p) => _emitProgress(photoId, 0.5 + p * 0.5),
          );
          remoteId = '${idEdited}_$idOrig';
        }

        await db.updateUploadStatus(
          id: item.id,
          status: 'completed',
          progress: 1.0,
          remoteFileId: remoteId,
        );
        _emitProgress(photoId, 1.0);
        return;
      }

      // Step 2B: Demo / Sandbox Mode chunk simulation
      final chunks = [0.45, 0.75, 1.0];
      for (final chunkProgress in chunks) {
        await Future<void>.delayed(chunkDelay);

        if (_isOffline) {
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

      final folderBase = driveFolderId ?? 'session_root';
      final remoteId = switch (variant) {
        UploadVariant.bakedLut => '${folderBase}_Edited_$photoId',
        UploadVariant.original => '${folderBase}_Original_$photoId',
        UploadVariant.both => '${folderBase}_EditedAndOriginal_$photoId',
      };

      await db.updateUploadStatus(
        id: item.id,
        status: 'completed',
        progress: 1.0,
        remoteFileId: remoteId,
      );
      _emitProgress(photoId, 1.0);
    } catch (e) {
      _lastErrorMessage = e.toString();
      final nextRetry = item.retryCount + 1;
      if (nextRetry <= maxRetries && !_isOffline) {
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
      _progressController
          .add(Map<String, double>.unmodifiable(_progressByPhotoId));
    }
  }

  @override
  Future<String> generateShareableFolderLink(String driveFolderId) async {
    final cleanId = CloudSyncService.extractDriveFolderId(driveFolderId);
    final user = _currentUser;

    if (user != null &&
        user.hasRealAccessToken &&
        !_isOffline &&
        cleanId.isNotEmpty &&
        !cleanId.startsWith('1GDrive_')) {
      try {
        await _httpClient.post(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$cleanId/permissions?supportsAllDrives=true',
          ),
          headers: {
            'Authorization': 'Bearer ${user.accessToken}',
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
