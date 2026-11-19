import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photoe_zi/features/film_sim/domain/cube_lut_parser.dart';
import 'package:photoe_zi/features/film_sim/domain/lut_preset.dart';

class LutPresetManager {
  final Future<Directory> Function()? customLutDirProvider;
  final Map<String, CubeLutData> _parsedCache = {};
  final Map<String, ui.Image> _gpuTextureCache = {};
  final List<LutPreset> _customPresets = [];

  LutPresetManager({this.customLutDirProvider});

  List<LutPreset> get allPresets => [
        ...LutPreset.builtInPresets,
        ..._customPresets,
      ];

  Future<Directory> _resolveCustomLutDir() async {
    if (customLutDirProvider != null) {
      return customLutDirProvider!();
    }
    try {
      final appDir = await getApplicationSupportDirectory();
      final lutDir = Directory(p.join(appDir.path, 'custom_luts'));
      if (!await lutDir.exists()) {
        await lutDir.create(recursive: true);
      }
      return lutDir;
    } catch (_) {
      final fallback =
          Directory(p.join(Directory.systemTemp.path, 'photoe_zi_custom_luts'));
      if (!await fallback.exists()) {
        await fallback.create(recursive: true);
      }
      return fallback;
    }
  }

  /// Loads any previously imported `.cube` files from the app's custom preset directory.
  Future<List<LutPreset>> loadSavedCustomPresets() async {
    final dir = await _resolveCustomLutDir();
    if (!await dir.exists()) {
      return allPresets;
    }

    _customPresets.clear();
    final entries = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.cube'))
        .toList();

    for (final file in entries) {
      try {
        final content = await file.readAsString();
        final baseName = p.basenameWithoutExtension(file.path);
        final parsed = CubeLutParser.parse(content, fallbackTitle: baseName);
        final id = 'custom_$baseName';
        _parsedCache[id] = parsed;
        _customPresets.add(
          LutPreset(
            id: id,
            name: parsed.title,
            category: 'Custom .cube',
            customFilePath: file.path,
            isCustom: true,
          ),
        );
      } catch (_) {}
    }
    return allPresets;
  }

  /// Imports a custom `.cube` file from device storage into the app's preset directory.
  Future<LutPreset> importCustomCubeFile(File sourceFile) async {
    final content = await sourceFile.readAsString();
    final rawBaseName = p.basenameWithoutExtension(sourceFile.path);
    final sanitizedBase =
        rawBaseName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final parsed = CubeLutParser.parse(content, fallbackTitle: rawBaseName);

    final targetDir = await _resolveCustomLutDir();
    final targetPath = p.join(targetDir.path, '$sanitizedBase.cube');
    await sourceFile.copy(targetPath);

    final id = 'custom_$sanitizedBase';
    _parsedCache[id] = parsed;

    final preset = LutPreset(
      id: id,
      name: parsed.title,
      category: 'Custom .cube',
      customFilePath: targetPath,
      isCustom: true,
    );

    _customPresets.removeWhere((item) => item.id == id);
    _customPresets.add(preset);
    return preset;
  }

  /// Loads and caches the parsed `CubeLutData` for any built-in or custom preset ID.
  Future<CubeLutData?> getLutData(String presetId) async {
    if (presetId == 'none' || presetId.isEmpty) {
      return null;
    }
    if (_parsedCache.containsKey(presetId)) {
      return _parsedCache[presetId];
    }

    final preset = allPresets.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) {
      return null;
    }

    String content;
    if (preset.isCustom && preset.customFilePath != null) {
      final file = File(preset.customFilePath!);
      if (!await file.exists()) return null;
      content = await file.readAsString();
    } else if (preset.assetPath != null) {
      content = await rootBundle.loadString(preset.assetPath!);
    } else {
      return null;
    }

    final parsed = CubeLutParser.parse(content, fallbackTitle: preset.name);
    _parsedCache[presetId] = parsed;
    return parsed;
  }

  /// Converts the parsed 3D LUT into a cached `ui.Image` 2D horizontal strip texture
  /// for real-time GPU fragment shader rendering.
  Future<ui.Image?> getGpuLutTexture(String presetId) async {
    if (presetId == 'none' || presetId.isEmpty) {
      return null;
    }
    if (_gpuTextureCache.containsKey(presetId)) {
      return _gpuTextureCache[presetId];
    }

    final lutData = await getLutData(presetId);
    if (lutData == null) {
      return null;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      lutData.rgbaAtlasBytes,
      lutData.atlasWidth,
      lutData.atlasHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final texture = await completer.future;
    _gpuTextureCache[presetId] = texture;
    return texture;
  }
}
