import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/film_sim/data/lut_baker_service.dart';
import 'package:photoe_zi/features/film_sim/data/lut_preset_manager.dart';
import 'package:photoe_zi/features/film_sim/domain/cube_lut_parser.dart';

String _buildSyntheticCubeString(int size, {String title = 'TestLUT'}) {
  final buffer = StringBuffer()
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
        // Warm tone shift: boost red slightly, dim blue slightly
        final ro = (rf * 0.9 + 0.1).clamp(0.0, 1.0);
        final go = gf.clamp(0.0, 1.0);
        final bo = (bf * 0.85).clamp(0.0, 1.0);
        buffer.writeln(
          '${ro.toStringAsFixed(5)} ${go.toStringAsFixed(5)} ${bo.toStringAsFixed(5)}',
        );
      }
    }
  }
  return buffer.toString();
}

/// Injects a synthetic APP1 (0xFFE1) EXIF segment after SOI (0xFFD8) for testing EXIF preservation.
Uint8List _injectTestExifApp1(Uint8List jpegBytes) {
  final exifPayload = Uint8List.fromList([
    0xFF, 0xE1, // APP1 marker
    0x00, 0x10, // Length = 16 bytes (including 2 length bytes)
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
  ]);
  final builder = BytesBuilder(copy: false)
    ..addByte(0xFF)
    ..addByte(0xD8)
    ..add(exifPayload)
    ..add(Uint8List.sublistView(jpegBytes, 2));
  return builder.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue #2.1 — .cube 3D LUT Parser & Preset Manager Tests', () {
    test('parses 17x17x17 and 33x33x33 .cube files into GPU 2D strip atlas',
        () {
      final cube17 = _buildSyntheticCubeString(17, title: 'Warm_17');
      final data17 = CubeLutParser.parse(cube17);
      expect(data17.title, 'Warm_17');
      expect(data17.size, 17);
      expect(data17.atlasWidth, 17 * 17);
      expect(data17.atlasHeight, 17);
      expect(data17.rgbaAtlasBytes.length, 17 * 17 * 17 * 4);

      final cube33 = _buildSyntheticCubeString(33, title: 'Cinema_33');
      final data33 = CubeLutParser.parse(cube33);
      expect(data33.title, 'Cinema_33');
      expect(data33.size, 33);
      expect(data33.atlasWidth, 33 * 33);
      expect(data33.atlasHeight, 33);
      expect(data33.rgbaAtlasBytes.length, 33 * 33 * 33 * 4);
    });

    test('loads built-in .cube assets and imports custom .cube preset',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lut_mgr_test_');
      final manager = LutPresetManager(
        customLutDirProvider: () async => tempDir,
      );

      // Verify built-in presets exist in assets/luts/
      final chromeData = await manager.getLutData('classic_chrome');
      expect(chromeData, isNotNull);
      expect(chromeData!.size, 17);

      final negData = await manager.getLutData('classic_neg');
      expect(negData, isNotNull);

      final airyData = await manager.getLutData('japanese_airy');
      expect(airyData, isNotNull);

      final acrosData = await manager.getLutData('bw_acros');
      expect(acrosData, isNotNull);

      // Test importing custom .cube file
      final customSourceFile = File('${tempDir.path}/source_portra.cube');
      await customSourceFile.writeAsString(
        _buildSyntheticCubeString(17, title: 'Portra 400 Custom'),
      );

      final imported = await manager.importCustomCubeFile(customSourceFile);
      expect(imported.isCustom, isTrue);
      expect(imported.name, 'Portra 400 Custom');
      expect(
        manager.allPresets.any((p) => p.id == imported.id),
        isTrue,
      );

      final loadedCustom = await manager.getLutData(imported.id);
      expect(loadedCustom, isNotNull);
      expect(loadedCustom!.title, 'Portra 400 Custom');

      await tempDir.delete(recursive: true);
    });
  });

  group('Issue #2.3 — Background LutBakerService & EXIF Preservation Tests',
      () {
    test('bakes LUT into JPEG in background isolate and preserves EXIF APP1',
        () async {
      final sourceImg = img.Image(width: 400, height: 300);
      for (int y = 0; y < 300; y++) {
        for (int x = 0; x < 400; x++) {
          sourceImg.setPixelRgb(x, y, 100, 120, 150);
        }
      }
      final rawJpeg = Uint8List.fromList(img.encodeJpg(sourceImg, quality: 92));
      final jpegWithExif = _injectTestExifApp1(rawJpeg);

      final lutData = CubeLutParser.parse(
        _buildSyntheticCubeString(17, title: 'WarmBake'),
      );

      const baker = LutBakerService();
      final sw = Stopwatch()..start();
      final bakedBytes = await baker.bakeBytes(
        sourceJpegBytes: jpegWithExif,
        lutData: lutData,
        intensity: 1.0,
        jpegQuality: 93,
      );
      sw.stop();

      // Verify baking speed (< 1000ms)
      expect(sw.elapsedMilliseconds, lessThan(1000));

      // Verify SOI (0xFFD8) followed immediately by preserved APP1 (0xFFE1) EXIF header
      expect(bakedBytes[0], 0xFF);
      expect(bakedBytes[1], 0xD8);
      expect(bakedBytes[2], 0xFF);
      expect(bakedBytes[3], 0xE1);

      // Verify baked pixel color changed according to LUT
      final bakedDecoded = img.decodeJpg(bakedBytes);
      expect(bakedDecoded, isNotNull);
      final centerPixel = bakedDecoded!.getPixel(200, 150);
      // Warm LUT boosts red (> 100) and lowers blue (< 150)
      expect(centerPixel.r, greaterThan(102));
      expect(centerPixel.b, lessThan(145));

      // Verify Histogram changes dynamically when LUT is applied vs original (Fix #2.4 / Issue #29)
      final origHist = await HistogramCalculator.computeFromBytes(rawJpeg);
      final lutHist = await HistogramCalculator.computeFromBytes(
        rawJpeg,
        lutData: lutData,
        lutIntensity: 1.0,
      );
      expect(lutHist.red, isNot(equals(origHist.red)));
      expect(lutHist.blue, isNot(equals(origHist.blue)));
    });
  });
}

