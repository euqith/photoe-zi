import 'dart:async';

import 'package:photoe_zi/features/camera/data/canon_native_camera_driver.dart';
import 'package:photoe_zi/features/camera/data/mock_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/camera_types.dart';

class CameraDriverManager implements BaseCameraDriver {
  BaseCameraDriver _activeDriver;
  StreamSubscription<CameraConnectionState>? _connSub;
  StreamSubscription<IncomingPhoto>? _photoSub;

  final StreamController<CameraConnectionState> _connectionController =
      StreamController<CameraConnectionState>.broadcast();
  final StreamController<IncomingPhoto> _photoController =
      StreamController<IncomingPhoto>.broadcast();

  String _currentDriverId = 'mock';

  CameraDriverManager({BaseCameraDriver? initialDriver})
      : _activeDriver = initialDriver ?? MockCameraDriver() {
    _bindDriverStreams();
  }

  String get currentDriverId => _currentDriverId;
  BaseCameraDriver get activeDriver => _activeDriver;

  void _bindDriverStreams() {
    _connSub?.cancel();
    _photoSub?.cancel();

    _connSub = _activeDriver.connectionStateStream.listen((state) {
      if (!_connectionController.isClosed) {
        _connectionController.add(state);
      }
    });

    _photoSub = _activeDriver.onNewPhotoStream.listen((photo) {
      if (!_photoController.isClosed) {
        _photoController.add(photo);
      }
    });
  }

  Future<void> switchDriver(
    String driverId, {
    String? ipAddress,
    int? port,
    bool autoConnect = true,
  }) async {
    if (_currentDriverId == driverId) {
      if (autoConnect) {
        await connect(ipAddress: ipAddress, port: port);
      }
      return;
    }

    await _activeDriver.disconnect();

    if (driverId == 'canon_usb') {
      _activeDriver = CanonNativeCameraDriver(
        driverId: 'canon_usb',
        driverName: 'Canon EOS (Wired USB-OTG)',
        connectionType: CameraConnectionType.usb,
      );
    } else if (driverId == 'canon_wifi') {
      _activeDriver = CanonNativeCameraDriver(
        driverId: 'canon_wifi',
        driverName: 'Canon EOS (Wi-Fi PTP/IP)',
        connectionType: CameraConnectionType.wifi,
      );
    } else {
      _activeDriver = MockCameraDriver();
    }

    _currentDriverId = driverId;
    _bindDriverStreams();

    if (autoConnect) {
      await _activeDriver.connect(ipAddress: ipAddress, port: port);
    }
  }

  Future<List<CameraDriverInfo>> getAvailableDrivers() async {
    return await CanonNativeCameraDriver.getAvailableDrivers();
  }

  @override
  String get driverName => _activeDriver.driverName;

  @override
  CameraConnectionType get connectionType => _activeDriver.connectionType;

  @override
  Stream<CameraConnectionState> get connectionStateStream =>
      _connectionController.stream;

  @override
  Stream<IncomingPhoto> get onNewPhotoStream => _photoController.stream;

  @override
  Future<bool> connect({String? ipAddress, int? port}) async {
    return await _activeDriver.connect(ipAddress: ipAddress, port: port);
  }

  @override
  Future<void> disconnect() async {
    await _activeDriver.disconnect();
  }

  @override
  Future<String> downloadFullResolution(
      String photoId, String targetDir) async {
    return await _activeDriver.downloadFullResolution(photoId, targetDir);
  }

  void dispose() {
    _connSub?.cancel();
    _photoSub?.cancel();
    _connectionController.close();
    _photoController.close();
    if (_activeDriver is MockCameraDriver) {
      (_activeDriver as MockCameraDriver).dispose();
    } else if (_activeDriver is CanonNativeCameraDriver) {
      (_activeDriver as CanonNativeCameraDriver).dispose();
    }
  }
}
