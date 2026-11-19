import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photoe_zi/features/film_sim/domain/cube_lut_parser.dart';

class _BakeJobPayload {
  final Uint8List sourceJpegBytes;
  final int lutSize;
  final Float32List lutRgbValues;
  final double intensity;
  final int jpegQuality;

  const _BakeJobPayload({
    required this.sourceJpegBytes,
    required this.lutSize,
    required this.lutRgbValues,
    required this.intensity,
    required this.jpegQuality,
  });
}

/// Extracts all APP1 (0xFFE1 — EXIF/XMP) segments from the source JPEG
/// and splices them right after the SOI (0xFFD8) marker of the newly encoded JPEG,
/// ensuring 100% lossless EXIF metadata preservation.
Uint8List _preserveJpegExifSegments(
  Uint8List originalJpeg,
  Uint8List encodedJpeg,
) {
  if (originalJpeg.length < 4 ||
      originalJpeg[0] != 0xFF ||
      originalJpeg[1] != 0xD8 ||
      encodedJpeg.length < 4 ||
      encodedJpeg[0] != 0xFF ||
      encodedJpeg[1] != 0xD8) {
    return encodedJpeg;
  }

  final app1Segments = <Uint8List>[];
  int offset = 2;
  while (offset + 4 <= originalJpeg.length) {
    if (originalJpeg[offset] != 0xFF) {
      break;
    }
    final marker = originalJpeg[offset + 1];
    // Stop at SOS (Start of Scan 0xDA) or EOI (0xD9)
    if (marker == 0xDA || marker == 0xD9) {
      break;
    }
    // Standalone markers without length
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    final segLength =
        (originalJpeg[offset + 2] << 8) | originalJpeg[offset + 3];
    if (segLength < 2 || offset + 2 + segLength > originalJpeg.length) {
      break;
    }
    if (marker == 0xE1) {
      app1Segments.add(
        Uint8List.sublistView(originalJpeg, offset, offset + 2 + segLength),
      );
    }
    offset += 2 + segLength;
  }

  if (app1Segments.isEmpty) {
    return encodedJpeg;
  }

  final builder = BytesBuilder(copy: false);
  // SOI marker
  builder.addByte(0xFF);
  builder.addByte(0xD8);
  // Original EXIF/XMP APP1 segments
  for (final seg in app1Segments) {
    builder.add(seg);
  }
  // Remainder of the newly baked JPEG (skipping its 2-byte SOI)
  builder.add(Uint8List.sublistView(encodedJpeg, 2));
  return builder.toBytes();
}

Uint8List _bakeLutInIsolate(_BakeJobPayload job) {
  final decoded = img.decodeImage(job.sourceJpegBytes);
  if (decoded == null) {
    return job.sourceJpegBytes;
  }

  final lut = CubeLutData(
    title: 'BakeLUT',
    size: job.lutSize,
    rgbValues: job.lutRgbValues,
    rgbaAtlasBytes: Uint8List(0),
  );

  final t = job.intensity.clamp(0.0, 1.0);
  if (t > 0.001) {
    for (final pixel in decoded) {
      final r = pixel.r.toInt().clamp(0, 255);
      final g = pixel.g.toInt().clamp(0, 255);
      final b = pixel.b.toInt().clamp(0, 255);

      final mapped = lut.lookupRgb8(r, g, b, intensity: t);
      pixel
        ..r = mapped[0]
        ..g = mapped[1]
        ..b = mapped[2];
    }
  }

  final encoded = Uint8List.fromList(
    img.encodeJpg(decoded, quality: job.jpegQuality),
  );
  return _preserveJpegExifSegments(job.sourceJpegBytes, encoded);
}

class LutBakerService {
  const LutBakerService();

  /// Renders a full-resolution JPEG + 3D LUT in a background isolate
  /// (quality 92% by default, preserving EXIF APP1 metadata) and writes to `outputPath`.
  Future<File> bakeToFile({
    required String sourceImagePath,
    required CubeLutData lutData,
    double intensity = 1.0,
    int jpegQuality = 93,
    String? outputPath,
  }) async {
    final sourceFile = File(sourceImagePath);
    final sourceBytes = await sourceFile.readAsBytes();

    final bakedBytes = await bakeBytes(
      sourceJpegBytes: sourceBytes,
      lutData: lutData,
      intensity: intensity,
      jpegQuality: jpegQuality,
    );

    final targetPath = outputPath ??
        p.join(
          sourceFile.parent.path,
          '${p.basenameWithoutExtension(sourceImagePath)}_baked.jpg',
        );
    final outFile = File(targetPath);
    await outFile.writeAsBytes(bakedBytes, flush: true);
    return outFile;
  }

  Future<Uint8List> bakeBytes({
    required Uint8List sourceJpegBytes,
    required CubeLutData lutData,
    double intensity = 1.0,
    int jpegQuality = 93,
  }) {
    return compute(
      _bakeLutInIsolate,
      _BakeJobPayload(
        sourceJpegBytes: sourceJpegBytes,
        lutSize: lutData.size,
        lutRgbValues: lutData.rgbValues,
        intensity: intensity,
        jpegQuality: jpegQuality.clamp(90, 95),
      ),
    );
  }
}
