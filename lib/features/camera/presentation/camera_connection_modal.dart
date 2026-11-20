import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';
import 'package:photoe_zi/features/camera/domain/camera_types.dart';

class CameraConnectionModal extends StatefulWidget {
  final String activeDriverId;
  final CameraConnectionState connectionState;
  final String currentDriverName;
  final Future<List<CameraDriverInfo>> Function() onGetAvailableDrivers;
  final Future<void> Function(String driverId, {String? ipAddress, int? port})
      onSelectAndConnect;
  final VoidCallback onDisconnect;
  final VoidCallback? onTriggerMockShot;

  const CameraConnectionModal({
    super.key,
    required this.activeDriverId,
    required this.connectionState,
    required this.currentDriverName,
    required this.onGetAvailableDrivers,
    required this.onSelectAndConnect,
    required this.onDisconnect,
    this.onTriggerMockShot,
  });

  @override
  State<CameraConnectionModal> createState() => _CameraConnectionModalState();
}

class _CameraConnectionModalState extends State<CameraConnectionModal> {
  late String _selectedDriverId;
  late TextEditingController _ipController;
  late TextEditingController _portController;
  List<CameraDriverInfo> _drivers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDriverId = widget.activeDriverId;
    _ipController = TextEditingController(text: '192.168.1.1');
    _portController = TextEditingController(text: '15740');
    _loadDrivers();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    final drivers = await widget.onGetAvailableDrivers();
    if (mounted) {
      setState(() {
        _drivers = drivers;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected =
        widget.connectionState == CameraConnectionState.connected;
    final isConnecting =
        widget.connectionState == CameraConnectionState.connecting;

    return Dialog(
      backgroundColor: StudioColors.panelSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: StudioColors.panelBorder),
      ),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modal Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StudioColors.accentAmber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: StudioColors.accentAmber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Camera Connection & Tethering',
                        style: TextStyle(
                          color: StudioColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Select hardware source for live photo transfer',
                        style: TextStyle(
                          color: StudioColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: StudioColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Active Connection Status Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: StudioColors.inputSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isConnected
                      ? StudioColors.statusSuccess.withValues(alpha: 0.4)
                      : isConnecting
                          ? StudioColors.accentAmber.withValues(alpha: 0.4)
                          : StudioColors.panelBorder,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? StudioColors.statusSuccess
                          : isConnecting
                              ? StudioColors.accentAmber
                              : StudioColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConnected
                          ? 'Connected: ${widget.currentDriverName}'
                          : isConnecting
                              ? 'Connecting to camera...'
                              : 'No Camera Connected',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isConnected
                            ? StudioColors.textPrimary
                            : StudioColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isConnected)
                    TextButton(
                      onPressed: () {
                        widget.onDisconnect();
                        setState(() {});
                      },
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text(
                        'Disconnect',
                        style: TextStyle(
                          fontSize: 11,
                          color: StudioColors.statusError,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'SELECT CAMERA DRIVER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: StudioColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),

            // Drivers list
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              _buildDriverOption(
                id: 'canon_usb',
                title: 'Canon EOS (Wired USB-OTG)',
                subtitle:
                    'Direct PTP connection for Canon 6D & M100 via USB cable',
                icon: Icons.usb_rounded,
                badgeText: _isDriverAvailable('canon_usb')
                    ? 'USB Detected ✓'
                    : 'Unplugged',
                badgeColor: _isDriverAvailable('canon_usb')
                    ? StudioColors.statusSuccess
                    : StudioColors.textMuted,
              ),
              const SizedBox(height: 6),
              _buildDriverOption(
                id: 'canon_wifi',
                title: 'Canon EOS (Wi-Fi PTP/IP)',
                subtitle:
                    'Connects to camera hotspot / local network (port 15740)',
                icon: Icons.wifi_rounded,
                badgeText: 'PTP/IP',
                badgeColor: StudioColors.accentAmber,
              ),
              if (_selectedDriverId == 'canon_wifi') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StudioColors.inputSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: StudioColors.panelBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _ipController,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: StudioTheme.monospaceFont,
                            color: StudioColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Camera IP',
                            labelStyle: TextStyle(fontSize: 10),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: StudioTheme.monospaceFont,
                            color: StudioColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Port',
                            labelStyle: TextStyle(fontSize: 10),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              _buildDriverOption(
                id: 'mock',
                title: 'Mock Camera Simulator',
                subtitle:
                    'Emulates Canon 6D studio shots for development & offline testing',
                icon: Icons.videogame_asset_outlined,
                badgeText: 'Simulator',
                badgeColor: StudioColors.textSecondary,
              ),
            ],

            const SizedBox(height: 18),

            // Footer Actions
            Row(
              children: [
                if (widget.onTriggerMockShot != null &&
                    _selectedDriverId == 'mock')
                  OutlinedButton.icon(
                    onPressed: () {
                      widget.onTriggerMockShot?.call();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Simulated shot captured!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.camera_alt_outlined, size: 14),
                    label: const Text(
                      'Test Shot',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  key: const Key('btn_confirm_camera_connection'),
                  onPressed: () async {
                    final ip = _ipController.text.trim();
                    final port = int.tryParse(_portController.text.trim()) ?? 15740;
                    Navigator.of(context).pop();
                    await widget.onSelectAndConnect(
                      _selectedDriverId,
                      ipAddress: ip,
                      port: port,
                    );
                  },
                  icon: const Icon(Icons.cable_rounded, size: 14),
                  label: const Text(
                    'Connect',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isDriverAvailable(String id) {
    return _drivers.any((d) => d.id == id && d.isAvailable);
  }

  Widget _buildDriverOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badgeText,
    required Color badgeColor,
  }) {
    final isSelected = _selectedDriverId == id;
    return InkWell(
      key: Key('camera_driver_option_$id'),
      onTap: () {
        setState(() {
          _selectedDriverId = id;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? StudioColors.accentAmber.withValues(alpha: 0.14)
              : StudioColors.panelElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? StudioColors.accentAmber
                : StudioColors.panelBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? StudioColors.accentAmber
                  : StudioColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected
                                ? StudioColors.accentAmber
                                : StudioColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: StudioColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
