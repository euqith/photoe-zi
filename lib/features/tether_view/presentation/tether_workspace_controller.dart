import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/camera/data/camera_driver_manager.dart';
import 'package:photoe_zi/features/camera/data/mock_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/camera_types.dart';
import 'package:photoe_zi/features/cloud_sync/data/cloud_sync_service.dart';
import 'package:photoe_zi/features/cloud_sync/data/google_drive_cloud_sync_service.dart';
import 'package:photoe_zi/features/cloud_sync/data/google_oauth_config_manager.dart';
import 'package:photoe_zi/features/film_sim/data/lut_baker_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_preset_manager.dart';
import 'package:photoe_zi/features/film_sim/domain/cube_lut_parser.dart';
import 'package:photoe_zi/features/film_sim/domain/lut_preset.dart';

enum FilmstripFilter { all, favorites }

class TetherSessionState {
  final String activeSessionId;
  final String activeSessionName;
  final String? driveFolderId;
  final String sessionFolderPath;
  final String shareableFolderUrl;
  final bool isGoogleSignedIn;
  final bool isGoogleDemoMode;
  final String? googleUserEmail;
  final String? googleAuthError;
  final String? customParentFolderId;
  final AutoUploadMode autoUploadMode;
  final UploadVariant uploadVariant;
  final bool isOffline;
  final Map<String, double> uploadProgressByPhotoId;
  final CameraConnectionState cameraState;
  final String cameraDriverName;
  final String? selectedPhotoId;
  final bool lockLatest;
  final bool isZenMode;
  final bool isRightInspectorVisible;
  final bool isVerticalLeftFilmstrip;
  final bool isBeforeAfterPressed;
  final FilmstripFilter filter;
  final String activeLutId;
  final double lutIntensity;
  final List<LutPreset> availablePresets;
  final CubeLutData? activeLutData;
  final ui.Image? activeLutTexture;
  final Map<String, Uint8List> inMemoryPreviews;
  final Map<String, String> bakedFilePaths;

  const TetherSessionState({
    this.activeSessionId = 'session_studio_a',
    this.activeSessionName = 'Studio_A',
    this.driveFolderId = '1GDrive_TetherApp_Studio_A',
    this.sessionFolderPath = 'TetherApp / 2026-11-20_Studio_A',
    this.shareableFolderUrl =
        'https://drive.google.com/drive/folders/1GDrive_TetherApp_Studio_A?usp=sharing',
    this.isGoogleSignedIn = false,
    this.isGoogleDemoMode = false,
    this.googleUserEmail,
    this.googleAuthError,
    this.customParentFolderId,
    this.autoUploadMode = AutoUploadMode.all,
    this.uploadVariant = UploadVariant.bakedLut,
    this.isOffline = false,
    this.uploadProgressByPhotoId = const {},
    this.cameraState = CameraConnectionState.disconnected,
    this.cameraDriverName = 'Canon EOS 6D (Mock Simulator)',
    this.selectedPhotoId,
    this.lockLatest = true,
    this.isZenMode = false,
    this.isRightInspectorVisible = true,
    this.isVerticalLeftFilmstrip = false,
    this.isBeforeAfterPressed = false,
    this.filter = FilmstripFilter.all,
    this.activeLutId = 'classic_chrome',
    this.lutIntensity = 0.85,
    this.availablePresets = LutPreset.builtInPresets,
    this.activeLutData,
    this.activeLutTexture,
    this.inMemoryPreviews = const {},
    this.bakedFilePaths = const {},
  });

