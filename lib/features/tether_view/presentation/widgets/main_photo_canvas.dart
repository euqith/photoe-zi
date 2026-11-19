import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';

class MainPhotoCanvas extends StatefulWidget {
  final Photo? activePhoto;
  final Uint8List? inMemoryPreview;
  final String activeLutId;
  final double lutIntensity;
  final bool isBeforeAfterPressed;
  final bool lockLatest;
  final bool isViewingOlderPhoto;
  final bool isZenMode;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleReject;
  final VoidCallback onJumpToLatest;
  final ValueChanged<bool> onBeforeAfterChanged;
  final VoidCallback onConnectMockCamera;

  const MainPhotoCanvas({
    super.key,
    required this.activePhoto,
    required this.inMemoryPreview,
    required this.activeLutId,
    required this.lutIntensity,
    required this.isBeforeAfterPressed,
    required this.lockLatest,
    required this.isViewingOlderPhoto,
    required this.isZenMode,
    required this.onToggleFavorite,
    required this.onToggleReject,
    required this.onJumpToLatest,
    required this.onBeforeAfterChanged,
    required this.onConnectMockCamera,
  });

  @override
  State<MainPhotoCanvas> createState() => _MainPhotoCanvasState();
}

class _MainPhotoCanvasState extends State<MainPhotoCanvas> {
  final TransformationController _transformController =
      TransformationController();
  bool _showBottomOverlay = true;
  double _currentZoom = 1.0;

  @override
  void didUpdateWidget(covariant MainPhotoCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activePhoto?.id != widget.activePhoto?.id) {
      _resetZoom();
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
    setState(() {
      _currentZoom = 1.0;
    });
  }

  void _handleDoubleTap() {
    if (_currentZoom > 1.05) {
      _resetZoom();
    } else {
      _transformController.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
      setState(() {
        _currentZoom = 2.5;
      });
    }
  }

