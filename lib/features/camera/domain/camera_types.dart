enum CameraDriverType { mock, usb, wifi }

class CameraDriverInfo {
  final String id;
  final String name;
  final CameraDriverType type;
  final bool isAvailable;

  const CameraDriverInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.isAvailable,
  });

  factory CameraDriverInfo.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type']?.toString() ?? 'mock';
    final type = switch (typeStr) {
      'usb' => CameraDriverType.usb,
      'wifi' => CameraDriverType.wifi,
      _ => CameraDriverType.mock,
    };
    return CameraDriverInfo(
      id: map['id']?.toString() ?? 'mock',
      name: map['name']?.toString() ?? 'Mock Camera',
      type: type,
      isAvailable: map['isAvailable'] == true,
    );
  }
}
