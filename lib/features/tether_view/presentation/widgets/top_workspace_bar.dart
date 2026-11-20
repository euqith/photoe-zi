import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/features/camera/domain/base_camera_driver.dart';

class TopWorkspaceBar extends StatelessWidget {
  final String sessionName;
  final CameraConnectionState cameraState;
  final String cameraDriverName;
  final bool isZenMode;
  final bool isBeforeAfterActive;
  final bool isRightInspectorVisible;
  final bool isLandscapeOrTablet;
  final int syncedCount;
  final int totalCount;
  final VoidCallback onToggleCamera;
  final VoidCallback? onOpenConnectionModal;
  final VoidCallback onManualMockCapture;
  final VoidCallback onToggleZenMode;
  final VoidCallback onToggleBeforeAfter;
  final VoidCallback onToggleRightInspector;
  final VoidCallback onShowSessionDialog;
  final VoidCallback onShowQrModal;
  final VoidCallback? onOpenDriveSettings;

  const TopWorkspaceBar({
    super.key,
    required this.sessionName,
    required this.cameraState,
    required this.cameraDriverName,
    required this.isZenMode,
    required this.isBeforeAfterActive,
    required this.isRightInspectorVisible,
    required this.isLandscapeOrTablet,
    required this.syncedCount,
    required this.totalCount,
    required this.onToggleCamera,
    this.onOpenConnectionModal,
    required this.onManualMockCapture,
    required this.onToggleZenMode,
    required this.onToggleBeforeAfter,
    required this.onToggleRightInspector,
    required this.onShowSessionDialog,
    required this.onShowQrModal,
    this.onOpenDriveSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = cameraState == CameraConnectionState.connected;
    final isConnecting = cameraState == CameraConnectionState.connecting;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isZenMode ? 0.55 : 1.0,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: StudioColors.panelSurface,
          border: Border(
            bottom: BorderSide(color: StudioColors.panelBorder, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Session Selector
                    InkWell(
                      key: const Key('btn_session_selector'),
                      onTap: onShowSessionDialog,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.folder_special_outlined,
                              size: 15,
                              color: StudioColors.accentAmber,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isLandscapeOrTablet
                                  ? 'Session: $sessionName'
                                  : sessionName,
                              style: const TextStyle(
                                color: StudioColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Camera Connection Pill (Tap for modal, Long-press to toggle)
                    InkWell(
                      key: const Key('btn_camera_connection_toggle'),
                      onTap: onOpenConnectionModal ?? onToggleCamera,
                      onLongPress: onToggleCamera,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isConnected
                              ? StudioColors.statusSuccess
                                  .withValues(alpha: 0.14)
                              : StudioColors.panelElevated,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isConnected
                                ? StudioColors.statusSuccess
                                : StudioColors.panelBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isConnected
                                    ? StudioColors.statusSuccess
                                    : (isConnecting
                                        ? StudioColors.accentAmber
                                        : StudioColors.textMuted),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isConnected
                                  ? (isLandscapeOrTablet
                                      ? cameraDriverName
                                      : cameraDriverName.split('(').first.trim())
                                  : (isConnecting
                                      ? 'Connecting...'
                                      : (isLandscapeOrTablet
                                          ? 'Connect Camera'
                                          : 'Offline')),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isConnected
                                    ? StudioColors.statusSuccess
                                    : StudioColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isConnected && cameraDriverName.toLowerCase().contains('wi-fi')) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF0284C7)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cell_tower_rounded, size: 12, color: Color(0xFF38BDF8)),
                            SizedBox(width: 4),
                            Text(
                              'Dual-Net',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),

                    // Manual Mock Photo Generator Button
                    InkWell(
                      key: const Key('btn_manual_mock_capture'),
                      onTap: onManualMockCapture,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              StudioColors.accentAmber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: StudioColors.accentAmber),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 13,
                              color: StudioColors.accentAmber,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '+ Mock Photo',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: StudioColors.accentAmber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 6),

            // Zen Mode 1-Tap Toggle
            _topBarButton(
              key: const Key('btn_zen_mode_toggle'),
              label: 'Zen',
              icon: Icons.fullscreen_rounded,
              isActive: isZenMode,
              onTap: onToggleZenMode,
            ),

            if (isLandscapeOrTablet) ...[
              const SizedBox(width: 6),
              _topBarButton(
                key: const Key('btn_before_after_toggle'),
                label: 'Before/After',
                icon: Icons.compare_rounded,
                isActive: isBeforeAfterActive,
                onTap: onToggleBeforeAfter,
              ),
            ],

            const SizedBox(width: 6),
            // Cloud Sync Progress Counter (Clickable -> opens Google Drive Settings & Folder Link setup)
            InkWell(
              key: const Key('btn_top_cloud_settings'),
              onTap: onOpenDriveSettings,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: StudioColors.panelElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: StudioColors.panelBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_done_outlined,
                      size: 13,
                      color: StudioColors.statusSuccess,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$syncedCount/$totalCount',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: StudioColors.textPrimary,
                        fontFamily: StudioTheme.monospaceFont,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 6),
            // QR Share Button
            _topBarButton(
              key: const Key('btn_qr_share'),
              label: 'QR',
              icon: Icons.qr_code_2_rounded,
              isActive: false,
              onTap: onShowQrModal,
            ),

            if (isLandscapeOrTablet && !isZenMode) ...[
              const SizedBox(width: 6),
              IconButton(
                key: const Key('btn_inspector_collapse'),
                tooltip: 'Toggle Right Inspector Panel',
                onPressed: onToggleRightInspector,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  isRightInspectorVisible
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  size: 18,
                  color: isRightInspectorVisible
                      ? StudioColors.accentAmber
                      : StudioColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _topBarButton({
    required Key key,
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? StudioColors.accentAmber.withValues(alpha: 0.18)
              : StudioColors.panelElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color:
                isActive ? StudioColors.accentAmber : StudioColors.panelBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color:
                  isActive ? StudioColors.accentAmber : StudioColors.textPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? StudioColors.accentAmber
                    : StudioColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
