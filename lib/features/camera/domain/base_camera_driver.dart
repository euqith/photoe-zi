import 'dart:typed_data';

enum CameraConnectionType { usb, wifi, mock }

enum CameraConnectionState { disconnected, connecting, connected, error }

enum LiveViewStatus { inactive, active, reconnecting }

class IncomingPhoto {
  final String id;
  final String fileName;
  final Uint8List? previewBytes; // Fast embedded thumbnail
  final String? fullResLocalPath; // Saved full-res path
  final Map<String, dynamic> exifData;
  final DateTime capturedAt;

  const IncomingPhoto({
    required this.id,
    required this.fileName,
    this.previewBytes,
    this.fullResLocalPath,
    required this.exifData,
    required this.capturedAt,
  });

  IncomingPhoto copyWith({
    String? id,
    String? fileName,
    Uint8List? previewBytes,
    String? fullResLocalPath,
    Map<String, dynamic>? exifData,
    DateTime? capturedAt,
  }) {
    return IncomingPhoto(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      previewBytes: previewBytes ?? this.previewBytes,
      fullResLocalPath: fullResLocalPath ?? this.fullResLocalPath,
      exifData: exifData ?? this.exifData,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}

abstract class BaseCameraDriver {
  String get driverName;
  CameraConnectionType get connectionType;

  Stream<CameraConnectionState> get connectionStateStream;
  Stream<IncomingPhoto> get onNewPhotoStream;

  Stream<LiveViewStatus> get liveViewStatusStream => const Stream.empty();
  Stream<Uint8List> get liveViewFrameStream => const Stream.empty();
  bool get isLiveViewActive => false;
  bool get isLiveViewReconnecting => false;

  Future<bool> connect({String? ipAddress, int? port});
  Future<void> disconnect();
  Future<String> downloadFullResolution(String photoId, String targetDir);
  Future<int> rescanCameraPhotos() async => 0;

  Future<bool> startLiveView() async => false;
  Future<bool> stopLiveView() async => false;
  Future<bool> triggerCapture() async => false;
}

