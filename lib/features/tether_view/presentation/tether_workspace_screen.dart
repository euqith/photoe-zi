import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/film_sim/domain/lut_preset.dart';
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
                  onToggleZenMode: controller.toggleZenMode,
                  onToggleBeforeAfter: () => controller.setBeforeAfterPressed(
                    !sessionState.isBeforeAfterPressed,
                  ),
                  onToggleRightInspector: controller.toggleRightInspector,
                  onShowSessionDialog: () =>
                      _showNewSessionDialog(context, controller),
                  onShowQrModal: () => _showQrPreviewDialog(
                    context,
                    sessionState.activeSessionName,
                  ),
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
  }) {
    final activeSyncStatus = activePhoto != null
        ? (uploadStatusMap[activePhoto.id] ?? 'completed')
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
            activeLutId: sessionState.activeLutId,
            lutIntensity: sessionState.lutIntensity,
            syncStatus: activeSyncStatus,
            onSelectLut: controller.setActiveLut,
            onIntensityChanged: controller.setLutIntensity,
            onImportCube: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Custom .cube LUT import ready (Sprint 2 GPU Engine)',
                  ),
                ),
              );
            },
            onManualUpload: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Queued for Google Drive Upload'),
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
  }) {
    final activeSyncStatus = activePhoto != null
        ? (uploadStatusMap[activePhoto.id] ?? 'completed')
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
                      ...LutPreset.builtInPresets.map((preset) {
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
                      ExifMetadataPanel(
                        photo: activePhoto,
                        syncStatus: activeSyncStatus,
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

  Future<void> _showNewSessionDialog(
    BuildContext context,
    TetherWorkspaceController controller,
  ) async {
    final textController = TextEditingController(text: 'Studio_B');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panelSurface,
        title: const Text(
          'New Shooting Session',
          style: TextStyle(color: StudioColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: StudioColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Session Name',
            hintText: 'e.g. Studio_A',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.createNewSession(textController.text);
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

  Future<void> _showQrPreviewDialog(
    BuildContext context,
    String sessionName,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panelSurface,
        title: Text(
          'Share Session: $sessionName',
          style: const TextStyle(color: StudioColors.textPrimary, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 160,
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 132,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'TetherApp / 2026-11-19_$sessionName',
              style: const TextStyle(
                color: StudioColors.textSecondary,
                fontSize: 11,
                fontFamily: StudioTheme.monospaceFont,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
