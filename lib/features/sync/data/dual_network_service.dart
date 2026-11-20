import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DualNetworkStatus {
  final bool isWifiActive;
  final bool isCellularActive;
  final bool isDualNetworkActive;
  final String statusDescription;

  const DualNetworkStatus({
    this.isWifiActive = false,
    this.isCellularActive = false,
    this.isDualNetworkActive = false,
    this.statusDescription = 'Standard Network',
  });

  factory DualNetworkStatus.fromMap(Map<dynamic, dynamic> map) {
    return DualNetworkStatus(
      isWifiActive: map['isWifiActive'] == true,
      isCellularActive: map['isCellularActive'] == true,
      isDualNetworkActive: map['isDualNetworkActive'] == true,
      statusDescription: map['statusDescription']?.toString() ?? 'Standard Network',
    );
  }
}

class DualNetworkService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.photoezi/camera_control');
  static const EventChannel _eventChannel =
      EventChannel('com.photoezi/camera_events');

  final StreamController<DualNetworkStatus> _statusController =
      StreamController<DualNetworkStatus>.broadcast();
  StreamSubscription<dynamic>? _sub;

  DualNetworkService() {
    _initListener();
  }

  void _initListener() {
    _sub = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map && event['type'] == 'networkStatusChanged' && event['data'] is Map) {
        _statusController.add(DualNetworkStatus.fromMap(event['data'] as Map));
      }
    }, onError: (_) {});
  }

  Stream<DualNetworkStatus> get statusStream => _statusController.stream;

  Future<DualNetworkStatus> getNetworkStatus() async {
    try {
      final res = await _methodChannel.invokeMapMethod<dynamic, dynamic>('getNetworkStatus');
      if (res != null) {
        return DualNetworkStatus.fromMap(res);
      }
    } catch (_) {}
    return const DualNetworkStatus();
  }

  Future<void> enableCellularSync() async {
    try {
      await _methodChannel.invokeMethod('enableCellularSync');
    } catch (_) {}
  }

  Future<void> disableCellularSync() async {
    try {
      await _methodChannel.invokeMethod('disableCellularSync');
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _statusController.close();
  }
}

final dualNetworkServiceProvider = Provider<DualNetworkService>((ref) {
  final service = DualNetworkService();
  ref.onDispose(() => service.dispose());
  return service;
});

final dualNetworkStatusProvider = StreamProvider<DualNetworkStatus>((ref) {
  final service = ref.watch(dualNetworkServiceProvider);
  return service.statusStream;
});