  TetherSessionState copyWith({
    String? activeSessionId,
    String? activeSessionName,
    String? driveFolderId,
    String? sessionFolderPath,
    String? shareableFolderUrl,
    bool? isGoogleSignedIn,
    bool? isGoogleDemoMode,
    String? googleUserEmail,
    bool clearGoogleUser = false,
    String? googleAuthError,
    bool clearGoogleAuthError = false,
    String? customParentFolderId,
    AutoUploadMode? autoUploadMode,
    UploadVariant? uploadVariant,
    bool? isOffline,
    Map<String, double>? uploadProgressByPhotoId,
    CameraConnectionState? cameraState,
    String? cameraDriverName,
    String? selectedPhotoId,
    bool clearSelectedPhoto = false,
    bool? lockLatest,
    bool? isZenMode,
    bool? isRightInspectorVisible,
    bool? isVerticalLeftFilmstrip,
    bool? isBeforeAfterPressed,
    FilmstripFilter? filter,
    String? activeLutId,
    double? lutIntensity,
    List<LutPreset>? availablePresets,
    CubeLutData? activeLutData,
    bool clearActiveLut = false,
    ui.Image? activeLutTexture,
    Map<String, Uint8List>? inMemoryPreviews,
    Map<String, String>? bakedFilePaths,
  }) {
    return TetherSessionState(
      activeSessionId: activeSessionId ?? this.activeSessionId,
      activeSessionName: activeSessionName ?? this.activeSessionName,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      sessionFolderPath: sessionFolderPath ?? this.sessionFolderPath,
      shareableFolderUrl: shareableFolderUrl ?? this.shareableFolderUrl,
      isGoogleSignedIn: isGoogleSignedIn ?? this.isGoogleSignedIn,
      isGoogleDemoMode: isGoogleDemoMode ?? this.isGoogleDemoMode,
      googleUserEmail:
          clearGoogleUser ? null : (googleUserEmail ?? this.googleUserEmail),
      googleAuthError: clearGoogleAuthError
          ? null
          : (googleAuthError ?? this.googleAuthError),
      customParentFolderId: customParentFolderId ?? this.customParentFolderId,
      autoUploadMode: autoUploadMode ?? this.autoUploadMode,
      uploadVariant: uploadVariant ?? this.uploadVariant,
      isOffline: isOffline ?? this.isOffline,
      uploadProgressByPhotoId:
          uploadProgressByPhotoId ?? this.uploadProgressByPhotoId,
      cameraState: cameraState ?? this.cameraState,
      cameraDriverName: cameraDriverName ?? this.cameraDriverName,
      selectedPhotoId:
          clearSelectedPhoto ? null : (selectedPhotoId ?? this.selectedPhotoId),
      lockLatest: lockLatest ?? this.lockLatest,
      isZenMode: isZenMode ?? this.isZenMode,
      isRightInspectorVisible:
          isRightInspectorVisible ?? this.isRightInspectorVisible,
      isVerticalLeftFilmstrip:
          isVerticalLeftFilmstrip ?? this.isVerticalLeftFilmstrip,
      isBeforeAfterPressed: isBeforeAfterPressed ?? this.isBeforeAfterPressed,
      filter: filter ?? this.filter,
      activeLutId: activeLutId ?? this.activeLutId,
      lutIntensity: lutIntensity ?? this.lutIntensity,
      availablePresets: availablePresets ?? this.availablePresets,
      activeLutData:
          clearActiveLut ? null : (activeLutData ?? this.activeLutData),
      activeLutTexture:
          clearActiveLut ? null : (activeLutTexture ?? this.activeLutTexture),
      inMemoryPreviews: inMemoryPreviews ?? this.inMemoryPreviews,
      bakedFilePaths: bakedFilePaths ?? this.bakedFilePaths,
    );
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final cameraDriverProvider = Provider<BaseCameraDriver>((ref) {
  final manager = CameraDriverManager();
  ref.onDispose(manager.dispose);
  return manager;
});

final lutPresetManagerProvider = Provider<LutPresetManager>((ref) {
  return LutPresetManager();
});

final lutBakerServiceProvider = Provider<LutBakerService>((ref) {
  return const LutBakerService();
});

final googleOAuthConfigManagerProvider =
    Provider<GoogleOAuthConfigManager>((ref) {
  return GoogleOAuthConfigManager();
});

final cloudSyncServiceProvider = Provider<GoogleDriveCloudSyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final lutManager = ref.watch(lutPresetManagerProvider);
  final lutBaker = ref.watch(lutBakerServiceProvider);
  final oauthManager = ref.watch(googleOAuthConfigManagerProvider);
  final service = GoogleDriveCloudSyncService(
    db: db,
    lutManager: lutManager,
    lutBaker: lutBaker,
    oauthConfigManager: oauthManager,
  );
  ref.onDispose(service.dispose);
  return service;
});

class TetherWorkspaceController extends StateNotifier<TetherSessionState> {
  final AppDatabase db;
  final BaseCameraDriver cameraDriver;
  final LutPresetManager lutManager;
  final LutBakerService lutBaker;
  final GoogleDriveCloudSyncService cloudSync;

