import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/features/cloud_sync/data/cloud_sync_service.dart';
import 'package:photoe_zi/features/cloud_sync/data/google_oauth_config_manager.dart';
import 'package:photoe_zi/features/film_sim/data/lut_baker_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_preset_manager.dart';

class GoogleDriveCloudSyncService implements CloudSyncService {
  final AppDatabase db;
  final LutPresetManager lutManager;
  final LutBakerService lutBaker;
  final GoogleOAuthConfigManager oauthConfigManager;
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
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();
  final Map<String, String> _sessionFolderNames = {};
  final Map<String, String> _subfolderCache = {};
  final Set<String> _publicSharedFolders = {};

  GoogleDriveCloudSyncService({
    required this.db,
    required this.lutManager,
    required this.lutBaker,
    GoogleOAuthConfigManager? oauthConfigManager,
    http.Client? httpClient,
    this.chunkDelay = const Duration(milliseconds: 55),
    this.maxRetries = 3,
    bool startInDemoMode = false,
  })  : oauthConfigManager = oauthConfigManager ?? GoogleOAuthConfigManager(),
        _httpClient = httpClient ?? http.Client() {
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

  Stream<String?> get errorStream => _errorController.stream;

  void _setError(String? message) {
    _lastErrorMessage = message;
    if (!_errorController.isClosed) {
      _errorController.add(message);
    }
  }

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
        String? verifiedEmail = email;
        String? verifiedName;
        bool verifiedViaTokenInfo = false;

        // Step 1: Check tokeninfo on oauth2.googleapis.com (no Drive API query quota consumed)
        try {
          final tokenInfoResp = await _httpClient.get(
            Uri.parse(
              'https://oauth2.googleapis.com/tokeninfo?access_token=$cleanToken',
            ),
          );
          if (tokenInfoResp.statusCode == 200) {
            final info = jsonDecode(tokenInfoResp.body) as Map<String, dynamic>;
            final tokenEmail = info['email']?.toString();
            if (tokenEmail != null && tokenEmail.isNotEmpty) {
              verifiedEmail = tokenEmail;
              verifiedName = tokenEmail.split('@').first;
              verifiedViaTokenInfo = true;
            }
          }
        } catch (_) {}

        // Step 2: Query Drive v3 /about?fields=user for rich Google Drive profile info
        try {
          final aboutResp = await _httpClient.get(
            Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user'),
            headers: {'Authorization': 'Bearer $cleanToken'},
          );

          if (aboutResp.statusCode == 200) {
            final body = jsonDecode(aboutResp.body) as Map<String, dynamic>;
            final userMap = body['user'] as Map<String, dynamic>?;
            verifiedEmail =
                userMap?['emailAddress']?.toString() ?? verifiedEmail;
            verifiedName =
                userMap?['displayName']?.toString() ?? verifiedName;

            _currentUser = GoogleDriveAccount(
              email: verifiedEmail ?? 'Google Drive User',
              displayName:
                  verifiedName ?? verifiedEmail?.split('@').first ?? 'User',
              accessToken: cleanToken,
              isDemoMode: false,
            );
            unawaited(_processQueue());
            return true;
          } else {
            // If Drive API /about hit rate limiting/quota on queries per minute,
            // but the token was verified via OAuth2 tokeninfo, login succeeds!
            if (verifiedViaTokenInfo && verifiedEmail != null) {
              _currentUser = GoogleDriveAccount(
                email: verifiedEmail,
                displayName: verifiedName ?? verifiedEmail.split('@').first,
                accessToken: cleanToken,
                isDemoMode: false,
              );
              unawaited(_processQueue());
              return true;
            }

            String apiErr = 'HTTP ${aboutResp.statusCode}';
            try {
              final errBody = jsonDecode(aboutResp.body) as Map<String, dynamic>;
              apiErr = errBody['error']?['message']?.toString() ?? apiErr;
            } catch (_) {}
            _lastErrorMessage = 'Google Drive token verification failed: $apiErr';
            return false;
          }
        } catch (e) {
          if (verifiedViaTokenInfo && verifiedEmail != null) {
            _currentUser = GoogleDriveAccount(
              email: verifiedEmail,
              displayName: verifiedName ?? verifiedEmail.split('@').first,
              accessToken: cleanToken,
              isDemoMode: false,
            );
            unawaited(_processQueue());
            return true;
          }
          _lastErrorMessage = 'Network error verifying Google Drive token: $e';
          return false;
        }
      } catch (e) {
        _lastErrorMessage = 'Google Drive token verification failed: $e';
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

  static const int _defaultLoopbackPort = 53682;

  /// Launches the official Google Sign-In OAuth 2.0 consent page in the system browser / popup
  /// (`https://accounts.google.com/o/oauth2/v2/auth`) and listens on `http://127.0.0.1:$port/`
  /// to exchange the authorization code for a live Google Drive API v3 `access_token`.
  /// Uses PhotoE-Zi's configured Google Cloud OAuth 2.0 Client credentials.
  @override
  Future<bool> signInWithBrowserOAuth({
    String? clientId,
    String? clientSecret,
  }) async {
    _lastErrorMessage = null;

    final savedConfig = await oauthConfigManager.loadConfig();
    final effectiveClientId = (clientId != null && clientId.trim().isNotEmpty)
        ? clientId.trim()
        : savedConfig.clientId;
    final effectiveClientSecret =
        (clientSecret != null && clientSecret.trim().isNotEmpty)
            ? clientSecret.trim()
            : savedConfig.clientSecret;

    if (effectiveClientId.isEmpty) {
      _lastErrorMessage =
          'PhotoE-Zi Google OAuth 2.0 Client ID is not configured yet. Please configure your personal GCP Client ID in Settings or enter an Access Token.';
      return false;
    }

    HttpServer? server;
    try {
      // Bind to port 53682 first (required by the built-in Desktop OAuth client),
      // falling back to an available loopback port if already bound.
      try {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          _defaultLoopbackPort,
          shared: true,
        );
      } catch (_) {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }

      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port/';

      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': effectiveClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': CloudSyncService.driveFullScope,
        'access_type': 'offline',
        'prompt': 'select_account consent',
      });

