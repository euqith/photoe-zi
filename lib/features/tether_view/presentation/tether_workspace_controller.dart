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
import 'package:photoe_zi/features/camera/data/mock_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/film_sim/data/lut_baker_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_preset_manager.dart';
import 'package:photoe_zi/features/film_sim/domain/cube_lut_parser.dart';
import 'package:photoe_zi/features/film_sim/domain/lut_preset.dart';

enum FilmstripFilter { all, favorites }

class TetherSessionState {
  final String activeSessionId;
  final String activeSessionName;
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
  final driver = MockCameraDriver();
  ref.onDispose(driver.dispose);
  return driver;
});

final lutPresetManagerProvider = Provider<LutPresetManager>((ref) {
  return LutPresetManager();
});

final lutBakerServiceProvider = Provider<LutBakerService>((ref) {
  return const LutBakerService();
});

class TetherWorkspaceController extends StateNotifier<TetherSessionState> {
  final AppDatabase db;
  final BaseCameraDriver cameraDriver;
  final LutPresetManager lutManager;
  final LutBakerService lutBaker;
  StreamSubscription<CameraConnectionState>? _connSub;
  StreamSubscription<IncomingPhoto>? _photoSub;

  TetherWorkspaceController({
    required this.db,
    required this.cameraDriver,
    required this.lutManager,
    required this.lutBaker,
  }) : super(TetherSessionState(cameraDriverName: cameraDriver.driverName)) {
    _initializeSessionAndStreams();
  }

  Future<void> _initializeSessionAndStreams() async {
    final existing = await db.getSessionById(state.activeSessionId);
    if (existing == null) {
      await db.createSession(
        SessionsCompanion.insert(
          id: state.activeSessionId,
          name: state.activeSessionName,
          createdAt: DateTime.now(),
          activeLutId: Value(state.activeLutId),
        ),
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

      await db.enqueueUpload(
        UploadQueueCompanion.insert(
          id: 'uq_${incoming.id}',
          photoId: incoming.id,
          variant: 'bakedLut',
          status: const Value('completed'),
          progress: const Value(1.0),
        ),
      );
    } else if (incoming.fullResLocalPath != null) {
      await db.updatePhotoFullResPath(incoming.id, incoming.fullResLocalPath!);
      // Auto-bake full-resolution JPEG with active LUT in background isolate (Issue #2.3)
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
    }
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

  /// Opens native file picker to import a custom `.cube` file into the preset directory
  /// and automatically activates it.
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
    await db.togglePhotoFavorite(photo.id, !photo.isFavorite);
  }

  Future<void> toggleRejected(Photo photo) async {
    await db.togglePhotoRejected(photo.id, !photo.isRejected);
  }

  Future<void> createNewSession(String name) async {
    final cleanName = name.trim().isEmpty ? 'Studio_Session' : name.trim();
    final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    await db.createSession(
      SessionsCompanion.insert(
        id: sessionId,
        name: cleanName,
        createdAt: DateTime.now(),
        activeLutId: Value(state.activeLutId),
      ),
    );
    state = state.copyWith(
      activeSessionId: sessionId,
      activeSessionName: cleanName,
      clearSelectedPhoto: true,
      lockLatest: true,
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _photoSub?.cancel();
    super.dispose();
  }
}

final tetherControllerProvider =
    StateNotifierProvider<TetherWorkspaceController, TetherSessionState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final driver = ref.watch(cameraDriverProvider);
  final lutManager = ref.watch(lutPresetManagerProvider);
  final lutBaker = ref.watch(lutBakerServiceProvider);
  return TetherWorkspaceController(
    db: db,
    cameraDriver: driver,
    lutManager: lutManager,
    lutBaker: lutBaker,
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