  StreamSubscription<CameraConnectionState>? _connSub;
  StreamSubscription<IncomingPhoto>? _photoSub;
  StreamSubscription<Map<String, double>>? _progressSub;
  StreamSubscription<String?>? _errorSub;

  TetherWorkspaceController({
    required this.db,
    required this.cameraDriver,
    required this.lutManager,
    required this.lutBaker,
    required this.cloudSync,
  }) : super(
          TetherSessionState(
            cameraDriverName: cameraDriver.driverName,
            isGoogleSignedIn: cloudSync.isSignedIn,
            googleUserEmail: cloudSync.currentUser?.email,
          ),
        ) {
    _initializeSessionAndStreams();
  }

  Future<void> _initializeSessionAndStreams() async {
    final existing = await db.getSessionById(state.activeSessionId);
    String folderId;
    if (existing == null || existing.driveFolderId == null) {
      folderId = await cloudSync.createSessionFolder(state.activeSessionName);
      await db.createSession(
        SessionsCompanion.insert(
          id: state.activeSessionId,
          name: state.activeSessionName,
          createdAt: DateTime.now(),
          driveFolderId: Value(folderId),
          activeLutId: Value(state.activeLutId),
        ),
      );
    } else {
      folderId = existing.driveFolderId!;
    }

    final shareLink = await cloudSync.generateShareableFolderLink(folderId);
    final folderDisplay = cloudSync.getSessionFolderPathDisplay(
      folderId,
      state.activeSessionName,
    );

    if (mounted) {
      state = state.copyWith(
        driveFolderId: folderId,
        sessionFolderPath: folderDisplay,
        shareableFolderUrl: shareLink,
      );
    }

    final presets = await lutManager.loadSavedCustomPresets();
    if (mounted) {
      state = state.copyWith(availablePresets: presets);
    }
    await _loadActiveLutResources(state.activeLutId);

    _connSub = cameraDriver.connectionStateStream.listen((connState) {
      if (mounted) {
        state = state.copyWith(cameraState: connState);
      }
    });

    _photoSub = cameraDriver.onNewPhotoStream.listen(_handleIncomingPhoto);
    _progressSub = cloudSync.uploadProgressStream.listen((progressMap) {
      if (mounted) {
        state = state.copyWith(uploadProgressByPhotoId: progressMap);
      }
    });
    _errorSub = cloudSync.errorStream.listen((errMsg) {
      if (mounted) {
        state = state.copyWith(
          googleAuthError: errMsg,
          clearGoogleAuthError: errMsg == null,
        );
      }
    });
  }

  Future<void> _loadActiveLutResources(String lutId) async {
    if (lutId == 'none' || lutId.isEmpty) {
      if (mounted) {
        state = state.copyWith(clearActiveLut: true);
      }
      return;
    }

    try {
      final lutData = await lutManager.getLutData(lutId);
      final lutTexture = await lutManager.getGpuLutTexture(lutId);
      if (mounted && state.activeLutId == lutId) {
        state = state.copyWith(
          activeLutData: lutData,
          activeLutTexture: lutTexture,
        );
      }
    } catch (_) {}
  }