      await openSystemUrl(authUrl.toString(), asPopup: true);

      String? authCode;
      await for (final HttpRequest request in server.timeout(
        const Duration(minutes: 3),
      )) {
        // Ignore favicon requests from the browser
        if (request.uri.path == '/favicon.ico') {
          request.response.statusCode = 404;
          await request.response.close();
          continue;
        }

        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        request.response.headers.contentType = ContentType.html;
        if (code != null && code.isNotEmpty) {
          authCode = code;
          request.response.write('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>PhotoE-Zi · Signed in with Google</title>
  <script>
    function autoClose() {
      try { window.opener = null; } catch(e){}
      try { window.open('', '_self'); } catch(e){}
      try { window.close(); } catch(e){}
    }
    autoClose();
    setTimeout(autoClose, 300);
    setTimeout(autoClose, 800);
  </script>
</head>
<body style="background:#0F0F10;color:#F3F4F6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
  <div style="background:#1A1A1D;border:1px solid #2A2A2E;border-radius:14px;padding:36px 40px;text-align:center;max-width:380px;box-shadow:0 20px 40px rgba(0,0,0,0.5);">
    <div style="width:48px;height:48px;border-radius:50%;background:rgba(16,185,129,0.15);color:#10B981;display:inline-flex;align-items:center;justify-content:center;font-size:24px;margin-bottom:16px;">✓</div>
    <h2 style="margin:0 0 8px 0;font-size:18px;color:#F3F4F6;">Google Account Connected!</h2>
    <p style="margin:0;color:#9CA3AF;font-size:13px;line-height:1.5;">You are now signed in to <b>PhotoE-Zi</b>. Closing this window...</p>
    <button onclick="autoClose()" style="margin-top:16px;background:#27272A;border:1px solid #3F3F46;color:#E5E7EB;padding:8px 16px;border-radius:8px;font-size:12px;cursor:pointer;">Close Window</button>
  </div>
</body>
</html>
''');
          await request.response.close();
          if (Platform.isMacOS) {
            unawaited(_closeAuthBrowserWindowOnMac());
          }
          break;
        } else if (error != null) {
          request.response.write('''
<!DOCTYPE html>
<html>
<body style="background:#0F0F10;color:#EF4444;font-family:sans-serif;text-align:center;padding-top:60px;">
  <h2>Google Sign-In Cancelled ($error)</h2>
</body>
</html>
''');
          await request.response.close();
          break;
        } else {
          request.response.statusCode = 200;
          await request.response.close();
        }
      }

      if (authCode == null || authCode.isEmpty) {
        _lastErrorMessage = 'Google Sign-In was cancelled or timed out.';
        return false;
      }

      final tokenBody = <String, String>{
        'code': authCode,
        'client_id': effectiveClientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      };
      if (effectiveClientSecret.isNotEmpty) {
        tokenBody['client_secret'] = effectiveClientSecret;
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
      _lastErrorMessage = 'Google Browser Sign-In error: $e';
      return false;
    } finally {
      await server?.close(force: true);
    }
  }

  /// Opens a URL in the host OS browser (macOS `open`, Linux `xdg-open`, Windows `start`).
  /// On macOS, if [asPopup] is true and Google Chrome is installed, opens Chrome in
  /// standalone app mode (`--app=...`) to provide a dedicated, frameless login popup.
  static Future<void> openSystemUrl(String url, {bool asPopup = false}) async {
    try {
      if (Platform.isMacOS) {
        if (asPopup && Directory('/Applications/Google Chrome.app').existsSync()) {
          final res = await Process.run('open', [
            '-na',
            '/Applications/Google Chrome.app',
            '--args',
            '--app=$url',
            '--window-size=520,680',
          ]);
          if (res.exitCode == 0) return;
        }
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url]);
      }
    } catch (_) {}
  }

  static Future<void> _closeAuthBrowserWindowOnMac() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await Process.run('osascript', [
        '-e',
        '''
        try
          tell application "Google Chrome"
            repeat with aWindow in windows
              repeat with aTab in tabs of aWindow
                if URL of aTab contains "127.0.0.1" or title of aTab contains "PhotoE-Zi" then
                  close aTab
                end if
              end repeat
            end repeat
          end tell
        end try
        ''',
      ]);
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
      if (msg.contains('Quota exceeded')) {
        _setError(
          'Google Drive query quota limit reached on shared Client ID. Please provide your personal GCP Client ID in Google Drive settings.',
        );
      }
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
  Future<void> retryFailedUploads({
    String? driveFolderId,
    String? activeLutId,
  }) async {
    _setError(null);
    await db.resetFailedUploadsToPending();
    if (!_isOffline && isSignedIn) {
      unawaited(
        _processQueue(
          driveFolderId: driveFolderId,
          activeLutId: activeLutId,
        ),
      );
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
      if (msg.contains('Quota exceeded')) {
        _setError(
          'Google Drive query quota limit reached on shared Client ID. Please provide your personal GCP Client ID in Google Drive settings.',
        );
      }
      throw Exception('Google Drive upload init failed: $msg');
    }

    final uploadLocation = initResp.headers['location'];
    if (uploadLocation == null || uploadLocation.isEmpty) {
      throw Exception('Google Drive did not return a resumable upload Location header');
    }

    onProgress(0.45);

    // 2. Upload JPEG bytes to the resumable session URI
    final putRequest = http.Request('PUT', Uri.parse(uploadLocation))
      ..headers['Authorization'] = 'Bearer $token'
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
      if (photo == null) {
        throw Exception('Photo record not found in local database ($photoId)');
      }
      final session = await db.getSessionById(photo.sessionId);
      final resolvedLutId = activeLutId ?? session?.activeLutId ?? 'classic_chrome';
      final resolvedDriveFolderId =
          driveFolderId ?? session?.driveFolderId ?? _customParentFolderId ?? '';

      String? sourcePath = photo.fullResPath ?? photo.previewPath;
      if (sourcePath == null || !File(sourcePath).existsSync()) {
        // Fallback to previewPath if fullResPath is missing
        if (photo.previewPath != null && File(photo.previewPath!).existsSync()) {
          sourcePath = photo.previewPath;
        }
      }
      String? bakedFilePath;

      // Step 1: If Baked LUT or Both is selected, run LutBakerService before upload
      if (variant == UploadVariant.bakedLut || variant == UploadVariant.both) {
        await db.updateUploadStatus(
          id: item.id,
          status: 'bakingLut',
          progress: 0.1,
        );
        _emitProgress(photoId, 0.1);

        if (sourcePath != null &&
            File(sourcePath).existsSync() &&
            resolvedLutId != 'none') {
          final lutData = await lutManager.getLutData(resolvedLutId);
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
        final cleanParentId =
            CloudSyncService.extractDriveFolderId(resolvedDriveFolderId);

        final fileName = photo.fileName;
        final origBytes = (sourcePath != null && File(sourcePath).existsSync())
            ? await File(sourcePath).readAsBytes()
            : Uint8List(0);
        final bakedBytes =
            (bakedFilePath != null && File(bakedFilePath).existsSync())
                ? await File(bakedFilePath).readAsBytes()
                : origBytes;

        if (bakedBytes.isEmpty && origBytes.isEmpty) {
          throw Exception(
            'Local image file missing for $fileName. Take a new shot to upload.',
          );
        }

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

        _setError(null);
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
      final cleanErr = e.toString().replaceFirst('Exception: ', '');
      _setError(cleanErr);
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
    _errorController.close();
    _httpClient.close();
  }
}