  ColorFilter? _buildPreviewLutFilter() {
    if (widget.isBeforeAfterPressed ||
        widget.activeLutId == 'none' ||
        widget.lutIntensity <= 0.01) {
      return null;
    }

    final t = widget.lutIntensity;
    switch (widget.activeLutId) {
      case 'classic_chrome':
        return ColorFilter.matrix([
          1 - 0.1 * t, 0.08 * t, 0.02 * t, 0, 0,
          0.04 * t, 1 - 0.04 * t, 0.02 * t, 0, 0,
          0.02 * t, 0.06 * t, 1 - 0.14 * t, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'classic_neg':
        return ColorFilter.matrix([
          1 + 0.12 * t, -0.04 * t, -0.04 * t, 0, 0,
          -0.02 * t, 1 - 0.02 * t, 0.04 * t, 0, 0,
          0.05 * t, -0.05 * t, 1 + 0.05 * t, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'kodachrome':
        return ColorFilter.matrix([
          1 + 0.15 * t, 0.04 * t, -0.05 * t, 0, 0,
          0.02 * t, 1 + 0.03 * t, -0.02 * t, 0, 0,
          -0.04 * t, 0.02 * t, 1 - 0.08 * t, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'japanese_airy':
        return ColorFilter.matrix([
          1 + 0.06 * t, 0.04 * t, 0.04 * t, 0, 14 * t,
          0.03 * t, 1 + 0.08 * t, 0.05 * t, 0, 16 * t,
          0.04 * t, 0.06 * t, 1 + 0.10 * t, 0, 18 * t,
          0, 0, 0, 1, 0,
        ]);
      case 'bw_acros':
        final r = 0.299 * t;
        final g = 0.587 * t;
        final b = 0.114 * t;
        return ColorFilter.matrix([
          (1 - t) + r, g, b, 0, 0,
          r, (1 - t) + g, b, 0, 0,
          r, g, (1 - t) + b, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      default:
        return null;
    }
  }

  Widget _buildImageContent(Photo photo) {
    Widget rawImage;
    final fullPath = photo.fullResPath;
    if (fullPath != null && File(fullPath).existsSync()) {
      rawImage = Image.file(
        File(fullPath),
        key: ValueKey('full_${photo.id}'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else if (widget.inMemoryPreview != null) {
      rawImage = Image.memory(
        widget.inMemoryPreview!,
        key: ValueKey('mem_${photo.id}'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else if (photo.previewPath != null &&
        File(photo.previewPath!).existsSync()) {
      rawImage = Image.file(
        File(photo.previewPath!),
        key: ValueKey('prev_${photo.id}'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else {
      rawImage = const Center(
        child: Icon(
          Icons.image_outlined,
          size: 64,
          color: StudioColors.textMuted,
        ),
      );
    }

    final filter = _buildPreviewLutFilter();
    if (filter != null) {
      return ColorFiltered(
        colorFilter: filter,
        child: rawImage,
      );
    }
    return rawImage;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.activePhoto;
    if (photo == null) {
      return Container(
        color: StudioColors.canvasBackground,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.camera_enhance_outlined,
              size: 48,
              color: StudioColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Waiting for Tethered Capture...',
              style: TextStyle(
                color: StudioColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connect a USB/Wi-Fi camera or start the Mock Camera Simulator',
              style: TextStyle(color: StudioColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('btn_empty_connect_mock'),
              onPressed: widget.onConnectMockCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: StudioColors.accentAmber,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text(
                'Start Mock Tether (3s Interval)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final exif = ExifSummary.fromJsonString(photo.exifJson);

    return Container(
      color: StudioColors.canvasBackground,
      child: Stack(
        children: [
          // Zoomable & Pannable Main Photo Canvas (up to 400%)
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _handleDoubleTap,
              onLongPressStart: (_) => widget.onBeforeAfterChanged(true),
              onLongPressEnd: (_) => widget.onBeforeAfterChanged(false),
              onTap: () {
                setState(() {
                  _showBottomOverlay = !_showBottomOverlay;
                });
              },
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 1.0,
                maxScale: 4.0,
                panEnabled: true,
                scaleEnabled: true,
                onInteractionEnd: (_) {
                  setState(() {
                    _currentZoom =
                        _transformController.value.getMaxScaleOnAxis();
                  });
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildImageContent(photo),
                  ),
                ),
              ),
            ),
          ),

          // Top Floating Badges (Before/After indicator, Zoom indicator, Jump to Latest)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (widget.isBeforeAfterPressed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: StudioColors.accentAmber),
                        ),
                        child: const Text(
                          'BEFORE (ORIGINAL)',
                          style: TextStyle(
                            color: StudioColors.accentAmber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: StudioTheme.monospaceFont,
                          ),
                        ),
                      ),
                    if (_currentZoom > 1.05) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _resetZoom,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: StudioColors.panelBorder),
                          ),
                          child: Text(
                            '${(_currentZoom * 100).round()}% (Reset)',
                            style: const TextStyle(
                              color: StudioColors.textPrimary,
                              fontSize: 10,
                              fontFamily: StudioTheme.monospaceFont,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (widget.isViewingOlderPhoto)
                  ElevatedButton.icon(
                    key: const Key('btn_jump_to_latest'),
                    onPressed: widget.onJumpToLatest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioColors.accentAmber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.skip_next_rounded, size: 16),
                    label: const Text(
                      'Jump to Latest',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Thin Overlay (Favorite, Reject, 1-line Monospace EXIF)
          if (_showBottomOverlay)
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: StudioColors.panelSurface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: StudioColors.panelBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _actionChip(
                          key: const Key('btn_canvas_favorite'),
                          icon: photo.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: 'Fav',
                          activeColor: StudioColors.statusFavorite,
                          isActive: photo.isFavorite,
                          onTap: widget.onToggleFavorite,
                        ),
                        const SizedBox(width: 8),
                        _actionChip(
                          key: const Key('btn_canvas_reject'),
                          icon: Icons.close_rounded,
                          label: 'Reject',
                          activeColor: StudioColors.statusError,
                          isActive: photo.isRejected,
                          onTap: widget.onToggleReject,
                        ),
                      ],
                    ),
                    Flexible(
                      child: Text(
                        '${photo.fileName}  ·  ${exif.oneLineSummary}',
                        style: const TextStyle(
                          color: StudioColors.textPrimary,
                          fontSize: 11,
                          fontFamily: StudioTheme.monospaceFont,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required Key key,
    required IconData icon,
    required String label,
    required Color activeColor,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.2)
              : StudioColors.canvasBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? activeColor : StudioColors.panelBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isActive ? activeColor : StudioColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? activeColor : StudioColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