  Future<void> _handleIncomingPhoto(IncomingPhoto incoming) async {
    if (!mounted) return;

    String? previewPath;
    final updatedPreviews =
        Map<String, Uint8List>.from(state.inMemoryPreviews);

    if (incoming.previewBytes != null) {
      updatedPreviews[incoming.id] = incoming.previewBytes!;
      try {
        final previewDir = Directory(
          p.join(Directory.systemTemp.path, 'photoe_zi_previews'),
        );
        if (!await previewDir.exists()) {
          await previewDir.create(recursive: true);
        }
        previewPath = p.join(previewDir.path, '${incoming.id}_thumb.jpg');
        await File(previewPath).writeAsBytes(incoming.previewBytes!);
      } catch (_) {}
    }

    final existingPhoto = await db.getPhotoById(incoming.id);
    if (existingPhoto == null) {
      await db.upsertPhoto(
        PhotosCompanion.insert(
          id: incoming.id,
          sessionId: state.activeSessionId,
          fileName: incoming.fileName,
          previewPath: Value(previewPath),
          fullResPath: Value(incoming.fullResLocalPath),
          exifJson: Value(jsonEncode(incoming.exifData)),
          capturedAt: incoming.capturedAt,
        ),
      );

      // Issue #3.3: Trigger auto-upload immediately if mode == AutoUploadMode.all
      if (state.autoUploadMode == AutoUploadMode.all) {
        await enqueuePhotoForUpload(incoming.id);
      }
    } else if (incoming.fullResLocalPath != null) {
      await db.updatePhotoFullResPath(incoming.id, incoming.fullResLocalPath!);
      unawaited(
        _autoBakeFullResInBackground(incoming.id, incoming.fullResLocalPath!),
      );
    }

    if (!mounted) return;

    final shouldSelectNew =
        state.lockLatest || state.selectedPhotoId == null;
    state = state.copyWith(
      selectedPhotoId: shouldSelectNew ? incoming.id : state.selectedPhotoId,
      inMemoryPreviews: updatedPreviews,
    );
  }

  Future<void> _autoBakeFullResInBackground(
    String photoId,
    String fullResPath,
  ) async {
    final lutData = state.activeLutData;
    if (lutData == null || state.activeLutId == 'none') {
      return;
    }
    try {
      final bakedFile = await lutBaker.bakeToFile(
        sourceImagePath: fullResPath,
        lutData: lutData,
        intensity: state.lutIntensity,
        jpegQuality: 93,
      );
      if (mounted) {
        final nextBaked = Map<String, String>.from(state.bakedFilePaths);
        nextBaked[photoId] = bakedFile.path;
        state = state.copyWith(bakedFilePaths: nextBaked);
      }
    } catch (_) {}
  }

  // --- Google Drive Cloud Sync Controls (Sprint 3 & Fix #3.5) ---

  Future<void> _ensureRealGoogleDriveFolderAfterSignIn() async {
    final currentFolder = state.driveFolderId;
    if (cloudSync.currentUser?.hasRealAccessToken == true &&
        (currentFolder == null || currentFolder.startsWith('1GDrive_'))) {
      try {
        final realFolderId =
            await cloudSync.createSessionFolder(state.activeSessionName);
        final shareLink =
            await cloudSync.generateShareableFolderLink(realFolderId);
        final folderDisplay = cloudSync.getSessionFolderPathDisplay(
          realFolderId,
          state.activeSessionName,
        );
        await db.updateSessionDriveFolder(state.activeSessionId, realFolderId);
        if (mounted) {
          state = state.copyWith(
            driveFolderId: realFolderId,
            sessionFolderPath: folderDisplay,
            shareableFolderUrl: shareLink,
          );
        }
      } catch (_) {}
    }
  }

  Future<bool> signInGoogleWithAccessToken({
    required String accessToken,
    String? email,
  }) async {
    final ok = await cloudSync.signIn(
      email: email,
      accessToken: accessToken,
      isDemoMode: false,
    );
    if (mounted) {
      state = state.copyWith(
        isGoogleSignedIn: cloudSync.isSignedIn,
        isGoogleDemoMode: cloudSync.currentUser?.isDemoMode ?? false,
        googleUserEmail: cloudSync.currentUser?.email,
        googleAuthError: cloudSync.lastErrorMessage,
        clearGoogleAuthError: ok,
      );
    }
    if (ok) {
      await _ensureRealGoogleDriveFolderAfterSignIn();
    }
    return ok;
  }

  Future<GoogleOAuthConfig> getOAuthConfig() async {
    return await cloudSync.oauthConfigManager.loadConfig();
  }

  Future<GoogleOAuthConfig> saveOAuthConfig({
    required String clientId,
    String? clientSecret,
  }) async {
    return await cloudSync.oauthConfigManager.saveConfig(
      clientId: clientId,
      clientSecret: clientSecret,
    );
  }

  Future<void> clearOAuthConfig() async {
    await cloudSync.oauthConfigManager.clearConfig();
  }

