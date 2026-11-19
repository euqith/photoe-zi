import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/camera/data/mock_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/tether_view/presentation/tether_workspace_controller.dart';
import 'package:photoe_zi/main.dart';

void main() {
  group('Issue #1.3 — MockCameraDriver Tests', () {
    test('emits connection states and two-stage preview -> full-res photos',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mock_cam_test_');
      final driver = MockCameraDriver(
        captureInterval: const Duration(seconds: 10),
        fullResDelay: const Duration(milliseconds: 80),
        storageDirProvider: () async => tempDir,
      );

      final states = <CameraConnectionState>[];
      final photos = <IncomingPhoto>[];

      final stateSub = driver.connectionStateStream.listen(states.add);
      final photoSub = driver.onNewPhotoStream.listen(photos.add);

      final connected = await driver.connect();
      expect(connected, isTrue);

      // Wait for stage 1 (preview) and stage 2 (full-res)
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(
        states,
        containsAllInOrder([
          CameraConnectionState.connecting,
          CameraConnectionState.connected,
        ]),
      );
      expect(photos.length, greaterThanOrEqualTo(2));
      expect(photos.first.previewBytes, isNotNull);
      expect(photos.first.fullResLocalPath, isNull);
      expect(photos.last.fullResLocalPath, isNotNull);
      expect(File(photos.last.fullResLocalPath!).existsSync(), isTrue);

      await driver.disconnect();
      expect(states.last, CameraConnectionState.disconnected);

      await stateSub.cancel();
      await photoSub.cancel();
      driver.dispose();
      await tempDir.delete(recursive: true);
    });
  });

  group('Issue #1.5 — EXIF & Background Isolate RGB Histogram Tests', () {
    test('parses EXIF summary and computes 64-bin RGB histogram', () async {
      final exif = ExifSummary.fromMap({
        'cameraModel': 'Canon EOS 6D',
        'aperture': 'f/1.8',
        'shutterSpeed': '1/250s',
        'iso': 200,
        'focalLength': '50mm',
      });
      expect(exif.oneLineSummary, 'f/1.8 · 1/250s · ISO 200');

      final driver = MockCameraDriver();
      final tempDir = await Directory.systemTemp.createTemp('hist_test_');
      final samplePath =
          await driver.downloadFullResolution('sample_1', tempDir.path);

      final histogram =
          await HistogramCalculator.computeFromFilePath(samplePath);
      expect(histogram.red.length, 64);
      expect(histogram.green.length, 64);
      expect(histogram.blue.length, 64);
      expect(histogram.luminance.length, 64);
      expect(histogram.luminance.any((v) => v > 0), isTrue);

      driver.dispose();
      await tempDir.delete(recursive: true);
    });
  });

  group('Issue #1.1 & #1.4 — Pro Tether Workspace UI Tests', () {
    testWidgets(
        'renders Neutral Dark Studio Theme, Landscape Inspector, and Portrait Bottom Sheet',
        (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final driver = MockCameraDriver(
        captureInterval: const Duration(seconds: 60),
      );

      // Set tablet landscape dimensions (1200 x 800)
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            cameraDriverProvider.overrideWithValue(driver),
          ],
          child: const PhotoEZiApp(),
        ),
      );
      await tester.pump();

      // Verify Neutral Dark Studio Theme
      final materialApp =
          tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        materialApp.theme?.scaffoldBackgroundColor,
        StudioColors.canvasBackground,
      );

      // Verify Right Inspector Panel is visible on Landscape/Tablet
      expect(find.byKey(const Key('right_inspector_panel')), findsOneWidget);
      expect(find.text('HISTOGRAM (RGB)'), findsOneWidget);
      expect(find.text('FILM SIMULATION'), findsOneWidget);
      expect(find.text('INFO & EXIF'), findsOneWidget);

      // Test Zen Mode hides Right Inspector
      await tester.tap(find.byKey(const Key('btn_zen_mode_toggle')));
      await tester.pump();
      expect(find.byKey(const Key('right_inspector_panel')), findsNothing);

      // Disable Zen Mode
      await tester.tap(find.byKey(const Key('btn_zen_mode_toggle')));
      await tester.pump();
      expect(find.byKey(const Key('right_inspector_panel')), findsOneWidget);

      // Switch to Smartphone Portrait layout (390 x 844)
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();

      // Right Inspector switches to Draggable Bottom Sheet
      expect(find.byKey(const Key('right_inspector_panel')), findsNothing);
      expect(
        find.byKey(const Key('portrait_inspector_bottom_sheet')),
        findsOneWidget,
      );

      await db.close();
      driver.dispose();
    });
  });
}
