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

  final String driverId; // 'canon_usb', 'canon_wifi', or 'fuji_wifi'
  final String _driverName;
  final CameraConnectionType _connectionType;

  final StreamController<CameraConnectionState> _connectionController =
      StreamController<CameraConnectionState>.broadcast();
  final StreamController<IncomingPhoto> _photoController =
      StreamController<IncomingPhoto>.broadcast();
  final StreamController<LiveViewStatus> _liveViewStatusController =
      StreamController<LiveViewStatus>.broadcast();
  final StreamController<Uint8List> _liveViewFrameController =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  CameraConnectionState _state = CameraConnectionState.disconnected;

  bool _isLiveViewActive = false;
  bool _wasInLiveView = false;
  bool _isLiveViewReconnecting = false;
  Timer? _reconnectTimeoutTimer;

  bool _intentionalDisconnect = false;
  Timer? _autoReconnectTimer;
  String? _lastIpAddress;
  int? _lastPort;

  bool get isAutoReconnectScheduled => _autoReconnectTimer?.isActive ?? false;

  CanonNativeCameraDriver({
    required this.driverId,
    String? driverName,
    CameraConnectionType? connectionType,
  })  : _driverName = driverName ??
            (driverId == 'canon_usb'
                ? 'Canon EOS (Wired USB-OTG)'
                : driverId == 'fuji_wifi'
                    ? 'Fujifilm X-T10 (Wi-Fi PTP/IP)'
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
            if ((newState == CameraConnectionState.disconnected ||
                    newState == CameraConnectionState.error) &&
                !_intentionalDisconnect &&
                _connectionType == CameraConnectionType.wifi) {
              _scheduleAutoReconnect();
            } else if (newState == CameraConnectionState.connected) {
              _autoReconnectTimer?.cancel();
            }
          } else if (type == 'photoAdded' && data is Map) {
            _handleIncomingNativePhoto(data);
          } else if (type == 'liveViewStatus') {
            final statusStr = (data is Map ? data['status'] : data)?.toString();
            final newStatus = switch (statusStr) {
              'active' => LiveViewStatus.active,
              'reconnecting' => LiveViewStatus.reconnecting,
              _ => LiveViewStatus.inactive,
            };
            _isLiveViewActive = newStatus == LiveViewStatus.active;
            _isLiveViewReconnecting = newStatus == LiveViewStatus.reconnecting;
            if (!_liveViewStatusController.isClosed) {
              _liveViewStatusController.add(newStatus);
            }
          } else if (type == 'liveViewFrame' && data is Uint8List) {
            if (!_liveViewFrameController.isClosed) {
              _liveViewFrameController.add(data);
            }
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
          'photo_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = map['fileName']?.toString() ?? 'IMG_0001.JPG';
      Uint8List? previewBytes = map['previewBytes'] as Uint8List?;
      final fullResLocalPath = map['fullResLocalPath']?.toString();
      final capturedAtMs = map['capturedAt'] as int?;
      final capturedAt = capturedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(capturedAtMs)
          : DateTime.now();
      final exif = Map<String, dynamic>.from(
        (map['exif'] as Map?) ?? <String, dynamic>{},
      );

      // If previewBytes is missing but fullResLocalPath is available on disk, load directly!
      if ((previewBytes == null || previewBytes.isEmpty) &&
          fullResLocalPath != null) {
        final f = File(fullResLocalPath);
        if (f.existsSync()) {
          try {
            previewBytes = f.readAsBytesSync();
          } catch (_) {}
        }
      }

      final photo = IncomingPhoto(
        id: id,
        fileName: fileName,
        previewBytes: previewBytes,
        fullResLocalPath: fullResLocalPath,
        exifData: exif,
        capturedAt: capturedAt,
      );

      if (!_photoController.isClosed) {
        _photoController.add(photo);
      }

      // Check if camera was in Live View before capture: auto-restart EVF after buffer delay
      if (_wasInLiveView) {
        _wasInLiveView = false;
        Future.delayed(const Duration(milliseconds: 400), () async {
          _reconnectTimeoutTimer?.cancel();
          await startLiveView();
        });
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
    _intentionalDisconnect = false;
    _lastIpAddress = ipAddress;
    _lastPort = port;
    _autoReconnectTimer?.cancel();

    _state = CameraConnectionState.connecting;
    if (!_connectionController.isClosed) {
      _connectionController.add(CameraConnectionState.connecting);
    }
    try {
      final defaultIp = (driverId == 'fuji_wifi') ? '192.168.0.1' : '192.168.1.1';
      final defaultPort = 15740;

      final ok = await _methodChannel.invokeMethod<bool>('connectCamera', {
        'driverType': driverId,
        'ipAddress': ipAddress ?? defaultIp,
        'port': port ?? defaultPort,
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
    _intentionalDisconnect = true;
    _autoReconnectTimer?.cancel();
    try {
      await _methodChannel.invokeMethod('disconnectCamera');
    } catch (_) {}
    _state = CameraConnectionState.disconnected;
    if (!_connectionController.isClosed) {
      _connectionController.add(CameraConnectionState.disconnected);
    }
  }

  void _scheduleAutoReconnect() {
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (!_intentionalDisconnect &&
          _state != CameraConnectionState.connected &&
          _state != CameraConnectionState.connecting) {
        await connect(ipAddress: _lastIpAddress, port: _lastPort);
      }
    });
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

  @override
  Stream<LiveViewStatus> get liveViewStatusStream =>
      _liveViewStatusController.stream;

  @override
  Stream<Uint8List> get liveViewFrameStream => _liveViewFrameController.stream;

  @override
  bool get isLiveViewActive => _isLiveViewActive;

  @override
  bool get isLiveViewReconnecting => _isLiveViewReconnecting;

  @override
  Future<bool> startLiveView() async {
    try {
      final ok =
          await _methodChannel.invokeMethod<bool>('startLiveView') ?? false;
      if (ok) {
        _isLiveViewActive = true;
        _wasInLiveView = false;
        _isLiveViewReconnecting = false;
        if (!_liveViewStatusController.isClosed) {
          _liveViewStatusController.add(LiveViewStatus.active);
        }
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopLiveView() async {
    try {
      final ok =
          await _methodChannel.invokeMethod<bool>('stopLiveView') ?? false;
      _isLiveViewActive = false;
      _wasInLiveView = false;
      _isLiveViewReconnecting = false;
      if (!_liveViewStatusController.isClosed) {
        _liveViewStatusController.add(LiveViewStatus.inactive);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> triggerCapture() async {
    // 1. Record whether camera was in Live View mode prior to capture command
    _wasInLiveView = _isLiveViewActive;
    if (_wasInLiveView) {
      _isLiveViewReconnecting = true;
      if (!_liveViewStatusController.isClosed) {
        _liveViewStatusController.add(LiveViewStatus.reconnecting);
      }
      // Safety timeout: if camera is stuck in review mode or buffer delayed > 2.5s, auto-cancel loading
      _reconnectTimeoutTimer?.cancel();
      _reconnectTimeoutTimer = Timer(const Duration(milliseconds: 2500), () {
        if (_isLiveViewReconnecting) {
          _isLiveViewReconnecting = false;
          _wasInLiveView = false;
          if (!_liveViewStatusController.isClosed) {
            _liveViewStatusController.add(LiveViewStatus.inactive);
          }
        }
      });
    }

    try {
      final ok =
          await _methodChannel.invokeMethod<bool>('triggerCapture') ?? false;
      return ok;
    } catch (_) {
      _reconnectTimeoutTimer?.cancel();
      _isLiveViewReconnecting = false;
      _wasInLiveView = false;
      return false;
    }
  }

  @override
  Future<int> rescanCameraPhotos() async {
    try {
      final count =
          await _methodChannel.invokeMethod<int>('rescanCameraPhotos');
      return count ?? 0;
    } catch (_) {
      return 0;
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
      CameraDriverInfo(
        id: 'fuji_wifi',
        name: 'Fujifilm X-T10 (Wi-Fi PTP/IP)',
        type: CameraDriverType.wifi,
        isAvailable: true,
      ),
    ];
  }

  void dispose() {
    _eventSubscription?.cancel();
    _connectionController.close();
    _photoController.close();
    _liveViewStatusController.close();
    _liveViewFrameController.close();
  }
}