  Future<bool> signInGoogleWithBrowserOAuth({
    String? clientId,
    String? clientSecret,
  }) async {
    final ok = await cloudSync.signInWithBrowserOAuth(
      clientId: clientId,
      clientSecret: clientSecret,
    );
    if (mounted) {
      state = state.copyWith(
        isGoogleSignedIn: cloudSync.isSignedIn,
        isGoogleDemoMode: cloudSync.currentUser?.isDemoMode ?? false,
        googleUserEmail: cloudSync.currentUser?.email,
        googleAuthError: cloudSync.lastErrorMessage,
        clearGoogleAuthError: ok,
      );
    }
    if (ok) {
      await _ensureRealGoogleDriveFolderAfterSignIn();
    }
    return ok;
  }

  Future<bool> signInGoogleAccount(
    String email, {
    String? accessToken,
    bool isDemoMode = false,
  }) async {
    final ok = await cloudSync.signIn(
      email: email,
      accessToken: accessToken,
      isDemoMode: isDemoMode,
    );
    if (mounted) {
      state = state.copyWith(
        isGoogleSignedIn: cloudSync.isSignedIn,
        isGoogleDemoMode: cloudSync.currentUser?.isDemoMode ?? false,
        googleUserEmail: cloudSync.currentUser?.email,
        googleAuthError: cloudSync.lastErrorMessage,
        clearGoogleAuthError: ok,
      );
    }
    if (ok) {
      await _ensureRealGoogleDriveFolderAfterSignIn();
    }
    return ok;
  }

  Future<void> signOutGoogleAccount() async {
    await cloudSync.signOut();
    if (mounted) {
      state = state.copyWith(
        isGoogleSignedIn: false,
        isGoogleDemoMode: false,
        clearGoogleUser: true,
        clearGoogleAuthError: true,
      );
    }
  }

  /// Registers a custom Google Drive Folder link or ID for the active session
  /// and optionally sets the parent folder for future sessions.
  Future<void> registerCustomDriveFolderLink(
    String folderLinkOrId, {
    bool setAsDefaultParent = false,
  }) async {
    final trimmed = folderLinkOrId.trim();
    if (trimmed.isEmpty) return;

    final cleanFolderId = CloudSyncService.extractDriveFolderId(trimmed);
    final shareLink = await cloudSync.generateShareableFolderLink(trimmed);
    if (setAsDefaultParent) {
      cloudSync.setCustomParentFolder(cleanFolderId);
    }

    await db.updateSessionDriveFolder(state.activeSessionId, cleanFolderId);
    if (mounted) {
      state = state.copyWith(
        driveFolderId: cleanFolderId,
        customParentFolderId:
            setAsDefaultParent ? cleanFolderId : state.customParentFolderId,
        sessionFolderPath: 'GDrive / $cleanFolderId',
        shareableFolderUrl: shareLink,
      );
    }
  }

  void setAutoUploadMode(AutoUploadMode mode) {
    state = state.copyWith(autoUploadMode: mode);
  }

  void setUploadVariant(UploadVariant variant) {
    state = state.copyWith(uploadVariant: variant);
  }

  void setOfflineMode(bool offline) {
    cloudSync.setOfflineMode(offline);
    state = state.copyWith(isOffline: offline);
  }

  Future<void> enqueuePhotoForUpload(String photoId) async {
    final folderId = state.driveFolderId ?? 'TetherApp_Root';
    await cloudSync.enqueuePhoto(
      localPhotoId: photoId,
      driveFolderId: folderId,
      variant: state.uploadVariant,
      activeLutId: state.activeLutId,
    );
  }

  Future<void> retryFailedUploads() async {
    await cloudSync.retryFailedUploads(
      driveFolderId: state.driveFolderId,
      activeLutId: state.activeLutId,
    );
  }

  Future<UploadAllSummary> uploadAllPhotosForCurrentSession() async {
    await _ensureRealGoogleDriveFolderAfterSignIn();
    final folderId = state.driveFolderId ?? 'TetherApp_Root';
    final summary = await cloudSync.uploadAllPhotos(
      sessionId: state.activeSessionId,
      driveFolderId: folderId,
      variant: state.uploadVariant,
      activeLutId: state.activeLutId,
    );
    return summary;
  }

  Future<String> prepareShareableSessionLink() async {
    final folderId = state.driveFolderId ?? state.shareableFolderUrl;
    final link = await cloudSync.generateShareableFolderLink(folderId);
    if (mounted) {
      state = state.copyWith(shareableFolderUrl: link);
    }
    return link;
  }

