import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/camera_types.dart';

class CanonNativeCameraDriver implements BaseCameraDriver {
  static const MethodChannel _methodChannel =
      MethodChannel('com.photoezi/camera_control');
  static const EventChannel _eventChannel =
      EventChannel('com.photoezi/camera_events');

  final String driverId; // 'canon_usb' or 'canon_wifi'
  final String _driverName;
  final CameraConnectionType _connectionType;

  final StreamController<CameraConnectionState> _connectionController =
      StreamController<CameraConnectionState>.broadcast();
  final StreamController<IncomingPhoto> _photoController =
      StreamController<IncomingPhoto>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  CameraConnectionState _state = CameraConnectionState.disconnected;

  CanonNativeCameraDriver({
    required this.driverId,
    String? driverName,
    CameraConnectionType? connectionType,
  })  : _driverName = driverName ??
            (driverId == 'canon_usb'
                ? 'Canon EOS (Wired USB-OTG)'
                : 'Canon EOS (Wi-Fi PTP/IP)'),
        _connectionType = connectionType ??
            (driverId == 'canon_usb'
                ? CameraConnectionType.usb
                : CameraConnectionType.wifi) {
    _initEventSubscription();
  }

  void _initEventSubscription() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final type = event['type']?.toString();
          final data = event['data'];
          if (type == 'connectionStateChanged') {
            final stateStr = data?.toString();
            final newState = switch (stateStr) {
              'connected' => CameraConnectionState.connected,
              'connecting' => CameraConnectionState.connecting,
              'error' => CameraConnectionState.error,
              _ => CameraConnectionState.disconnected,
            };
            _state = newState;
            if (!_connectionController.isClosed) {
              _connectionController.add(newState);
            }
          } else if (type == 'photoAdded' && data is Map) {
            _handleIncomingNativePhoto(data);
          }
        }
      },
      onError: (dynamic error) {
        _state = CameraConnectionState.error;
        if (!_connectionController.isClosed) {
          _connectionController.add(CameraConnectionState.error);
        }
      },
    );
  }

  void _handleIncomingNativePhoto(Map<dynamic, dynamic> map) {
    try {
      final id = map['id']?.toString() ??
          'canon_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = map['fileName']?.toString() ?? 'IMG_0001.JPG';
      final previewBytes = map['previewBytes'] as Uint8List?;
      final capturedAtMs = map['capturedAt'] as int?;
      final capturedAt = capturedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(capturedAtMs)
          : DateTime.now();
      final exif = Map<String, dynamic>.from(
        (map['exif'] as Map?) ?? <String, dynamic>{},
      );

      final photo = IncomingPhoto(
        id: id,
        fileName: fileName,
        previewBytes: previewBytes,
        fullResLocalPath: null,
        exifData: exif,
        capturedAt: capturedAt,
      );

      if (!_photoController.isClosed) {
        _photoController.add(photo);
      }
    } catch (_) {}
  }

  CameraConnectionState get currentState => _state;

  @override
  String get driverName => _driverName;

  @override
  CameraConnectionType get connectionType => _connectionType;

  @override
  Stream<CameraConnectionState> get connectionStateStream =>
      _connectionController.stream;

  @override
  Stream<IncomingPhoto> get onNewPhotoStream => _photoController.stream;

  @override
  Future<bool> connect({String? ipAddress, int? port}) async {
    _state = CameraConnectionState.connecting;
    if (!_connectionController.isClosed) {
      _connectionController.add(CameraConnectionState.connecting);
    }
    try {
      final ok = await _methodChannel.invokeMethod<bool>('connectCamera', {
        'driverType': driverId,
        'ipAddress': ipAddress ?? '192.168.1.1',
        'port': port ?? 15740,
      });
      if (ok != true) {
        _state = CameraConnectionState.disconnected;
        if (!_connectionController.isClosed) {
          _connectionController.add(CameraConnectionState.disconnected);
        }
        return false;
      }
      return true;
    } catch (e) {
      _state = CameraConnectionState.error;
      if (!_connectionController.isClosed) {
        _connectionController.add(CameraConnectionState.error);
      }
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _methodChannel.invokeMethod('disconnectCamera');
    } catch (_) {}
    _state = CameraConnectionState.disconnected;
    if (!_connectionController.isClosed) {
      _connectionController.add(CameraConnectionState.disconnected);
    }
  }

  @override
  Future<String> downloadFullResolution(
      String photoId, String targetDir) async {
    final targetPath = '$targetDir/$photoId.jpg';
    try {
      final downloadedPath = await _methodChannel
          .invokeMethod<String>('downloadFullResolution', {
        'photoId': photoId,
        'targetPath': targetPath,
      });
      return downloadedPath ?? targetPath;
    } catch (e) {
      // Fallback empty file if not yet retrieved
      final file = File(targetPath);
      if (!file.existsSync()) {
        await file.create(recursive: true);
      }
      return targetPath;
    }
  }

  static Future<List<CameraDriverInfo>> getAvailableDrivers() async {
    try {
      final result = await _methodChannel
          .invokeListMethod<Map<dynamic, dynamic>>('getAvailableDrivers');
      if (result != null) {
        return result.map(CameraDriverInfo.fromMap).toList();
      }
    } catch (_) {}

    return const [
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
        isAvailable: false,
      ),
      CameraDriverInfo(
        id: 'canon_wifi',
        name: 'Canon EOS (Wi-Fi PTP/IP)',
        type: CameraDriverType.wifi,
        isAvailable: true,
      ),
    ];
  }

  void dispose() {
    _eventSubscription?.cancel();
    _connectionController.close();
    _photoController.close();
  }
}
