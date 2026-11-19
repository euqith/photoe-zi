import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/cloud_sync/data/google_drive_cloud_sync_service.dart';
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
            lastUploadError: sessionState.googleAuthError,
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
                        lastUploadError: sessionState.googleAuthError,
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
          return Dialog(
            backgroundColor: StudioColors.panelSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: StudioColors.panelBorder),
            ),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              StudioColors.accentAmber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.filter_b_and_w_rounded,
                          size: 18,
                          color: StudioColors.accentAmber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Import .cube 3D LUT',
                              style: TextStyle(
                                color: StudioColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Supports 17x17x17 & 33x33x33 Adobe/IRIDAS .cube files',
                              style: TextStyle(
                                color: StudioColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: StudioColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Option 1: Native File Picker
                  SizedBox(
                    width: double.infinity,
                    height: 38,
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
                                'Use local file path or quick preset generator below ($e)';
                          });
                        }
                      },
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('Browse .cube File from Device'),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Option 2: Direct file path input card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StudioColors.panelElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StudioColors.panelBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('LOAD FROM LOCAL FILE PATH'),
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
                                  hintText: '/path/to/my_preset.cube',
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
                                    errorMessage =
                                        'Please enter a .cube file path';
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
                                  final imported = await controller
                                      .importCustomCubeFromFile(file);
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Quick Custom .cube Generator
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StudioColors.panelElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StudioColors.panelBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('QUICK GENERATE CUSTOM .CUBE PRESET'),
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
                                  hintText: 'e.g. Portra 400 Warm',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              key: const Key('btn_generate_custom_cube'),
                              onPressed: () async {
                                final presetName =
                                    nameController.text.trim().isEmpty
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
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: StudioColors.accentAmber,
                              ),
                              label: const Text('Add .cube'),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
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
      builder: (ctx) => Dialog(
        backgroundColor: StudioColors.panelSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: StudioColors.panelBorder),
        ),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: StudioColors.accentAmber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                      color: StudioColors.accentAmber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Shooting Session',
                          style: TextStyle(
                            color: StudioColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Creates a clean workspace & Google Drive session folder',
                          style: TextStyle(
                            color: StudioColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: StudioColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _fieldLabel('SESSION NAME'),
              const SizedBox(height: 6),
              TextField(
                key: const Key('input_new_session_name'),
                controller: textController,
                style: const TextStyle(
                  color: StudioColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  hintText: 'e.g. Studio_A or Editorial_Lookbook',
                ),
              ),
              const SizedBox(height: 14),
              _fieldLabel('GOOGLE DRIVE FOLDER LINK / ID (OPTIONAL)'),
              const SizedBox(height: 6),
              TextField(
                key: const Key('input_new_session_drive_link'),
                controller: driveLinkController,
                style: const TextStyle(
                  color: StudioColors.textPrimary,
                  fontSize: 12,
                  fontFamily: StudioTheme.monospaceFont,
                ),
                decoration: const InputDecoration(
                  hintText: 'Leave empty to auto-create TetherApp/YYYY-MM-DD',
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    key: const Key('btn_confirm_create_session'),
                    onPressed: () {
                      controller.createNewSession(
                        textController.text,
                        customDriveLinkOrId: driveLinkController.text,
                      );
                      Navigator.of(ctx).pop();
                    },
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Create Session'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showGoogleDriveSettingsDialog(
    BuildContext context,
    TetherWorkspaceController controller,
    TetherSessionState sessionState,
  ) async {
    final tokenController = TextEditingController();
    final clientIdController = TextEditingController();
    final clientSecretController = TextEditingController();
    final linkController = TextEditingController(
      text: sessionState.shareableFolderUrl,
    );
    final initialConfig = await controller.getOAuthConfig();
    if (!context.mounted) return;
    clientIdController.text = initialConfig.clientId;
    clientSecretController.text = initialConfig.clientSecret;
    bool showAdvancedConfig = !initialConfig.isConfigured;
    bool setAsDefaultParent = false;
    bool isAuthenticating = false;
    String? statusFeedback;
    bool isErrorFeedback = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentState = ref.read(tetherControllerProvider);
          final userEmail = currentState.googleUserEmail ?? '';
          final avatarLetter =
              userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'G';

          return Dialog(
            backgroundColor: StudioColors.panelSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: StudioColors.panelBorder),
            ),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Clean Studio Modal Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: StudioColors.accentAmber
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.add_to_drive_rounded,
                            color: StudioColors.accentAmber,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Google Drive Cloud Sync',
                                style: TextStyle(
                                  color: StudioColors.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Sign in with Google & choose your session folder',
                                style: TextStyle(
                                  color: StudioColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: StudioColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 2. Simple 1-Click Google Account Section
                    _fieldLabel('GOOGLE ACCOUNT'),
                    const SizedBox(height: 8),
                    if (currentState.isGoogleSignedIn)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: StudioColors.statusSuccess
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: StudioColors.statusSuccess
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: StudioColors.accentAmber,
                              child: Text(
                                avatarLetter,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userEmail,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: StudioColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentState.isGoogleDemoMode
                                        ? '✓ Connected via Browser Pop-Up'
                                        : '✓ Connected · Live Google Drive API v3',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: StudioColors.statusSuccess,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 30,
                              child: OutlinedButton(
                                key: const Key('btn_google_sign_out'),
                                onPressed: () async {
                                  await controller.signOutGoogleAccount();
                                  setDialogState(() {
                                    statusFeedback = null;
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                child: const Text(
                                  'Switch Account',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: StudioColors.panelElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: StudioColors.panelBorder),
                        ),
                        child: Column(
                          children: [
                            // 1-Click Standard "Sign in with Google" Button
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: ElevatedButton(
                                key: const Key('btn_launch_browser_oauth'),
                                onPressed: isAuthenticating
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          isAuthenticating = true;
                                          isErrorFeedback = false;
                                          statusFeedback =
                                              'Choose your Google account in the browser pop-up...';
                                        });
                                        final ok = await controller
                                            .signInGoogleWithBrowserOAuth(
                                          clientId: clientIdController.text,
                                          clientSecret:
                                              clientSecretController.text,
                                        );
                                        setDialogState(() {
                                          isAuthenticating = false;
                                          isErrorFeedback = !ok;
                                          statusFeedback = ok
                                              ? '✓ Signed in as ${ref.read(tetherControllerProvider).googleUserEmail}'
                                              : (ref
                                                      .read(
                                                          tetherControllerProvider)
                                                      .googleAuthError ??
                                                  'Sign-in cancelled');
                                        });
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF1F2937),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isAuthenticating)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF1A73E8),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A73E8)
                                              .withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Text(
                                          'G',
                                          style: TextStyle(
                                            color: Color(0xFF1A73E8),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 10),
                                    Text(
                                      isAuthenticating
                                          ? 'Waiting for Browser Sign-In...'
                                          : 'Sign in with Google',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Opens a browser pop-up to pick your existing Google Account',
                              style: TextStyle(
                                fontSize: 11,
                                color: StudioColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                    if (statusFeedback != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isErrorFeedback
                              ? StudioColors.statusError.withValues(alpha: 0.12)
                              : StudioColors.statusSuccess
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isErrorFeedback
                                ? StudioColors.statusError
                                    .withValues(alpha: 0.5)
                                : StudioColors.statusSuccess
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          statusFeedback!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isErrorFeedback
                                ? StudioColors.statusError
                                : StudioColors.statusSuccess,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // 3. Destination Folder Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: StudioColors.panelElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: StudioColors.panelBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('DESTINATION GOOGLE DRIVE FOLDER'),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('input_gdrive_folder_link'),
                            controller: linkController,
                            style: const TextStyle(
                              color: StudioColors.textPrimary,
                              fontSize: 12,
                              fontFamily: StudioTheme.monospaceFont,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'https://drive.google.com/drive/folders/...',
                              prefixIcon: const Icon(
                                Icons.folder_special_outlined,
                                size: 16,
                                color: StudioColors.accentAmber,
                              ),
                              suffixIcon: IconButton(
                                tooltip: 'Paste Folder Link',
                                onPressed: () async {
                                  final data = await Clipboard.getData(
                                    Clipboard.kTextPlain,
                                  );
                                  if (data?.text != null) {
                                    linkController.text = data!.text!.trim();
                                  }
                                },
                                icon: const Icon(
                                  Icons.content_paste_rounded,
                                  size: 15,
                                  color: StudioColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: () {
                              setDialogState(() {
                                setAsDefaultParent = !setAsDefaultParent;
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: setAsDefaultParent,
                                      activeColor: StudioColors.accentAmber,
                                      checkColor: Colors.black,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          setAsDefaultParent = val ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Use as default parent folder for future sessions',
                                      style: TextStyle(
                                        color: StudioColors.textSecondary,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 4. Collapsible Advanced Developer OAuth Config (Hidden by default)
                    InkWell(
                      onTap: () {
                        setDialogState(() {
                          showAdvancedConfig = !showAdvancedConfig;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              showAdvancedConfig
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_right_rounded,
                              size: 16,
                              color: StudioColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Advanced: Custom OAuth Token / GCP Client ID',
                              style: TextStyle(
                                fontSize: 11,
                                color: StudioColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showAdvancedConfig) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: StudioColors.inputSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: StudioColors.panelBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PhotoE-Zi Google OAuth 2.0 Credentials (Google Cloud)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: StudioColors.accentAmber,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Enter your personal GCP Desktop Client ID so Google displays "PhotoE-Zi" during login and guarantees full upload quota.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: StudioColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('input_google_client_id'),
                              controller: clientIdController,
                              style: const TextStyle(
                                color: StudioColors.textPrimary,
                                fontSize: 11.5,
                                fontFamily: StudioTheme.monospaceFont,
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    'GCP Client ID (e.g. 12345...apps.googleusercontent.com)',
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('input_google_client_secret'),
                              controller: clientSecretController,
                              style: const TextStyle(
                                color: StudioColors.textPrimary,
                                fontSize: 11.5,
                                fontFamily: StudioTheme.monospaceFont,
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    'Client Secret (Optional for Desktop PKCE)',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: StudioColors.panelElevated,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                  icon: const Icon(Icons.save_rounded, size: 13),
                                  label: const Text(
                                    'Save PhotoE-Zi Credentials',
                                    style: TextStyle(fontSize: 10.5),
                                  ),
                                  onPressed: () async {
                                    await controller.saveOAuthConfig(
                                      clientId: clientIdController.text.trim(),
                                      clientSecret:
                                          clientSecretController.text.trim(),
                                    );
                                    setDialogState(() {
                                      isErrorFeedback = false;
                                      statusFeedback =
                                          '✓ PhotoE-Zi OAuth credentials saved!';
                                    });
                                  },
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: () {
                                    GoogleDriveCloudSyncService.openSystemUrl(
                                      'https://console.cloud.google.com/apis/credentials',
                                    );
                                  },
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.open_in_new_rounded,
                                        size: 12,
                                        color: StudioColors.accentAmber,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Open GCP Console',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: StudioColors.accentAmber,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Option B: Direct OAuth 2.0 Access Token',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: StudioColors.accentAmber,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const Key('input_google_access_token'),
                                    controller: tokenController,
                                    style: const TextStyle(
                                      color: StudioColors.textPrimary,
                                      fontSize: 11.5,
                                      fontFamily: StudioTheme.monospaceFont,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Access Token (ya29.a0...)',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: StudioColors.panelElevated,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () async {
                                    if (tokenController.text.trim().isEmpty) {
                                      setDialogState(() {
                                        isErrorFeedback = true;
                                        statusFeedback =
                                            'Please paste an OAuth Access Token first.';
                                      });
                                      return;
                                    }
                                    setDialogState(() {
                                      isAuthenticating = true;
                                    });
                                    final ok = await controller
                                        .signInGoogleWithAccessToken(
                                      accessToken: tokenController.text,
                                    );
                                    setDialogState(() {
                                      isAuthenticating = false;
                                      if (ok) {
                                        isErrorFeedback = false;
                                        statusFeedback =
                                            'Successfully connected as ${ref.read(tetherControllerProvider).googleUserEmail ?? 'Google Account'}!';
                                      } else {
                                        isErrorFeedback = true;
                                        statusFeedback = ref
                                                .read(tetherControllerProvider)
                                                .googleAuthError ??
                                            'Token verification failed';
                                      }
                                    });
                                  },
                                  child: const Text(
                                    'Apply',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                GoogleDriveCloudSyncService.openSystemUrl(
                                  'https://developers.google.com/oauthplayground',
                                );
                              },
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: 13,
                                    color: StudioColors.accentAmber,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Get token from Google OAuth 2.0 Playground',
                                    style: TextStyle(
                                      color: StudioColors.accentAmber,
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // 5. Footer Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          key: const Key('btn_save_gdrive_link'),
                          onPressed: () async {
                            if (clientIdController.text.trim().isNotEmpty) {
                              await controller.saveOAuthConfig(
                                clientId: clientIdController.text.trim(),
                                clientSecret: clientSecretController.text.trim(),
                              );
                            }

                            if (tokenController.text.trim().isNotEmpty) {
                              final ok =
                                  await controller.signInGoogleWithAccessToken(
                                accessToken: tokenController.text,
                              );
                              if (!ok) {
                                setDialogState(() {
                                  isErrorFeedback = true;
                                  statusFeedback = ref
                                          .read(tetherControllerProvider)
                                          .googleAuthError ??
                                      'Invalid OAuth 2.0 Access Token';
                                });
                                return;
                              }
                            }

                            await controller.registerCustomDriveFolderLink(
                              linkController.text,
                              setAsDefaultParent: setAsDefaultParent,
                            );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Google Drive settings saved & ready for sync!',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Save & Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: StudioColors.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
      ),
    );
  }
}

