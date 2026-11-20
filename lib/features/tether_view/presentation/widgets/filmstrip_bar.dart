import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/features/tether_view/presentation/tether_workspace_controller.dart';

class FilmstripBar extends StatefulWidget {
  final List<Photo> allPhotos;
  final Map<String, Uint8List> inMemoryPreviews;
  final Map<String, String> uploadStatusByPhotoId;
  final String? selectedPhotoId;
  final FilmstripFilter activeFilter;
  final bool lockLatest;
  final bool isVertical;
  final double height;
  final ValueChanged<FilmstripFilter> onFilterChanged;
  final VoidCallback onToggleLockLatest;
  final VoidCallback onToggleOrientation;
  final void Function(String photoId, bool isLatest) onSelectPhoto;
  final VoidCallback? onResetCamera;

  const FilmstripBar({
    super.key,
    required this.allPhotos,
    required this.inMemoryPreviews,
    required this.uploadStatusByPhotoId,
    required this.selectedPhotoId,
    required this.activeFilter,
    required this.lockLatest,
    this.isVertical = false,
    this.height = 105,
    required this.onFilterChanged,
    required this.onToggleLockLatest,
    required this.onToggleOrientation,
    required this.onSelectPhoto,
    this.onResetCamera,
  });

  @override
  State<FilmstripBar> createState() => _FilmstripBarState();
}

