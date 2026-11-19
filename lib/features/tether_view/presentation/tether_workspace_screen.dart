import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/cloud_sync/presentation/drive_sync_panel.dart';
import 'package:photoe_zi/features/tether_view/presentation/tether_workspace_controller.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/exif_metadata_panel.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/filmstrip_bar.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/main_photo_canvas.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/rgb_histogram_widget.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/right_inspector_panel.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/top_workspace_bar.dart';

class TetherWorkspaceScreen extends ConsumerStatefulWidget {
  const TetherWorkspaceScreen({super.key});

  @override
  ConsumerState<TetherWorkspaceScreen> createState() =>
      _TetherWorkspaceScreenState();
}

class _TetherWorkspaceScreenState
    extends ConsumerState<TetherWorkspaceScreen> {
  int _selectedPortraitTab = 0; // 0: Film Sim, 1: Histogram/EXIF, 2: Drive Sync

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(tetherControllerProvider);
    final controller = ref.read(tetherControllerProvider.notifier);
    final photosAsync = ref.watch(sessionPhotosStreamProvider);
    final uploadQueueAsync = ref.watch(uploadQueueStreamProvider);

    final allPhotos = photosAsync.valueOrNull ?? const <Photo>[];
    final uploadList =
        uploadQueueAsync.valueOrNull ?? const <UploadQueueData>[];

    final uploadStatusMap = <String, String>{};
    for (final item in uploadList) {
      uploadStatusMap[item.photoId] = item.status;
    }

    Photo? activePhoto;
    if (allPhotos.isNotEmpty) {
      if (sessionState.selectedPhotoId != null) {
        for (final p in allPhotos) {
          if (p.id == sessionState.selectedPhotoId) {
            activePhoto = p;
            break;
          }
        }
      }
      activePhoto ??= allPhotos.last;
    }

    final latestPhoto = allPhotos.isNotEmpty ? allPhotos.last : null;
    final isViewingOlderPhoto = activePhoto != null &&
        latestPhoto != null &&
        activePhoto.id != latestPhoto.id;

    final histogramAsync =
        ref.watch(activePhotoHistogramProvider(activePhoto?.id));
    final histogramData =
        histogramAsync.valueOrNull ?? RgbHistogramData.empty();

    final syncedCount =
        allPhotos.where((p) => uploadStatusMap[p.id] == 'completed').length;
    final failedCount =
        allPhotos.where((p) => uploadStatusMap[p.id] == 'failed').length;
    final queuedCount = allPhotos
        .where((p) =>
            uploadStatusMap[p.id] == 'pending' ||
            uploadStatusMap[p.id] == 'bakingLut' ||
            uploadStatusMap[p.id] == 'uploading')
        .length;

    return Scaffold(
      backgroundColor: StudioColors.canvasBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscapeOrTablet = constraints.maxWidth >= 700 ||
                constraints.maxWidth > constraints.maxHeight;

            return Column(
              children: [
                // Top Bar (48px)
                TopWorkspaceBar(
                  sessionName: sessionState.activeSessionName,
                  cameraState: sessionState.cameraState,
                  cameraDriverName: sessionState.cameraDriverName,
                  isZenMode: sessionState.isZenMode,
                  isBeforeAfterActive: sessionState.isBeforeAfterPressed,
                  isRightInspectorVisible:
                      sessionState.isRightInspectorVisible,
                  isLandscapeOrTablet: isLandscapeOrTablet,
                  syncedCount: syncedCount,
                  totalCount: allPhotos.length,
                  onToggleCamera: controller.toggleCameraConnection,
                  onManualMockCapture: controller.triggerManualMockCapture,
                  onToggleZenMode: controller.toggleZenMode,
                  onToggleBeforeAfter: () => controller.setBeforeAfterPressed(
                    !sessionState.isBeforeAfterPressed,
                  ),
                  onToggleRightInspector: controller.toggleRightInspector,
                  onShowSessionDialog: () =>
                      _showNewSessionDialog(context, controller),
                  onOpenDriveSettings: () => _showGoogleDriveSettingsDialog(
                    context,
                    controller,
                    sessionState,
                  ),
                  onShowQrModal: () async {
                    final shareUrl =
                        await controller.prepareShareableSessionLink();
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (_) => QrShareSessionModal(
                        sessionName: sessionState.activeSessionName,
                        sessionFolderPath: sessionState.sessionFolderPath,
                        shareableUrl: shareUrl,
                        onEditDriveLink: () => _showGoogleDriveSettingsDialog(
                          context,
                          controller,
                          sessionState,
                        ),
                      ),
                    );
                  },
                ),

                // Main Content Area
                Expanded(
                  child: isLandscapeOrTablet
                      ? _buildLandscapeProLayout(
                          sessionState: sessionState,
                          controller: controller,
                          allPhotos: allPhotos,
                          activePhoto: activePhoto,
                          latestPhoto: latestPhoto,
                          isViewingOlderPhoto: isViewingOlderPhoto,
                          uploadStatusMap: uploadStatusMap,
                          histogramData: histogramData,
                          isHistogramLoading: histogramAsync.isLoading,
                          syncedCount: syncedCount,
                          queuedCount: queuedCount,
                          failedCount: failedCount,
                        )
                      : _buildPortraitResponsiveLayout(
                          sessionState: sessionState,
                          controller: controller,
                          allPhotos: allPhotos,
                          activePhoto: activePhoto,
                          latestPhoto: latestPhoto,
                          isViewingOlderPhoto: isViewingOlderPhoto,
                          uploadStatusMap: uploadStatusMap,
                          histogramData: histogramData,
                          isHistogramLoading: histogramAsync.isLoading,
                          syncedCount: syncedCount,
                          queuedCount: queuedCount,
                          failedCount: failedCount,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Desktop / Tablet Landscape Layout (Primary Pro Workspace)
  Widget _buildLandscapeProLayout({
    required TetherSessionState sessionState,
    required TetherWorkspaceController controller,
    required List<Photo> allPhotos,
    required Photo? activePhoto,
    required Photo? latestPhoto,
    required bool isViewingOlderPhoto,
    required Map<String, String> uploadStatusMap,
    required RgbHistogramData histogramData,
    required bool isHistogramLoading,
    required int syncedCount,
    required int queuedCount,
    required int failedCount,
  }) {
    final activeSyncStatus = activePhoto != null
        ? (uploadStatusMap[activePhoto.id] ?? 'pending')
        : 'completed';

    return Row(
      children: [
        // Optional Vertical Filmstrip on Left
        if (sessionState.isVerticalLeftFilmstrip)
          FilmstripBar(
            allPhotos: allPhotos,
            inMemoryPreviews: sessionState.inMemoryPreviews,
            uploadStatusByPhotoId: uploadStatusMap,
            selectedPhotoId: activePhoto?.id,
            activeFilter: sessionState.filter,
            lockLatest: sessionState.lockLatest,
            isVertical: true,
            onFilterChanged: controller.setFilter,
            onToggleLockLatest: () =>
                controller.toggleLockLatest(latestPhoto?.id),
            onToggleOrientation: controller.toggleFilmstripOrientation,
            onSelectPhoto: (photoId, isLatest) =>
                controller.selectPhoto(photoId, isLatestPhoto: isLatest),
          ),

        // Main Photo Canvas + Bottom Filmstrip (~75% dominant workspace)
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: MainPhotoCanvas(
                  activePhoto: activePhoto,
                  inMemoryPreview: activePhoto != null
                      ? sessionState.inMemoryPreviews[activePhoto.id]
                      : null,
                  activeLutId: sessionState.activeLutId,
                  activeLutData: sessionState.activeLutData,
                  activeLutTexture: sessionState.activeLutTexture,
                  lutIntensity: sessionState.lutIntensity,
                  isBeforeAfterPressed: sessionState.isBeforeAfterPressed,
                  lockLatest: sessionState.lockLatest,
                  isViewingOlderPhoto: isViewingOlderPhoto,
                  isZenMode: sessionState.isZenMode,
                  onToggleFavorite: () {
                    if (activePhoto != null) {
                      controller.toggleFavorite(activePhoto);
                    }
                  },
                  onToggleReject: () {
                    if (activePhoto != null) {
                      controller.toggleRejected(activePhoto);
                    }
                  },
                  onJumpToLatest: () {
                    if (latestPhoto != null) {
                      controller.jumpToLatest(latestPhoto.id);
                    }
                  },
                  onBeforeAfterChanged: controller.setBeforeAfterPressed,
                  onConnectMockCamera: controller.toggleCameraConnection,
                ),
              ),
              if (!sessionState.isVerticalLeftFilmstrip)
                FilmstripBar(
                  allPhotos: allPhotos,
                  inMemoryPreviews: sessionState.inMemoryPreviews,
                  uploadStatusByPhotoId: uploadStatusMap,
                  selectedPhotoId: activePhoto?.id,
                  activeFilter: sessionState.filter,
                  lockLatest: sessionState.lockLatest,
                  height: sessionState.isZenMode ? 84 : 105,
                  onFilterChanged: controller.setFilter,
                  onToggleLockLatest: () =>
                      controller.toggleLockLatest(latestPhoto?.id),
                  onToggleOrientation: controller.toggleFilmstripOrientation,
                  onSelectPhoto: (photoId, isLatest) =>
                      controller.selectPhoto(photoId, isLatestPhoto: isLatest),
                ),
            ],
          ),
        ),

        // Collapsible Right Inspector (~280px), hidden in Zen mode
        if (!sessionState.isZenMode && sessionState.isRightInspectorVisible)
          RightInspectorPanel(
            key: const Key('right_inspector_panel'),
            activePhoto: activePhoto,
            histogramData: histogramData,
            isHistogramLoading: isHistogramLoading,
            presets: sessionState.availablePresets,
            activeLutId: sessionState.activeLutId,
            lutIntensity: sessionState.lutIntensity,
            syncStatus: activeSyncStatus,
            isGoogleSignedIn: sessionState.isGoogleSignedIn,
            googleUserEmail: sessionState.googleUserEmail,
            sessionFolderPath: sessionState.sessionFolderPath,
            shareableFolderUrl: sessionState.shareableFolderUrl,
            autoUploadMode: sessionState.autoUploadMode,
            uploadVariant: sessionState.uploadVariant,
            isOffline: sessionState.isOffline,
            syncedCount: syncedCount,
            queuedCount: queuedCount,
            failedCount: failedCount,
            onSelectLut: controller.setActiveLut,
            onIntensityChanged: controller.setLutIntensity,
            onImportCube: () => _showImportCubeDialog(context, controller),
            onManualUpload: () {
              if (activePhoto != null) {
                controller.enqueuePhotoForUpload(activePhoto.id);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Queued for Google Drive Upload'),
                ),
              );
            },
            onOpenDriveSettings: () => _showGoogleDriveSettingsDialog(
              context,
              controller,
              sessionState,
            ),
            onAutoUploadModeChanged: controller.setAutoUploadMode,
            onUploadVariantChanged: controller.setUploadVariant,
            onToggleOffline: controller.setOfflineMode,
            onRetryFailed: controller.retryFailedUploads,
            onShowQrModal: () async {
              final shareUrl = await controller.prepareShareableSessionLink();
              if (!mounted) return;
              await showDialog<void>(
                context: context,
                builder: (_) => QrShareSessionModal(
                  sessionName: sessionState.activeSessionName,
                  sessionFolderPath: sessionState.sessionFolderPath,
                  shareableUrl: shareUrl,
                  onEditDriveLink: () => _showGoogleDriveSettingsDialog(
                    context,
                    controller,
                    sessionState,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// Smartphone Portrait Layout (Responsive Fallback with Draggable Bottom Sheet Inspector)
  Widget _buildPortraitResponsiveLayout({
    required TetherSessionState sessionState,
    required TetherWorkspaceController controller,
    required List<Photo> allPhotos,
    required Photo? activePhoto,
    required Photo? latestPhoto,
    required bool isViewingOlderPhoto,
    required Map<String, String> uploadStatusMap,
    required RgbHistogramData histogramData,
    required bool isHistogramLoading,
    required int syncedCount,
    required int queuedCount,
    required int failedCount,
  }) {
    final activeSyncStatus = activePhoto != null
        ? (uploadStatusMap[activePhoto.id] ?? 'pending')
        : 'completed';

    return Stack(
      children: [
        Column(
          children: [
            // Main Photo Canvas (~65% height)
            Expanded(
              child: MainPhotoCanvas(
                activePhoto: activePhoto,
                inMemoryPreview: activePhoto != null
                    ? sessionState.inMemoryPreviews[activePhoto.id]
                    : null,
                activeLutId: sessionState.activeLutId,
                activeLutData: sessionState.activeLutData,
                activeLutTexture: sessionState.activeLutTexture,
                lutIntensity: sessionState.lutIntensity,
                isBeforeAfterPressed: sessionState.isBeforeAfterPressed,
                lockLatest: sessionState.lockLatest,
                isViewingOlderPhoto: isViewingOlderPhoto,
                isZenMode: sessionState.isZenMode,
                onToggleFavorite: () {
                  if (activePhoto != null) {
                    controller.toggleFavorite(activePhoto);
                  }
                },
                onToggleReject: () {
                  if (activePhoto != null) {
                    controller.toggleRejected(activePhoto);
                  }
                },
                onJumpToLatest: () {
                  if (latestPhoto != null) {
                    controller.jumpToLatest(latestPhoto.id);
                  }
                },
                onBeforeAfterChanged: controller.setBeforeAfterPressed,
                onConnectMockCamera: controller.toggleCameraConnection,
              ),
            ),

            // Bottom Filmstrip (Height ~85px in Portrait)
            FilmstripBar(
              allPhotos: allPhotos,
              inMemoryPreviews: sessionState.inMemoryPreviews,
              uploadStatusByPhotoId: uploadStatusMap,
              selectedPhotoId: activePhoto?.id,
              activeFilter: sessionState.filter,
              lockLatest: sessionState.lockLatest,
              height: 85,
              onFilterChanged: controller.setFilter,
              onToggleLockLatest: () =>
                  controller.toggleLockLatest(latestPhoto?.id),
              onToggleOrientation: controller.toggleFilmstripOrientation,
              onSelectPhoto: (photoId, isLatest) =>
                  controller.selectPhoto(photoId, isLatestPhoto: isLatest),
            ),

            // Space reserved for collapsed DraggableScrollableSheet trigger tabs
            if (!sessionState.isZenMode) const SizedBox(height: 44),
          ],
        ),

        // Draggable Bottom Sheet Inspector (Hidden in Zen Mode)
        if (!sessionState.isZenMode)
          DraggableScrollableSheet(
            key: const Key('portrait_inspector_bottom_sheet'),
            initialChildSize: 0.10,
            minChildSize: 0.08,
            maxChildSize: 0.62,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: StudioColors.panelSurface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(
                    top: BorderSide(color: StudioColors.panelBorder, width: 1),
                  ),
                ),
                child: ListView(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: StudioColors.panelBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Trigger Tabs: [Film Sim], [Histogram/EXIF], [Drive Sync]
                    Row(
                      children: [
                        Expanded(
                          child: _portraitTabButton(
                            index: 0,
                            label: 'Film Sim',
                            icon: Icons.filter_b_and_w_rounded,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _portraitTabButton(
                            index: 1,
                            label: 'Histogram/EXIF',
                            icon: Icons.bar_chart_rounded,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _portraitTabButton(
                            index: 2,
                            label: 'Drive Sync',
                            icon: Icons.cloud_sync_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_selectedPortraitTab == 0) ...[
                      ...sessionState.availablePresets.map((preset) {
                        final isSelected =
                            preset.id == sessionState.activeLutId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: InkWell(
                            onTap: () => controller.setActiveLut(preset.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? StudioColors.accentAmber
                                        .withValues(alpha: 0.16)
                                    : StudioColors.panelElevated,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected
                                      ? StudioColors.accentAmber
                                      : StudioColors.panelBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    preset.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? StudioColors.accentAmber
                                          : StudioColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    preset.category,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: StudioColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      Slider(
                        value: sessionState.lutIntensity,
                        onChanged: controller.setLutIntensity,
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showImportCubeDialog(context, controller),
                          icon: const Icon(Icons.add_rounded, size: 14),
                          label: const Text('Import .cube'),
                        ),
                      ),
                    ] else if (_selectedPortraitTab == 1) ...[
                      RgbHistogramWidget(
                        data: histogramData,
                        isLoading: isHistogramLoading,
                      ),
                      const SizedBox(height: 10),
                      ExifMetadataPanel(
                        photo: activePhoto,
                        syncStatus: activeSyncStatus,
                      ),
                    ] else ...[
                      DriveSyncInspectorPanel(
                        isSignedIn: sessionState.isGoogleSignedIn,
                        userEmail: sessionState.googleUserEmail,
                        sessionFolderPath: sessionState.sessionFolderPath,
                        shareableFolderUrl: sessionState.shareableFolderUrl,
                        autoUploadMode: sessionState.autoUploadMode,
                        uploadVariant: sessionState.uploadVariant,
                        isOffline: sessionState.isOffline,
                        syncedCount: syncedCount,
                        queuedCount: queuedCount,
                        failedCount: failedCount,
                        onOpenDriveSettings: () =>
                            _showGoogleDriveSettingsDialog(
                          context,
                          controller,
                          sessionState,
                        ),
                        onAutoUploadModeChanged: controller.setAutoUploadMode,
                        onUploadVariantChanged: controller.setUploadVariant,
                        onToggleOffline: controller.setOfflineMode,
                        onRetryFailed: controller.retryFailedUploads,
                        onShowQrModal: () async {
                          final shareUrl =
                              await controller.prepareShareableSessionLink();
                          if (!context.mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (_) => QrShareSessionModal(
                              sessionName: sessionState.activeSessionName,
                              sessionFolderPath:
                                  sessionState.sessionFolderPath,
                              shareableUrl: shareUrl,
                              onEditDriveLink: () =>
                                  _showGoogleDriveSettingsDialog(
                                context,
                                controller,
                                sessionState,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _portraitTabButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedPortraitTab == index;
    return InkWell(
      key: Key('portrait_tab_$index'),
      onTap: () {
        setState(() {
          _selectedPortraitTab = index;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? StudioColors.accentAmber.withValues(alpha: 0.16)
              : StudioColors.panelElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color:
                isSelected ? StudioColors.accentAmber : StudioColors.panelBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? StudioColors.accentAmber
                  : StudioColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? StudioColors.accentAmber
                      : StudioColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportCubeDialog(
    BuildContext context,
    TetherWorkspaceController controller,
  ) async {
    final pathController = TextEditingController();
    final nameController = TextEditingController(text: 'Portra 400 Warm');
    String? errorMessage;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: StudioColors.panelSurface,
            title: const Row(
              children: [
                Icon(
                  Icons.filter_b_and_w_rounded,
                  size: 18,
                  color: StudioColors.accentAmber,
                ),
                SizedBox(width: 8),
                Text(
                  'Import .cube 3D LUT',
                  style: TextStyle(
                    color: StudioColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Option 1: Native File Picker
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('btn_dialog_browse_cube'),
                      onPressed: () async {
                        try {
                          final imported =
                              await controller.pickAndImportCustomCubeFile();
                          if (imported != null && ctx.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Imported & activated LUT: ${imported.name}',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            errorMessage =
                                'Native file picker requires cold restart or use Path / Quick Preset below ($e)';
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StudioColors.accentAmber,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('Browse .cube File from Device'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: StudioColors.panelBorder),
                  ),
                  // Option 2: Direct file path input
                  const Text(
                    'Or Load from Local File Path:',
                    style: TextStyle(
                      color: StudioColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('input_cube_file_path'),
                          controller: pathController,
                          style: const TextStyle(
                            color: StudioColors.textPrimary,
                            fontSize: 12,
                            fontFamily: StudioTheme.monospaceFont,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '/path/to/my_lut.cube',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const Key('btn_load_cube_path'),
                        onPressed: () async {
                          final rawPath = pathController.text.trim();
                          if (rawPath.isEmpty) {
                            setDialogState(() {
                              errorMessage = 'Please enter a .cube file path';
                            });
                            return;
                          }
                          final file = File(rawPath);
                          if (!await file.exists()) {
                            setDialogState(() {
                              errorMessage = 'File not found: $rawPath';
                            });
                            return;
                          }
                          try {
                            final imported =
                                await controller.importCustomCubeFromFile(file);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Imported & activated LUT: ${imported.name}',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              errorMessage = 'Invalid .cube file: $e';
                            });
                          }
                        },
                        child: const Text('Load'),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: StudioColors.panelBorder),
                  ),
                  // Option 3: Quick Custom .cube Generator for Instant Studio Testing
                  const Text(
                    'Quick Generate Custom .cube Preset:',
                    style: TextStyle(
                      color: StudioColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('input_custom_lut_name'),
                          controller: nameController,
                          style: const TextStyle(
                            color: StudioColors.textPrimary,
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Custom Preset Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const Key('btn_generate_custom_cube'),
                        onPressed: () async {
                          final presetName = nameController.text.trim().isEmpty
                              ? 'Portra 400 Warm'
                              : nameController.text.trim();
                          final cubeStr =
                              _generatePortraCustomCubeString(presetName);
                          final imported = await controller
                              .importCustomCubeFromString(
                            cubeStr,
                            presetName: presetName,
                          );
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Created & activated custom .cube: ${imported.name}',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                        label: const Text('Add .cube'),
                      ),
                    ],
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: StudioColors.statusError,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _generatePortraCustomCubeString(String title) {
    const int size = 17;
    final buf = StringBuffer()
      ..writeln('TITLE "$title"')
      ..writeln('LUT_3D_SIZE $size')
      ..writeln('DOMAIN_MIN 0.0 0.0 0.0')
      ..writeln('DOMAIN_MAX 1.0 1.0 1.0');
    for (int b = 0; b < size; b++) {
      final bf = b / (size - 1);
      for (int g = 0; g < size; g++) {
        final gf = g / (size - 1);
        for (int r = 0; r < size; r++) {
          final rf = r / (size - 1);
          // Warm golden Portra skin tones + lifted teal shadows
          final ro = (0.04 + rf * 0.94 + 0.04 * (1.0 - bf)).clamp(0.0, 1.0);
          final go = (0.03 + gf * 0.93 + 0.02 * rf).clamp(0.0, 1.0);
          final bo = (0.05 + bf * 0.86).clamp(0.0, 1.0);
          buf.writeln(
            '${ro.toStringAsFixed(5)} ${go.toStringAsFixed(5)} ${bo.toStringAsFixed(5)}',
          );
        }
      }
    }
    return buf.toString();
  }

  Future<void> _showNewSessionDialog(
    BuildContext context,
    TetherWorkspaceController controller,
  ) async {
    final textController = TextEditingController(text: 'Studio_B');
    final driveLinkController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panelSurface,
        title: const Text(
          'New Shooting Session',
          style: TextStyle(color: StudioColors.textPrimary, fontSize: 15),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_new_session_name'),
                controller: textController,
                style: const TextStyle(color: StudioColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Session Name',
                  hintText: 'e.g. Studio_A',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('input_new_session_drive_link'),
                controller: driveLinkController,
                style: const TextStyle(
                  color: StudioColors.textPrimary,
                  fontSize: 12,
                  fontFamily: StudioTheme.monospaceFont,
                ),
                decoration: const InputDecoration(
                  labelText: 'Google Drive Folder Link / ID (Optional)',
                  hintText:
                      'https://drive.google.com/drive/folders/... (leave blank to auto-create)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_create_session'),
            onPressed: () {
              controller.createNewSession(
                textController.text,
                customDriveLinkOrId: driveLinkController.text,
              );
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: StudioColors.accentAmber,
              foregroundColor: Colors.black,
            ),
            child: const Text('Create Session'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGoogleDriveSettingsDialog(
    BuildContext context,
    TetherWorkspaceController controller,
    TetherSessionState sessionState,
  ) async {
    final emailController = TextEditingController(
      text: sessionState.googleUserEmail ?? 'photographer@gmail.com',
    );
    final linkController = TextEditingController(
      text: sessionState.shareableFolderUrl,
    );
    bool setAsDefaultParent = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: StudioColors.panelSurface,
            title: const Row(
              children: [
                Icon(
                  Icons.add_to_drive_rounded,
                  color: StudioColors.accentAmber,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Google Drive Cloud Sync & Folder Link',
                  style: TextStyle(
                    color: StudioColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Google Account OAuth 2.0 Sign-In / Sign-Out (Issue #3.1)
                  const Text(
                    'GOOGLE ACCOUNT (OAuth 2.0 · scope: drive.file)',
                    style: TextStyle(
                      color: StudioColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('input_google_email'),
                          controller: emailController,
                          style: const TextStyle(
                            color: StudioColors.textPrimary,
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Google Account Email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (sessionState.isGoogleSignedIn)
                        OutlinedButton(
                          key: const Key('btn_google_sign_out'),
                          onPressed: () async {
                            await controller.signOutGoogleAccount();
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                          },
                          child: const Text('Sign Out'),
                        )
                      else
                        ElevatedButton(
                          key: const Key('btn_google_sign_in'),
                          onPressed: () async {
                            await controller
                                .signInGoogleAccount(emailController.text);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StudioColors.accentAmber,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Sign In'),
                        ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: StudioColors.panelBorder),
                  ),

                  // Register / Set Custom Google Drive Folder Link or ID
                  const Text(
                    'REGISTER GOOGLE DRIVE FOLDER LINK / FOLDER ID',
                    style: TextStyle(
                      color: StudioColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('input_gdrive_folder_link'),
                    controller: linkController,
                    style: const TextStyle(
                      color: StudioColors.textPrimary,
                      fontSize: 12,
                      fontFamily: StudioTheme.monospaceFont,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Google Drive Folder URL or Folder ID',
                      hintText:
                          'https://drive.google.com/drive/folders/1AbCdEfGhIjK...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: setAsDefaultParent,
                    activeColor: StudioColors.accentAmber,
                    title: const Text(
                      'Also use as custom parent folder for future sessions',
                      style: TextStyle(
                        color: StudioColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        setAsDefaultParent = val ?? false;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                key: const Key('btn_save_gdrive_link'),
                onPressed: () async {
                  if (!sessionState.isGoogleSignedIn) {
                    await controller.signInGoogleAccount(emailController.text);
                  }
                  await controller.registerCustomDriveFolderLink(
                    linkController.text,
                    setAsDefaultParent: setAsDefaultParent,
                  );
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Google Drive Folder Link saved & synced!'),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: StudioColors.accentAmber,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.save_outlined, size: 15),
                label: const Text('Save Drive Link'),
              ),
            ],
          );
        },
      ),
    );
  }
}