  // --- Camera & Workspace Controls ---

  Future<void> toggleCameraConnection() async {
    if (state.cameraState == CameraConnectionState.connected ||
        state.cameraState == CameraConnectionState.connecting) {
      await cameraDriver.disconnect();
    } else {
      await cameraDriver.connect();
    }
  }

  Future<void> triggerManualMockCapture() async {
    final driver = cameraDriver;
    if (driver is MockCameraDriver) {
      await driver.triggerManualShot();
    } else if (driver is CameraDriverManager) {
      final active = driver.activeDriver;
      if (active is MockCameraDriver) {
        await active.triggerManualShot();
      }
    }
  }

  Future<List<CameraDriverInfo>> getAvailableCameraDrivers() async {
    final driver = cameraDriver;
    if (driver is CameraDriverManager) {
      return await driver.getAvailableDrivers();
    }
    return const [
      CameraDriverInfo(
        id: 'mock',
        name: 'Mock Camera Simulator',
        type: CameraDriverType.mock,
        isAvailable: true,
      ),
    ];
  }

  Future<void> switchCameraDriver(
    String driverId, {
    String? ipAddress,
    int? port,
  }) async {
    final driver = cameraDriver;
    if (driver is CameraDriverManager) {
      await driver.switchDriver(driverId, ipAddress: ipAddress, port: port);
      if (mounted) {
        state = state.copyWith(cameraDriverName: driver.driverName);
      }
    }
  }

  String get activeCameraDriverId {
    final driver = cameraDriver;
    if (driver is CameraDriverManager) {
      return driver.currentDriverId;
    }
    return 'mock';
  }

  void selectPhoto(String photoId, {required bool isLatestPhoto}) {
    state = state.copyWith(
      selectedPhotoId: photoId,
      lockLatest: isLatestPhoto ? state.lockLatest : false,
    );
  }

  void jumpToLatest(String latestPhotoId) {
    state = state.copyWith(
      selectedPhotoId: latestPhotoId,
      lockLatest: true,
    );
  }

  void toggleLockLatest(String? latestPhotoId) {
    final nextLock = !state.lockLatest;
    state = state.copyWith(
      lockLatest: nextLock,
      selectedPhotoId: (nextLock && latestPhotoId != null)
          ? latestPhotoId
          : state.selectedPhotoId,
    );
  }

  void toggleZenMode() {
    state = state.copyWith(isZenMode: !state.isZenMode);
  }

  void toggleRightInspector() {
    state = state.copyWith(
      isRightInspectorVisible: !state.isRightInspectorVisible,
    );
  }

  void toggleFilmstripOrientation() {
    state = state.copyWith(
      isVerticalLeftFilmstrip: !state.isVerticalLeftFilmstrip,
    );
  }

  void setBeforeAfterPressed(bool pressed) {
    state = state.copyWith(isBeforeAfterPressed: pressed);
  }

  void setFilter(FilmstripFilter filter) {
    state = state.copyWith(filter: filter);
  }

  Future<void> setActiveLut(String lutId) async {
    state = state.copyWith(activeLutId: lutId);
    await db.updateSessionActiveLut(state.activeSessionId, lutId);
    await _loadActiveLutResources(lutId);
  }

  void setLutIntensity(double intensity) {
    state = state.copyWith(lutIntensity: intensity.clamp(0.0, 1.0));
  }

