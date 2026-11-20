import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/film_sim/data/gpu_lut_renderer.dart';
import 'package:photoe_zi/features/film_sim/domain/cube_lut_parser.dart';

class MainPhotoCanvas extends StatefulWidget {
  final Photo? activePhoto;
  final Uint8List? inMemoryPreview;
  final String activeLutId;
  final CubeLutData? activeLutData;
  final ui.Image? activeLutTexture;
  final double lutIntensity;
  final bool isBeforeAfterPressed;
  final bool lockLatest;
  final bool isViewingOlderPhoto;
  final bool isZenMode;
  final bool isLiveViewActive;
  final bool isLiveViewReconnecting;
  final Uint8List? liveViewFrame;
  final VoidCallback? onCancelLiveView;
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
    this.activeLutData,
    this.activeLutTexture,
    required this.lutIntensity,
    required this.isBeforeAfterPressed,
    required this.lockLatest,
    required this.isViewingOlderPhoto,
    required this.isZenMode,
    this.isLiveViewActive = false,
    this.isLiveViewReconnecting = false,
    this.liveViewFrame,
    this.onCancelLiveView,
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

  Uint8List? _resolveDisplayBytes(Photo photo) {
    final fullPath = photo.fullResPath;
    if (fullPath != null) {
      final f = File(fullPath);
      if (f.existsSync()) {
        return f.readAsBytesSync();
      }
    }
    if (widget.inMemoryPreview != null) {
      return widget.inMemoryPreview;
    }
    if (photo.previewPath != null) {
      final f = File(photo.previewPath!);
      if (f.existsSync()) {
        return f.readAsBytesSync();
      }
    }
    return null;
  }

  Widget _buildImageContent(Photo photo) {
    if (widget.isLiveViewActive && widget.liveViewFrame != null) {
      return Image.memory(
        widget.liveViewFrame!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );
    }

    final bytes = _resolveDisplayBytes(photo);
    if (bytes == null) {
      return const Center(
        child: Icon(
          Icons.image_outlined,
          size: 64,
          color: StudioColors.textMuted,
        ),
      );
    }

    return GpuLutImageRenderer(
      key: ValueKey('gpu_lut_${photo.id}_${photo.fullResPath != null}'),
      imageBytes: bytes,
      lutData: widget.activeLutData,
      lutTexture: widget.activeLutTexture,
      intensity: widget.lutIntensity,
      bypassLut: widget.isBeforeAfterPressed || widget.activeLutId == 'none',
    );
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
      if (widget.isLiveViewActive || widget.isLiveViewReconnecting) {
        return Container(
          color: StudioColors.canvasBackground,
          child: Stack(
            children: [
              if (widget.isLiveViewActive && widget.liveViewFrame != null)
                Positioned.fill(
                  child: Image.memory(
                    widget.liveViewFrame!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              if (widget.isLiveViewActive)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 7, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          'LIVE VIEW (EVF)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.isLiveViewReconnecting)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.72),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: StudioColors.panelSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: StudioColors.panelBorder),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  StudioColors.accentAmber,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Resuming Live View (EVF)...',
                              style: TextStyle(
                                color: StudioColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Clearing camera buffer · Auto-restarting EVF',
                              style: TextStyle(
                                color: StudioColors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }

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
                'Start Mock Tether (3 Sample Shots)',
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

          // Live View Active Badge
          if (widget.isLiveViewActive)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.35),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 7, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'LIVE VIEW (EVF)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Live View Reconnecting Overlay (Smooth camera buffer clear indicator)
          if (widget.isLiveViewReconnecting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.72),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: StudioColors.panelSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StudioColors.panelBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              StudioColors.accentAmber,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Resuming Live View (EVF)...',
                          style: TextStyle(
                            color: StudioColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Clearing camera buffer · Auto-restarting EVF',
                          style: TextStyle(
                            color: StudioColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        if (widget.onCancelLiveView != null) ...[
                          SizedBox(height: 12),
                          InkWell(
                            onTap: widget.onCancelLiveView,
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              child: Text(
                                'Cancel & Return to Photo',
                                style: TextStyle(
                                  color: StudioColors.accentAmber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
