import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoe_zi/features/camera/data/camera_driver_manager.dart';
import 'package:photoe_zi/features/camera/data/mock_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/camera_types.dart';
import 'package:photoe_zi/features/camera/presentation/camera_connection_modal.dart';
import 'package:photoe_zi/features/sync/data/dual_network_service.dart';
import 'package:photoe_zi/features/tether/data/photo_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Camera Bridge & Driver Management (Epics #4 & #5)', () {
    test('CameraDriverInfo maps correctly from native payload', () {
      final infoUsb = CameraDriverInfo.fromMap({
        'id': 'canon_usb',
        'name': 'Canon EOS 6D (USB)',
        'type': 'usb',
        'isAvailable': true,
      });
      expect(infoUsb.id, 'canon_usb');
      expect(infoUsb.name, 'Canon EOS 6D (USB)');
      expect(infoUsb.type, CameraDriverType.usb);
      expect(infoUsb.isAvailable, true);

      final infoFuji = CameraDriverInfo.fromMap({
        'id': 'fuji_wifi',
        'name': 'Fujifilm X-T10 (Wi-Fi PTP/IP)',
        'type': 'wifi',
        'isAvailable': true,
      });
      expect(infoFuji.id, 'fuji_wifi');
      expect(infoFuji.type, CameraDriverType.wifi);
      expect(infoFuji.isAvailable, true);
    });

    test('CameraDriverManager switches between Mock, Canon, and Fuji drivers', () async {
      final manager = CameraDriverManager();
      expect(manager.currentDriverId, 'mock');

      // Switch to Fuji Wi-Fi without auto-connecting
      await manager.switchDriver('fuji_wifi', autoConnect: false);
      expect(manager.currentDriverId, 'fuji_wifi');
      expect(manager.driverName, 'Fujifilm X-T10 (Wi-Fi PTP/IP)');
      expect(manager.connectionType, CameraConnectionType.wifi);

      // Switch to Canon USB
      await manager.switchDriver('canon_usb', autoConnect: false);
      expect(manager.currentDriverId, 'canon_usb');
      expect(manager.driverName, 'Canon EOS (Wired USB-OTG)');
      expect(manager.connectionType, CameraConnectionType.usb);

      // Switch back to Mock
      await manager.switchDriver('mock', autoConnect: false);
      expect(manager.currentDriverId, 'mock');

      manager.dispose();
    });
  });

  group('Dual-Network Service (Epic #6.2)', () {
    test('DualNetworkStatus correctly parses network state', () {
      final status = DualNetworkStatus.fromMap({
        'isWifiActive': true,
        'isCellularActive': true,
        'isDualNetworkActive': true,
        'statusDescription': 'Dual-Network Active: Camera Wi-Fi + Cellular Cloud Sync',
      });

      expect(status.isWifiActive, true);
      expect(status.isCellularActive, true);
      expect(status.isDualNetworkActive, true);
      expect(status.statusDescription, contains('Dual-Network Active'));
    });
  });

  group('Memory Hardening & Photo Cache LRU Eviction (Epic #6.1)', () {
    test('Stress test: 100 rapid simulated photos stays within LRU memory bounds', () async {
      final tempDir = await Directory.systemTemp.createTemp('photoe_cache_test_');
      final cacheManager = PhotoCacheManager(
        maxMemoryEntries: 15, // limit to 15 in RAM
        cacheDir: tempDir,
      );

      // Simulate 100 photos arriving in rapid succession
      for (int i = 1; i <= 100; i++) {
        final dummyBytes = Uint8List.fromList(List<int>.generate(2048, (idx) => (i + idx) % 256));
        final photo = IncomingPhoto(
          id: 'photo_$i',
          fileName: 'IMG_${1000 + i}.JPG',
          previewBytes: dummyBytes,
          fullResLocalPath: null,
          exifData: {'iso': 400},
          capturedAt: DateTime.now(),
        );

        cacheManager.addPhoto(photo);
      }

      // Verify that total tracked metadata is 100
      expect(cacheManager.totalTrackedPhotos, 100);

      // Verify that memory RAM cache is strictly bounded by maxMemoryEntries
      expect(cacheManager.cachedMemoryCount, lessThanOrEqualTo(15));

      // Test retrieving an older photo that was evicted to disk
      final olderBytes = await cacheManager.getPreviewBytes('photo_5');
      expect(olderBytes, isNotNull);
      expect(olderBytes!.length, 2048);

      // Clean up temp test directory
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
  });

  group('Camera Connection Modal UI', () {
    testWidgets('Displays all drivers including Canon and Fujifilm X-T10', (tester) async {
      String? selectedDriver;
      String? selectedIp;
      int? selectedPort;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraConnectionModal(
              activeDriverId: 'mock',
              connectionState: CameraConnectionState.disconnected,
              currentDriverName: 'Mock Camera Simulator',
              onGetAvailableDrivers: () async => const [
                CameraDriverInfo(
                  id: 'mock',
                  name: 'Mock Camera Simulator',
                  type: CameraDriverType.mock,
                  isAvailable: true,
                ),
                CameraDriverInfo(
                  id: 'canon_usb',
                  name: 'Canon EOS (Wired USB-OTG)',
                  type: CameraDriverType.usb,
                  isAvailable: true,
                ),
                CameraDriverInfo(
                  id: 'canon_wifi',
                  name: 'Canon EOS (Wi-Fi PTP/IP)',
                  type: CameraDriverType.wifi,
                  isAvailable: true,
                ),
                CameraDriverInfo(
                  id: 'fuji_wifi',
                  name: 'Fujifilm X-T10 (Wi-Fi PTP/IP)',
                  type: CameraDriverType.wifi,
                  isAvailable: true,
                ),
              ],
              onSelectAndConnect: (driverId, {ipAddress, port}) async {
                selectedDriver = driverId;
                selectedIp = ipAddress;
                selectedPort = port;
              },
              onDisconnect: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Camera Connection & Tethering'), findsOneWidget);
      expect(find.byKey(const Key('camera_driver_option_canon_usb')), findsOneWidget);
      expect(find.byKey(const Key('camera_driver_option_canon_wifi')), findsOneWidget);
      expect(find.byKey(const Key('camera_driver_option_fuji_wifi')), findsOneWidget);
      expect(find.byKey(const Key('camera_driver_option_mock')), findsOneWidget);

      // Tap Fuji Wi-Fi option
      await tester.tap(find.byKey(const Key('camera_driver_option_fuji_wifi')));
      await tester.pumpAndSettle();

      // IP input should auto-default to Fujifilm gateway 192.168.0.1 and port 55740
      expect(find.text('192.168.0.1'), findsOneWidget);
      expect(find.text('55740'), findsOneWidget);

      // Confirm connect button
      await tester.ensureVisible(find.byKey(const Key('btn_confirm_camera_connection')));
      await tester.tap(find.byKey(const Key('btn_confirm_camera_connection')));
      await tester.pumpAndSettle();

      expect(selectedDriver, 'fuji_wifi');
      expect(selectedIp, '192.168.0.1');
      expect(selectedPort, 55740);
    });

    test('Live View EVF Auto-Restart: preserves wasInLiveView and restarts after buffer delay', () async {
      final mockDriver = MockCameraDriver();
      await mockDriver.connect();

      expect(mockDriver.isLiveViewActive, false);
      expect(mockDriver.isLiveViewReconnecting, false);

      // 1. Start Live View
      await mockDriver.startLiveView();
      expect(mockDriver.isLiveViewActive, true);

      // Track status transitions
      final statuses = <LiveViewStatus>[];
      final sub = mockDriver.liveViewStatusStream.listen(statuses.add);

      // 2. Trigger capture while in Live View
      final captureFuture = mockDriver.triggerCapture();
      expect(mockDriver.isLiveViewReconnecting, true);

      await captureFuture;

      // 3. Wait for photo capture + 400ms buffer clearance delay
      await Future<void>.delayed(const Duration(milliseconds: 650));

      // 4. Live View should be automatically restarted!
      expect(mockDriver.isLiveViewActive, true);
      expect(mockDriver.isLiveViewReconnecting, false);
      expect(statuses, contains(LiveViewStatus.reconnecting));
      expect(statuses.last, LiveViewStatus.active);

      await sub.cancel();
      mockDriver.dispose();
    });
  });
}
