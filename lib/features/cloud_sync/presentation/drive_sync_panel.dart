import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/features/cloud_sync/data/cloud_sync_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

class DriveSyncInspectorPanel extends StatelessWidget {
  final bool isSignedIn;
  final String? userEmail;
  final String sessionFolderPath;
  final String shareableFolderUrl;
  final AutoUploadMode autoUploadMode;
  final UploadVariant uploadVariant;
  final bool isOffline;
  final int syncedCount;
  final int queuedCount;
  final int failedCount;
  final String? lastUploadError;
  final VoidCallback onOpenDriveSettings;
  final ValueChanged<AutoUploadMode> onAutoUploadModeChanged;
  final ValueChanged<UploadVariant> onUploadVariantChanged;
  final ValueChanged<bool> onToggleOffline;
  final VoidCallback onRetryFailed;
  final VoidCallback onShowQrModal;

  const DriveSyncInspectorPanel({
    super.key,
    required this.isSignedIn,
    required this.userEmail,
    required this.sessionFolderPath,
    required this.shareableFolderUrl,
    required this.autoUploadMode,
    required this.uploadVariant,
    required this.isOffline,
    required this.syncedCount,
    required this.queuedCount,
    required this.failedCount,
    this.lastUploadError,
    required this.onOpenDriveSettings,
    required this.onAutoUploadModeChanged,
    required this.onUploadVariantChanged,
    required this.onToggleOffline,
    required this.onRetryFailed,
    required this.onShowQrModal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: StudioColors.panelElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioColors.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account & Settings Header Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: StudioColors.inputSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSignedIn
                    ? StudioColors.statusSuccess.withValues(alpha: 0.35)
                    : StudioColors.panelBorder,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSignedIn
                              ? StudioColors.statusSuccess
                              : StudioColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          isSignedIn
                              ? (userEmail ?? 'Connected')
                              : 'Not Signed In',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSignedIn
                                ? StudioColors.textPrimary
                                : StudioColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  key: const Key('btn_open_drive_settings'),
                  onTap: onOpenDriveSettings,
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSignedIn
                          ? StudioColors.panelElevated
                          : StudioColors.accentAmber,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isSignedIn
                            ? StudioColors.borderSubtle
                            : StudioColors.accentAmber,
                      ),
                    ),
                    child: Text(
                      isSignedIn ? 'Configure' : 'Connect',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSignedIn
                            ? StudioColors.textPrimary
                            : Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Active Session Folder Path
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 13,
                color: StudioColors.accentAmber,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  sessionFolderPath,
                  style: const TextStyle(
                    fontSize: 10,
                    color: StudioColors.textSecondary,
                    fontFamily: StudioTheme.monospaceFont,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Divider(height: 1, color: StudioColors.panelBorder),
          ),

          // Auto-Upload Trigger Mode Selector (Issue #3.3)
          const Text(
            'AUTO-UPLOAD TRIGGER',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: StudioColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: StudioColors.inputSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: StudioColors.panelBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _segmentedPill(
                    key: const Key('upload_mode_all'),
                    label: 'All',
                    isSelected: autoUploadMode == AutoUploadMode.all,
                    onTap: () => onAutoUploadModeChanged(AutoUploadMode.all),
                  ),
                ),
                Expanded(
                  child: _segmentedPill(
                    key: const Key('upload_mode_favorites'),
                    label: '♥ Fav',
                    isSelected: autoUploadMode == AutoUploadMode.favoritesOnly,
                    onTap: () =>
                        onAutoUploadModeChanged(AutoUploadMode.favoritesOnly),
                  ),
                ),
                Expanded(
                  child: _segmentedPill(
                    key: const Key('upload_mode_manual'),
                    label: 'Manual',
                    isSelected: autoUploadMode == AutoUploadMode.manual,
                    onTap: () => onAutoUploadModeChanged(AutoUploadMode.manual),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // File Variant Selector (Issue #3.3)
          const Text(
            'EXPORT VARIANT',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: StudioColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: StudioColors.inputSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: StudioColors.panelBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _segmentedPill(
                    key: const Key('variant_baked'),
                    label: 'Baked LUT',
                    isSelected: uploadVariant == UploadVariant.bakedLut,
                    onTap: () => onUploadVariantChanged(UploadVariant.bakedLut),
                  ),
                ),
                Expanded(
                  child: _segmentedPill(
                    key: const Key('variant_original'),
                    label: 'Original',
                    isSelected: uploadVariant == UploadVariant.original,
                    onTap: () => onUploadVariantChanged(UploadVariant.original),
                  ),
                ),
                Expanded(
                  child: _segmentedPill(
                    key: const Key('variant_both'),
                    label: 'Both',
                    isSelected: uploadVariant == UploadVariant.both,
                    onTap: () => onUploadVariantChanged(UploadVariant.both),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Divider(height: 1, color: StudioColors.panelBorder),
          ),

          // Queue Summary & Network Status (Issue #3.2)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '✓ $syncedCount · • $queuedCount · ! $failedCount',
                  style: const TextStyle(
                    fontSize: 10,
                    color: StudioColors.textPrimary,
                    fontFamily: StudioTheme.monospaceFont,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                key: const Key('toggle_offline_simulation'),
                onTap: () => onToggleOffline(!isOffline),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOffline
                        ? StudioColors.statusWarning.withValues(alpha: 0.16)
                        : StudioColors.statusSuccess.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isOffline
                          ? StudioColors.statusWarning
                          : StudioColors.statusSuccess,
                    ),
                  ),
                  child: Text(
                    isOffline ? 'Offline' : 'Online',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: isOffline
                          ? StudioColors.statusWarning
                          : StudioColors.statusSuccess,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (lastUploadError != null && lastUploadError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StudioColors.statusError.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: StudioColors.statusError.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                lastUploadError!,
                style: const TextStyle(
                  fontSize: 10,
                  color: StudioColors.statusError,
                  height: 1.35,
                ),
              ),
            ),
          ],

          if (failedCount > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 28,
              child: OutlinedButton.icon(
                key: const Key('btn_retry_failed_uploads'),
                onPressed: onRetryFailed,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: StudioColors.statusError),
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 13,
                  color: StudioColors.statusError,
                ),
                label: Text(
                  'Retry Failed ($failedCount)',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: StudioColors.statusError,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton.icon(
              key: const Key('btn_inspector_qr_share'),
              onPressed: onShowQrModal,
              icon: const Icon(Icons.qr_code_2_rounded, size: 15),
              label: const Text(
                'Client QR Share',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedPill({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? StudioColors.panelElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color:
                isSelected ? StudioColors.accentAmber : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? StudioColors.accentAmber
                : StudioColors.textSecondary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class QrShareSessionModal extends StatelessWidget {
  final String sessionName;
  final String sessionFolderPath;
  final String shareableUrl;
  final VoidCallback onEditDriveLink;

  const QrShareSessionModal({
    super.key,
    required this.sessionName,
    required this.sessionFolderPath,
    required this.shareableUrl,
    required this.onEditDriveLink,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: StudioColors.panelSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: StudioColors.panelBorder),
      ),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    Icons.qr_code_2_rounded,
                    color: StudioColors.accentAmber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Client Gallery Share · $sessionName',
                        style: const TextStyle(
                          color: StudioColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Scan QR to view & download photos immediately',
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

            // Permission Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: StudioColors.statusSuccess.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: StudioColors.statusSuccess.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.public_rounded,
                    size: 13,
                    color: StudioColors.statusSuccess,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Anyone with the link can view ✓',
                    style: TextStyle(
                      color: StudioColors.statusSuccess,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Framed QR Code Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: QrImageView(
                data: shareableUrl,
                version: QrVersions.auto,
                size: 186,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            // Folder Info Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: StudioColors.inputSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: StudioColors.panelBorder),
              ),
              child: Column(
                children: [
                  Text(
                    sessionFolderPath,
                    style: const TextStyle(
                      color: StudioColors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: StudioTheme.monospaceFont,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    shareableUrl,
                    style: const TextStyle(
                      color: StudioColors.textSecondary,
                      fontSize: 10.5,
                      fontFamily: StudioTheme.monospaceFont,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Footer Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onEditDriveLink();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit Folder Link'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('btn_copy_share_link'),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: shareableUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Google Drive folder link copied to clipboard!',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy Link'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