  Future<LutPreset?> pickAndImportCustomCubeFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final pickedPath = result.files.single.path;
    if (pickedPath == null) {
      return null;
    }
    return importCustomCubeFromFile(File(pickedPath));
  }

  Future<LutPreset> importCustomCubeFromFile(File sourceFile) async {
    final imported = await lutManager.importCustomCubeFile(sourceFile);
    if (mounted) {
      state = state.copyWith(availablePresets: lutManager.allPresets);
      await setActiveLut(imported.id);
    }
    return imported;
  }

  Future<LutPreset> importCustomCubeFromString(
    String cubeContent, {
    required String presetName,
  }) async {
    final imported = await lutManager.importCustomCubeString(
      cubeContent,
      fileName: presetName,
    );
    if (mounted) {
      state = state.copyWith(availablePresets: lutManager.allPresets);
      await setActiveLut(imported.id);
    }
    return imported;
  }

  Future<void> toggleFavorite(Photo photo) async {
    final nextFav = !photo.isFavorite;
    await db.togglePhotoFavorite(photo.id, nextFav);
    // Issue #3.3: When in "Favorites Only" mode, pressing ♥ automatically enqueues the photo
    if (nextFav && state.autoUploadMode == AutoUploadMode.favoritesOnly) {
      await enqueuePhotoForUpload(photo.id);
    }
  }

  Future<void> toggleRejected(Photo photo) async {
    await db.togglePhotoRejected(photo.id, !photo.isRejected);
  }

  Future<void> createNewSession(
    String name, {
    String? customDriveLinkOrId,
  }) async {
    final cleanName = name.trim().isEmpty ? 'Studio_Session' : name.trim();
    final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';

    String folderId;
    String folderDisplay;
    String shareUrl;

    if (customDriveLinkOrId != null && customDriveLinkOrId.trim().isNotEmpty) {
      folderId = CloudSyncService.extractDriveFolderId(customDriveLinkOrId);
      folderDisplay = 'GDrive / $folderId';
      shareUrl = await cloudSync.generateShareableFolderLink(customDriveLinkOrId);
    } else {
      folderId = await cloudSync.createSessionFolder(cleanName);
      folderDisplay =
          cloudSync.getSessionFolderPathDisplay(folderId, cleanName);
      shareUrl = await cloudSync.generateShareableFolderLink(folderId);
    }

    await db.createSession(
      SessionsCompanion.insert(
        id: sessionId,
        name: cleanName,
        createdAt: DateTime.now(),
        driveFolderId: Value(folderId),
        activeLutId: Value(state.activeLutId),
      ),
    );
    state = state.copyWith(
      activeSessionId: sessionId,
      activeSessionName: cleanName,
      driveFolderId: folderId,
      sessionFolderPath: folderDisplay,
      shareableFolderUrl: shareUrl,
      clearSelectedPhoto: true,
      lockLatest: true,
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _photoSub?.cancel();
    _progressSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}

final tetherControllerProvider =
    StateNotifierProvider<TetherWorkspaceController, TetherSessionState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final driver = ref.watch(cameraDriverProvider);
  final lutManager = ref.watch(lutPresetManagerProvider);
  final lutBaker = ref.watch(lutBakerServiceProvider);
  final cloudSync = ref.watch(cloudSyncServiceProvider);
  return TetherWorkspaceController(
    db: db,
    cameraDriver: driver,
    lutManager: lutManager,
    lutBaker: lutBaker,
    cloudSync: cloudSync,
  );
});

final sessionPhotosStreamProvider = StreamProvider<List<Photo>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final sessionId =
      ref.watch(tetherControllerProvider.select((s) => s.activeSessionId));
  return db.watchPhotosForSession(sessionId);
});

final uploadQueueStreamProvider = StreamProvider<List<UploadQueueData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchUploadQueue();
});

final activePhotoHistogramProvider =
    FutureProvider.family<RgbHistogramData, String?>((ref, photoId) async {
  if (photoId == null) return RgbHistogramData.empty();
  final state = ref.watch(tetherControllerProvider);
  final effectiveLut =
      (state.isBeforeAfterPressed || state.activeLutId == 'none')
          ? null
          : state.activeLutData;
  final effectiveIntensity =
      (state.isBeforeAfterPressed || state.activeLutId == 'none')
          ? 0.0
          : state.lutIntensity;

  final previewBytes = state.inMemoryPreviews[photoId];
  if (previewBytes != null) {
    return HistogramCalculator.computeFromBytes(
      previewBytes,
      lutData: effectiveLut,
      lutIntensity: effectiveIntensity,
    );
  }
  final db = ref.watch(appDatabaseProvider);
  final photo = await db.getPhotoById(photoId);
  if (photo?.fullResPath != null) {
    return HistogramCalculator.computeFromFilePath(
      photo!.fullResPath!,
      lutData: effectiveLut,
      lutIntensity: effectiveIntensity,
    );
  }
  if (photo?.previewPath != null) {
    return HistogramCalculator.computeFromFilePath(
      photo!.previewPath!,
      lutData: effectiveLut,
      lutIntensity: effectiveIntensity,
    );
  }
  return RgbHistogramData.empty();
});
