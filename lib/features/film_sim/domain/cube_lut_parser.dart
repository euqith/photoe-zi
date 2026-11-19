import 'dart:typed_data';

class CubeLutData {
  final String title;
  final int size; // N (typically 17 or 33)
  final Float32List rgbValues; // length: N * N * N * 3
  final Uint8List rgbaAtlasBytes; // 2D horizontal strip texture: (N * N) x N x 4

  const CubeLutData({
    required this.title,
    required this.size,
    required this.rgbValues,
    required this.rgbaAtlasBytes,
  });

  int get atlasWidth => size * size;
  int get atlasHeight => size;

  /// Performs fast trilinear interpolation on CPU for a normalized RGB pixel [0.0..1.0]
  /// or 8-bit integer RGB [0..255], returning 8-bit [R, G, B].
  List<int> lookupRgb8(int r8, int g8, int b8, {double intensity = 1.0}) {
    if (intensity <= 0.0) {
      return [r8, g8, b8];
    }

    final n = size;
    final maxIdx = n - 1;
    final rf = (r8 / 255.0).clamp(0.0, 1.0) * maxIdx;
    final gf = (g8 / 255.0).clamp(0.0, 1.0) * maxIdx;
    final bf = (b8 / 255.0).clamp(0.0, 1.0) * maxIdx;

    final r0 = rf.floor();
    final g0 = gf.floor();
    final b0 = bf.floor();
    final r1 = (r0 + 1 <= maxIdx) ? r0 + 1 : maxIdx;
    final g1 = (g0 + 1 <= maxIdx) ? g0 + 1 : maxIdx;
    final b1 = (b0 + 1 <= maxIdx) ? b0 + 1 : maxIdx;

    final dr = rf - r0;
    final dg = gf - g0;
    final db = bf - b0;

    int baseIndex(int r, int g, int b) => ((b * n + g) * n + r) * 3;

    double interpChannel(int ch) {
      final c000 = rgbValues[baseIndex(r0, g0, b0) + ch];
      final c100 = rgbValues[baseIndex(r1, g0, b0) + ch];
      final c010 = rgbValues[baseIndex(r0, g1, b0) + ch];
      final c110 = rgbValues[baseIndex(r1, g1, b0) + ch];
      final c001 = rgbValues[baseIndex(r0, g0, b1) + ch];
      final c101 = rgbValues[baseIndex(r1, g0, b1) + ch];
      final c011 = rgbValues[baseIndex(r0, g1, b1) + ch];
      final c111 = rgbValues[baseIndex(r1, g1, b1) + ch];

      final c00 = c000 * (1.0 - dr) + c100 * dr;
      final c10 = c010 * (1.0 - dr) + c110 * dr;
      final c01 = c001 * (1.0 - dr) + c101 * dr;
      final c11 = c011 * (1.0 - dr) + c111 * dr;

      final c0 = c00 * (1.0 - dg) + c10 * dg;
      final c1 = c01 * (1.0 - dg) + c11 * dg;

      return c0 * (1.0 - db) + c1 * db;
    }

    final lutR = (interpChannel(0) * 255.0).clamp(0.0, 255.0);
    final lutG = (interpChannel(1) * 255.0).clamp(0.0, 255.0);
    final lutB = (interpChannel(2) * 255.0).clamp(0.0, 255.0);

    final t = intensity.clamp(0.0, 1.0);
    final outR = (r8 * (1.0 - t) + lutR * t).round().clamp(0, 255);
    final outG = (g8 * (1.0 - t) + lutG * t).round().clamp(0, 255);
    final outB = (b8 * (1.0 - t) + lutB * t).round().clamp(0, 255);

    return [outR, outG, outB];
  }
}

class CubeLutParser {
  CubeLutParser._();

