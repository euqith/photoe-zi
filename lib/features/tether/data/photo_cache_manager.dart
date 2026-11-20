import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';

/// Hardened LRU Memory & Disk Cache for incoming tethered photos.
/// Prevents Out-Of-Memory (OOM) during marathon shooting sessions (100+ photos).
class PhotoCacheManager {
  final int maxMemoryEntries;
  final Directory? cacheDir;

  // LinkedHashMap maintains insertion / access order for LRU eviction
  final LinkedHashMap<String, Uint8List> _memoryByteCache =
      LinkedHashMap<String, Uint8List>();
  final Map<String, IncomingPhoto> _photoMetadata = {};

  PhotoCacheManager({
    this.maxMemoryEntries = 25,
    this.cacheDir,
  });

  int get cachedMemoryCount => _memoryByteCache.length;
  int get totalTrackedPhotos => _photoMetadata.length;

  void addPhoto(IncomingPhoto photo) {
    _photoMetadata[photo.id] = photo;

    if (photo.previewBytes != null) {
      _putBytes(photo.id, photo.previewBytes!);
    }
  }

  void _putBytes(String id, Uint8List bytes) {
    if (_memoryByteCache.containsKey(id)) {
      _memoryByteCache.remove(id);
    } else if (_memoryByteCache.length >= maxMemoryEntries) {
      // Evict least-recently-used item to disk
      final oldestId = _memoryByteCache.keys.first;
      final oldestBytes = _memoryByteCache.remove(oldestId);
      if (oldestBytes != null && cacheDir != null) {
        _persistToDisk(oldestId, oldestBytes);
      }
    }
    _memoryByteCache[id] = bytes;
  }

  Future<Uint8List?> getPreviewBytes(String id) async {
    if (_memoryByteCache.containsKey(id)) {
      final bytes = _memoryByteCache.remove(id)!;
      _memoryByteCache[id] = bytes; // Promote to MRU
      return bytes;
    }

    // Try reading from disk cache if evicted
    if (cacheDir != null) {
      final file = File('${cacheDir!.path}/$id.cache');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _putBytes(id, bytes);
        return bytes;
      }
    }

    return _photoMetadata[id]?.previewBytes;
  }

  Future<void> _persistToDisk(String id, Uint8List bytes) async {
    try {
      if (cacheDir != null) {
        if (!await cacheDir!.exists()) {
          await cacheDir!.create(recursive: true);
        }
        final file = File('${cacheDir!.path}/$id.cache');
        await file.writeAsBytes(bytes, flush: false);
      }
    } catch (_) {}
  }

  IncomingPhoto? getPhoto(String id) {
    return _photoMetadata[id];
  }

  List<IncomingPhoto> getAllPhotos() {
    return _photoMetadata.values.toList();
  }

  void clear() {
    _memoryByteCache.clear();
    _photoMetadata.clear();
  }
}

final photoCacheManagerProvider = Provider<PhotoCacheManager>((ref) {
  return PhotoCacheManager();
});
