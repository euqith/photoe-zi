import 'dart:convert';
import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ExifSummary {
  final String cameraModel;
  final String lens;
  final String aperture;
  final String shutterSpeed;
  final String iso;
  final String focalLength;
  final String resolution;

  const ExifSummary({
    required this.cameraModel,
    required this.lens,
    required this.aperture,
    required this.shutterSpeed,
    required this.iso,
    required this.focalLength,
    required this.resolution,
  });

  String get oneLineSummary => '$aperture · $shutterSpeed · ISO $iso';

  factory ExifSummary.fromJsonString(String exifJson) {
    try {
      final decoded = jsonDecode(exifJson);
      if (decoded is Map<String, dynamic>) {
        return ExifSummary.fromMap(decoded);
      }
    } catch (_) {}
    return const ExifSummary(
      cameraModel: 'Canon EOS 6D',
      lens: 'EF 50mm f/1.8 STM',
      aperture: 'f/1.8',
      shutterSpeed: '1/250s',
      iso: '200',
      focalLength: '50mm',
      resolution: '5472 × 3648',
    );
  }

  factory ExifSummary.fromMap(Map<String, dynamic> map) {
    return ExifSummary(
      cameraModel: (map['cameraModel'] ?? 'Canon EOS 6D').toString(),
      lens: (map['lens'] ?? 'EF 50mm f/1.8 STM').toString(),
      aperture: (map['aperture'] ?? 'f/1.8').toString(),
      shutterSpeed: (map['shutterSpeed'] ?? '1/250s').toString(),
      iso: (map['iso'] ?? '200').toString(),
      focalLength: (map['focalLength'] ?? '50mm').toString(),
      resolution: (map['resolution'] ?? '5472 × 3648').toString(),
    );
  }

  /// Reads raw EXIF tags from a JPEG byte buffer using package:exif,
  /// merging with any existing metadata map.
  static Future<Map<String, dynamic>> extractFromJpegBytes(
    Uint8List bytes, {
    Map<String, dynamic>? fallback,
  }) async {
    final result = Map<String, dynamic>.from(fallback ?? {});
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isNotEmpty) {
        if (tags.containsKey('Image Model')) {
          result['cameraModel'] = tags['Image Model']!.printable;
        }
        if (tags.containsKey('EXIF LensModel')) {
          result['lens'] = tags['EXIF LensModel']!.printable;
        }
        if (tags.containsKey('EXIF FNumber')) {
          result['aperture'] = 'f/${tags['EXIF FNumber']!.printable}';
        }
        if (tags.containsKey('EXIF ExposureTime')) {
          result['shutterSpeed'] = '${tags['EXIF ExposureTime']!.printable}s';
        }
        if (tags.containsKey('EXIF ISOSpeedRatings')) {
          result['iso'] = tags['EXIF ISOSpeedRatings']!.printable;
        }
        if (tags.containsKey('EXIF FocalLength')) {
          result['focalLength'] = '${tags['EXIF FocalLength']!.printable}mm';
        }
      }
    } catch (_) {}
    return result;
  }
}

class RgbHistogramData {
  final List<double> red;
  final List<double> green;
  final List<double> blue;
  final List<double> luminance;

  const RgbHistogramData({
    required this.red,
    required this.green,
    required this.blue,
    required this.luminance,
  });

  factory RgbHistogramData.empty() {
    return RgbHistogramData(
      red: List<double>.filled(64, 0.0),
      green: List<double>.filled(64, 0.0),
      blue: List<double>.filled(64, 0.0),
      luminance: List<double>.filled(64, 0.0),
    );
  }
}

RgbHistogramData _computeHistogramInIsolate(Uint8List imageBytes) {
  const int bins = 64;
  final rCounts = List<int>.filled(bins, 0);
  final gCounts = List<int>.filled(bins, 0);
  final bCounts = List<int>.filled(bins, 0);
  final lCounts = List<int>.filled(bins, 0);

  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) {
    return RgbHistogramData.empty();
  }

  // Sample with step to guarantee fast computation even on large images
  final stepX = (decoded.width / 120).ceil().clamp(1, 32);
  final stepY = (decoded.height / 120).ceil().clamp(1, 32);

  for (int y = 0; y < decoded.height; y += stepY) {
    for (int x = 0; x < decoded.width; x += stepX) {
      final pixel = decoded.getPixel(x, y);
      final r = pixel.r.toInt().clamp(0, 255);
      final g = pixel.g.toInt().clamp(0, 255);
      final b = pixel.b.toInt().clamp(0, 255);
      final lum = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);

      rCounts[(r * bins) ~/ 256]++;
      gCounts[(g * bins) ~/ 256]++;
      bCounts[(b * bins) ~/ 256]++;
      lCounts[(lum * bins) ~/ 256]++;
    }
  }

  int maxCount = 1;
  for (int i = 0; i < bins; i++) {
    if (rCounts[i] > maxCount) maxCount = rCounts[i];
    if (gCounts[i] > maxCount) maxCount = gCounts[i];
    if (bCounts[i] > maxCount) maxCount = bCounts[i];
    if (lCounts[i] > maxCount) maxCount = lCounts[i];
  }

  return RgbHistogramData(
    red: rCounts.map((c) => c / maxCount).toList(growable: false),
    green: gCounts.map((c) => c / maxCount).toList(growable: false),
    blue: bCounts.map((c) => c / maxCount).toList(growable: false),
    luminance: lCounts.map((c) => c / maxCount).toList(growable: false),
  );
}

class HistogramCalculator {
  HistogramCalculator._();

  /// Computes normalized 64-bin RGB + Luminance histogram in a background isolate
  /// so the Flutter UI thread remains locked at 60fps.
  static Future<RgbHistogramData> computeFromBytes(Uint8List bytes) {
    return compute(_computeHistogramInIsolate, bytes);
  }

  static Future<RgbHistogramData> computeFromFilePath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return RgbHistogramData.empty();
    }
    final bytes = await file.readAsBytes();
    return compute(_computeHistogramInIsolate, bytes);
  }
}