class _FilmstripBarState extends State<FilmstripBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant FilmstripBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allPhotos.length > oldWidget.allPhotos.length &&
        widget.lockLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favoriteCount = widget.allPhotos.where((p) => p.isFavorite).length;
    final filteredPhotos = widget.activeFilter == FilmstripFilter.favorites
        ? widget.allPhotos.where((p) => p.isFavorite).toList()
        : widget.allPhotos;
    final latestPhotoId =
        widget.allPhotos.isNotEmpty ? widget.allPhotos.last.id : null;

    if (widget.isVertical) {
      return Container(
        width: 120,
        decoration: const BoxDecoration(
          color: StudioColors.panelSurface,
          border: Border(
            right: BorderSide(color: StudioColors.panelBorder, width: 1),
          ),
        ),
        child: Column(
          children: [
            _buildCompactHeader(favoriteCount),
            const Divider(height: 1, color: StudioColors.panelBorder),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(6),
                itemCount: filteredPhotos.length,
                itemBuilder: (context, index) {
                  final photo = filteredPhotos[index];
                  final isLatest = photo.id == latestPhotoId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      height: 76,
                      child: _buildThumbnailTile(photo, isLatest),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: StudioColors.panelSurface,
        border: Border(
          top: BorderSide(color: StudioColors.panelBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Filmstrip Filter & Controls Bar
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Filter:',
                          style: TextStyle(
                            color: StudioColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          key: const Key('filter_all'),
                          label: 'All (${widget.allPhotos.length})',
                          isSelected:
                              widget.activeFilter == FilmstripFilter.all,
                          onTap: () =>
                              widget.onFilterChanged(FilmstripFilter.all),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          key: const Key('filter_favorites'),
                          label: '♥ $favoriteCount',
                          isSelected:
                              widget.activeFilter == FilmstripFilter.favorites,
                          onTap: () =>
                              widget.onFilterChanged(FilmstripFilter.favorites),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      key: const Key('toggle_lock_latest'),
                      onTap: widget.onToggleLockLatest,
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: widget.lockLatest
                              ? StudioColors.accentAmber.withValues(alpha: 0.16)
                              : StudioColors.canvasBackground,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: widget.lockLatest
                                ? StudioColors.accentAmber
                                : StudioColors.panelBorder,
                          ),
                        ),
                        child: Text(
                          'Lock Latest: ${widget.lockLatest ? "ON" : "OFF"}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: StudioTheme.monospaceFont,
                            color: widget.lockLatest
                                ? StudioColors.accentAmber
                                : StudioColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (widget.onResetCamera != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        key: const Key('btn_filmstrip_reset_camera'),
                        onTap: widget.onResetCamera,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: StudioColors.canvasBackground,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: StudioColors.panelBorder),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                size: 11,
                                color: StudioColors.textSecondary,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Reset',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: StudioColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Toggle Vertical/Horizontal Filmstrip',
                      onPressed: widget.onToggleOrientation,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 22, minHeight: 22),
                      icon: const Icon(
                        Icons.view_sidebar_outlined,
                        size: 14,
                        color: StudioColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: StudioColors.panelBorder),
          // Horizontal Thumbnail Strip
          Expanded(
            child: filteredPhotos.isEmpty
                ? const Center(
                    child: Text(
                      'No photos in filmstrip',
                      style: TextStyle(
                        color: StudioColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    itemCount: filteredPhotos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final photo = filteredPhotos[index];
                      final isLatest = photo.id == latestPhotoId;
                      return SizedBox(
                        width: 86,
                        child: _buildThumbnailTile(photo, isLatest),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader(int favoriteCount) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _filterChip(
            key: const Key('filter_all_vert'),
            label: 'All (${widget.allPhotos.length})',
            isSelected: widget.activeFilter == FilmstripFilter.all,
            onTap: () => widget.onFilterChanged(FilmstripFilter.all),
          ),
          IconButton(
            onPressed: widget.onToggleOrientation,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            icon: const Icon(
              Icons.view_stream_outlined,
              size: 14,
              color: StudioColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? StudioColors.panelElevated
              : StudioColors.canvasBackground,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected
                ? StudioColors.activeWhite
                : StudioColors.panelBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? StudioColors.textPrimary
                : StudioColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailTile(Photo photo, bool isLatest) {
    final isSelected = photo.id == widget.selectedPhotoId;
    final syncStatus = widget.uploadStatusByPhotoId[photo.id] ?? 'completed';
    final previewBytes = widget.inMemoryPreviews[photo.id];

    Widget imageThumb;
    if (previewBytes != null) {
      imageThumb = Image.memory(
        previewBytes,
        fit: BoxFit.cover,
        cacheWidth: 300,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    } else if (photo.previewPath != null &&
        File(photo.previewPath!).existsSync()) {
      imageThumb = Image.file(
        File(photo.previewPath!),
        fit: BoxFit.cover,
        cacheWidth: 300,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    } else if (photo.fullResPath != null &&
        File(photo.fullResPath!).existsSync()) {
      imageThumb = Image.file(
        File(photo.fullResPath!),
        fit: BoxFit.cover,
        cacheWidth: 300,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    } else {
      imageThumb = Container(color: StudioColors.canvasBackground);
    }

    return GestureDetector(
      key: Key('thumb_${photo.id}'),
      onTap: () => widget.onSelectPhoto(photo.id, isLatest),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: photo.isRejected ? 0.4 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: StudioColors.canvasBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? StudioColors.accentAmber
                  : StudioColors.panelBorder,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              imageThumb,
              // Top-left Micro-badge: Favorite ♥ or *NEW*
              Positioned(
                top: 3,
                left: 3,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (photo.isFavorite)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 11,
                          color: StudioColors.statusFavorite,
                        ),
                      ),
                    if (isLatest) ...[
                      if (photo.isFavorite) const SizedBox(width: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: StudioColors.accentAmber,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            fontFamily: StudioTheme.monospaceFont,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Bottom filename + Bottom-right Google Drive sync micro-badge
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          photo.fileName.replaceAll('.JPG', ''),
                          style: const TextStyle(
                            color: StudioColors.textPrimary,
                            fontSize: 8.5,
                            fontFamily: StudioTheme.monospaceFont,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildDriveSyncBadge(syncStatus),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriveSyncBadge(String status) {
    switch (status) {
      case 'completed':
        return const Text(
          '✓',
          style: TextStyle(
            color: StudioColors.statusSuccess,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
      case 'uploading':
      case 'bakingLut':
        return const SizedBox(
          width: 8,
          height: 8,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: StudioColors.accentAmber,
          ),
        );
      case 'failed':
        return const Text(
          '!',
          style: TextStyle(
            color: StudioColors.statusError,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
      default:
        return const Text(
          '•',
          style: TextStyle(
            color: StudioColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
    }
  }
}
