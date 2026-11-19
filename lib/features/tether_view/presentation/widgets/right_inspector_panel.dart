import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';
import 'package:photoe_zi/features/cloud_sync/data/cloud_sync_service.dart';
import 'package:photoe_zi/features/cloud_sync/presentation/drive_sync_panel.dart';
import 'package:photoe_zi/features/film_sim/domain/lut_preset.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/exif_metadata_panel.dart';
import 'package:photoe_zi/features/tether_view/presentation/widgets/rgb_histogram_widget.dart';

class RightInspectorPanel extends StatelessWidget {
  final Photo? activePhoto;
  final RgbHistogramData histogramData;
  final bool isHistogramLoading;
  final List<LutPreset> presets;
  final String activeLutId;
  final double lutIntensity;
  final String syncStatus;
  final bool isGoogleSignedIn;
  final String? googleUserEmail;
  final String sessionFolderPath;
  final String shareableFolderUrl;
  final AutoUploadMode autoUploadMode;
  final UploadVariant uploadVariant;
  final bool isOffline;
  final int syncedCount;
  final int queuedCount;
  final int failedCount;
  final String? lastUploadError;
  final ValueChanged<String> onSelectLut;
  final ValueChanged<double> onIntensityChanged;
  final VoidCallback? onImportCube;
  final VoidCallback? onManualUpload;
  final VoidCallback onOpenDriveSettings;
  final ValueChanged<AutoUploadMode> onAutoUploadModeChanged;
  final ValueChanged<UploadVariant> onUploadVariantChanged;
  final ValueChanged<bool> onToggleOffline;
  final VoidCallback onRetryFailed;
  final VoidCallback onShowQrModal;

  const RightInspectorPanel({
    super.key,
    required this.activePhoto,
    required this.histogramData,
    required this.isHistogramLoading,
    this.presets = LutPreset.builtInPresets,
    required this.activeLutId,
    required this.lutIntensity,
    required this.syncStatus,
    this.isGoogleSignedIn = true,
    this.googleUserEmail = 'studio@photoe-zi.app',
    this.sessionFolderPath = 'TetherApp / Studio_A',
    this.shareableFolderUrl =
        'https://drive.google.com/drive/folders/1GDrive_Studio_A?usp=sharing',
    this.autoUploadMode = AutoUploadMode.all,
    this.uploadVariant = UploadVariant.bakedLut,
    this.isOffline = false,
    this.syncedCount = 0,
    this.queuedCount = 0,
    this.failedCount = 0,
    this.lastUploadError,
    required this.onSelectLut,
    required this.onIntensityChanged,
    this.onImportCube,
    this.onManualUpload,
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
      width: 280,
      decoration: const BoxDecoration(
        color: StudioColors.panelSurface,
        border: Border(
          left: BorderSide(color: StudioColors.panelBorder, width: 1),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionHeader('HISTOGRAM (RGB)'),
          const SizedBox(height: 8),
          RgbHistogramWidget(
            data: histogramData,
            isLoading: isHistogramLoading,
          ),
          const SizedBox(height: 16),
          _sectionHeader('FILM SIMULATION'),
          const SizedBox(height: 8),
          ...presets.map((preset) {
            final isSelected = preset.id == activeLutId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: InkWell(
                key: Key('lut_preset_${preset.id}'),
                onTap: () => onSelectLut(preset.id),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? StudioColors.accentAmber.withValues(alpha: 0.16)
                        : StudioColors.panelElevated,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? StudioColors.accentAmber
                          : StudioColors.panelBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? StudioColors.accentAmber
                                : StudioColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        preset.category,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: StudioColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: OutlinedButton.icon(
              key: const Key('btn_import_cube'),
              onPressed: onImportCube,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: StudioColors.panelBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              icon: const Icon(
                Icons.add_rounded,
                size: 14,
                color: StudioColors.textSecondary,
              ),
              label: const Text(
                'Import .cube',
                style: TextStyle(
                  fontSize: 11,
                  color: StudioColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Intensity',
                style: TextStyle(
                  fontSize: 11,
                  color: StudioColors.textSecondary,
                ),
              ),
              Text(
                '${(lutIntensity * 100).round()}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: StudioColors.textPrimary,
                  fontFamily: StudioTheme.monospaceFont,
                ),
              ),
            ],
          ),
          Slider(
            key: const Key('slider_lut_intensity'),
            value: lutIntensity,
            min: 0.0,
            max: 1.0,
            onChanged: onIntensityChanged,
          ),
          const SizedBox(height: 12),
          _sectionHeader('INFO & EXIF'),
          const SizedBox(height: 8),
          ExifMetadataPanel(
            photo: activePhoto,
            syncStatus: syncStatus,
            onManualUpload: onManualUpload,
          ),
          const SizedBox(height: 16),
          _sectionHeader('GOOGLE DRIVE CLOUD SYNC'),
          const SizedBox(height: 8),
          DriveSyncInspectorPanel(
            isSignedIn: isGoogleSignedIn,
            userEmail: googleUserEmail,
            sessionFolderPath: sessionFolderPath,
            shareableFolderUrl: shareableFolderUrl,
            autoUploadMode: autoUploadMode,
            uploadVariant: uploadVariant,
            isOffline: isOffline,
            syncedCount: syncedCount,
            queuedCount: queuedCount,
            failedCount: failedCount,
            lastUploadError: lastUploadError,
            onOpenDriveSettings: onOpenDriveSettings,
            onAutoUploadModeChanged: onAutoUploadModeChanged,
            onUploadVariantChanged: onUploadVariantChanged,
            onToggleOffline: onToggleOffline,
            onRetryFailed: onRetryFailed,
            onShowQrModal: onShowQrModal,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: StudioColors.textSecondary,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
