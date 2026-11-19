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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioColors.panelElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: StudioColors.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account & Settings Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isSignedIn
                          ? Icons.verified_user_outlined
                          : Icons.account_circle_outlined,
                      size: 14,
                      color: isSignedIn
                          ? StudioColors.statusSuccess
                          : StudioColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        isSignedIn
                            ? (userEmail ?? 'Connected')
                            : 'Not Signed In',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: StudioColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                key: const Key('btn_open_drive_settings'),
                onTap: onOpenDriveSettings,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSignedIn
                        ? StudioColors.canvasBackground
                        : StudioColors.accentAmber.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: StudioColors.accentAmber),
                  ),
                  child: Text(
                    isSignedIn ? 'Drive Settings' : 'Sign In & Link',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: StudioColors.accentAmber,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Active Session Folder Path
          Text(
            'Folder: $sessionFolderPath',
            style: const TextStyle(
              fontSize: 10,
              color: StudioColors.textSecondary,
              fontFamily: StudioTheme.monospaceFont,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: StudioColors.panelBorder),
          ),

          // Auto-Upload Trigger Mode Selector (Issue #3.3)
          const Text(
            'AUTO-UPLOAD MODE',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: StudioColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: _modeChip(
                  key: const Key('upload_mode_all'),
                  label: 'All',
                  isSelected: autoUploadMode == AutoUploadMode.all,
                  onTap: () => onAutoUploadModeChanged(AutoUploadMode.all),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _modeChip(
                  key: const Key('upload_mode_favorites'),
                  label: '♥ Fav Only',
                  isSelected: autoUploadMode == AutoUploadMode.favoritesOnly,
                  onTap: () =>
                      onAutoUploadModeChanged(AutoUploadMode.favoritesOnly),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _modeChip(
                  key: const Key('upload_mode_manual'),
                  label: 'Manual',
                  isSelected: autoUploadMode == AutoUploadMode.manual,
                  onTap: () => onAutoUploadModeChanged(AutoUploadMode.manual),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // File Variant Selector (Issue #3.3)
          const Text(
            'FILE VARIANT',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: StudioColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: _modeChip(
                  key: const Key('variant_baked'),
                  label: 'Baked LUT',
                  isSelected: uploadVariant == UploadVariant.bakedLut,
                  onTap: () => onUploadVariantChanged(UploadVariant.bakedLut),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _modeChip(
                  key: const Key('variant_original'),
                  label: 'Original',
                  isSelected: uploadVariant == UploadVariant.original,
                  onTap: () => onUploadVariantChanged(UploadVariant.original),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _modeChip(
                  key: const Key('variant_both'),
                  label: 'Both (/Ed+/Or)',
                  isSelected: uploadVariant == UploadVariant.both,
                  onTap: () => onUploadVariantChanged(UploadVariant.both),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
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
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isOffline
                        ? StudioColors.statusWarning.withValues(alpha: 0.18)
                        : StudioColors.statusSuccess.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(3),
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

          if (failedCount > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 26,
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

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 28,
            child: ElevatedButton.icon(
              key: const Key('btn_inspector_qr_share'),
              onPressed: onShowQrModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: StudioColors.accentAmber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.qr_code_2_rounded, size: 14),
              label: const Text(
                'Share Session QR Code',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? StudioColors.accentAmber.withValues(alpha: 0.18)
              : StudioColors.canvasBackground,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color:
                isSelected ? StudioColors.accentAmber : StudioColors.panelBorder,
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
    return AlertDialog(
      backgroundColor: StudioColors.panelSurface,
      title: Row(
        children: [
          const Icon(
            Icons.qr_code_2_rounded,
            color: StudioColors.accentAmber,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Instant Client Share: $sessionName',
              style: const TextStyle(
                color: StudioColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: StudioColors.statusSuccess.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: StudioColors.statusSuccess),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.public_rounded,
                    size: 14,
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: shareableUrl,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StudioColors.canvasBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: StudioColors.panelBorder),
              ),
              child: SelectableText(
                shareableUrl,
                style: const TextStyle(
                  color: StudioColors.textSecondary,
                  fontSize: 10.5,
                  fontFamily: StudioTheme.monospaceFont,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onEditDriveLink();
          },
          child: const Text('Change Drive Link'),
        ),
        ElevatedButton.icon(
          key: const Key('btn_copy_share_link'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: shareableUrl));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Google Drive folder link copied to clipboard!'),
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioColors.accentAmber,
            foregroundColor: Colors.black,
          ),
          icon: const Icon(Icons.copy_rounded, size: 14),
          label: const Text('Copy Link'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