  /// Parses an Adobe/IRIDAS `.cube` 3D LUT string (supports 17x17x17, 33x33x33, etc.)
  /// and packs it into both a Float32List and a 2D RGBA texture strip (width = N*N, height = N)
  /// ready for GPU shader sampling.
  static CubeLutData parse(String content, {String fallbackTitle = 'Custom LUT'}) {
    String title = fallbackTitle;
    int? lutSize;
    List<double> domainMin = [0.0, 0.0, 0.0];
    List<double> domainMax = [1.0, 1.0, 1.0];

    final lines = content.split(RegExp(r'\r?\n'));
    final rawTriplets = <double>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      if (line.startsWith('TITLE')) {
        final match = RegExp(r'TITLE\s+"?([^"]+)"?').firstMatch(line);
        if (match != null) {
          title = match.group(1)!.trim();
        }
        continue;
      }

      if (line.startsWith('LUT_3D_SIZE')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          lutSize = int.tryParse(parts[1]);
        }
        continue;
      }

      if (line.startsWith('DOMAIN_MIN')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          domainMin = [
            double.tryParse(parts[1]) ?? 0.0,
            double.tryParse(parts[2]) ?? 0.0,
            double.tryParse(parts[3]) ?? 0.0,
          ];
        }
        continue;
      }

      if (line.startsWith('DOMAIN_MAX')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          domainMax = [
            double.tryParse(parts[1]) ?? 1.0,
            double.tryParse(parts[2]) ?? 1.0,
            double.tryParse(parts[3]) ?? 1.0,
          ];
        }
        continue;
      }

      if (line.startsWith('LUT_1D_SIZE') || line.startsWith('LUT_')) {
        continue;
      }

      // Parse data row: R G B
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final r = double.tryParse(parts[0]);
        final g = double.tryParse(parts[1]);
        final b = double.tryParse(parts[2]);
        if (r != null && g != null && b != null) {
          rawTriplets.add(r);
          rawTriplets.add(g);
          rawTriplets.add(b);
        }
      }
    }

    if (lutSize == null || lutSize <= 1) {
      throw const FormatException('Missing or invalid LUT_3D_SIZE in .cube file');
    }

    final expectedCount = lutSize * lutSize * lutSize * 3;
    if (rawTriplets.length < expectedCount) {
      throw FormatException(
        'Incomplete .cube LUT data: expected ${expectedCount ~/ 3} entries for size $lutSize, got ${rawTriplets.length ~/ 3}',
      );
    }

    final rgbFloats = Float32List(expectedCount);
    final rgbaAtlas = Uint8List(lutSize * lutSize * lutSize * 4);

    final rangeR = (domainMax[0] - domainMin[0]) == 0 ? 1.0 : (domainMax[0] - domainMin[0]);
    final rangeG = (domainMax[1] - domainMin[1]) == 0 ? 1.0 : (domainMax[1] - domainMin[1]);
    final rangeB = (domainMax[2] - domainMin[2]) == 0 ? 1.0 : (domainMax[2] - domainMin[2]);

    final n = lutSize;
    final atlasWidth = n * n;

    int tripletIdx = 0;
    for (int b = 0; b < n; b++) {
      for (int g = 0; g < n; g++) {
        for (int r = 0; r < n; r++) {
          final normR = ((rawTriplets[tripletIdx] - domainMin[0]) / rangeR).clamp(0.0, 1.0);
          final normG = ((rawTriplets[tripletIdx + 1] - domainMin[1]) / rangeG).clamp(0.0, 1.0);
          final normB = ((rawTriplets[tripletIdx + 2] - domainMin[2]) / rangeB).clamp(0.0, 1.0);

          rgbFloats[tripletIdx] = normR;
          rgbFloats[tripletIdx + 1] = normG;
          rgbFloats[tripletIdx + 2] = normB;
          tripletIdx += 3;

          // Pack into 2D horizontal strip atlas:
          // x = b * n + r, y = g
          final atlasX = b * n + r;
          final atlasY = g;
          final pixelOffset = (atlasY * atlasWidth + atlasX) * 4;
          rgbaAtlas[pixelOffset] = (normR * 255.0).round().clamp(0, 255);
          rgbaAtlas[pixelOffset + 1] = (normG * 255.0).round().clamp(0, 255);
          rgbaAtlas[pixelOffset + 2] = (normB * 255.0).round().clamp(0, 255);
          rgbaAtlas[pixelOffset + 3] = 255;
        }
      }
    }

    return CubeLutData(
      title: title,
      size: lutSize,
      rgbValues: rgbFloats,
      rgbaAtlasBytes: rgbaAtlas,
    );
  }
}
