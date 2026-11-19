import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/database/app_database.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';

class ExifMetadataPanel extends StatelessWidget {
  final Photo? photo;
  final String syncStatus;
  final VoidCallback? onManualUpload;

  const ExifMetadataPanel({
    super.key,
    required this.photo,
    this.syncStatus = 'completed',
    this.onManualUpload,
  });

  @override
  Widget build(BuildContext context) {
    if (photo == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: StudioColors.panelElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: StudioColors.panelBorder),
        ),
        child: const Text(
          'No photo selected',
          style: TextStyle(color: StudioColors.textMuted, fontSize: 12),
        ),
      );
    }

    final exif = ExifSummary.fromJsonString(photo!.exifJson);

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  photo!.fileName,
                  style: const TextStyle(
                    color: StudioColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    fontFamily: StudioTheme.monospaceFont,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: photo!.fullResPath != null
                      ? StudioColors.statusSuccess.withValues(alpha: 0.15)
                      : StudioColors.accentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  photo!.fullResPath != null ? 'FULL-RES' : 'PREVIEW',
                  style: TextStyle(
                    color: photo!.fullResPath != null
                        ? StudioColors.statusSuccess
                        : StudioColors.accentAmber,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: StudioTheme.monospaceFont,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            exif.cameraModel,
            style: const TextStyle(
              color: StudioColors.textSecondary,
              fontSize: 11,
              fontFamily: StudioTheme.monospaceFont,
            ),
          ),
          Text(
            exif.lens,
            style: const TextStyle(
              color: StudioColors.textMuted,
              fontSize: 10,
              fontFamily: StudioTheme.monospaceFont,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: StudioColors.panelBorder),
          ),
          // Monospace EXIF Grid (Aperture, Shutter, ISO, Focal Length)
          Row(
            children: [
              Expanded(child: _exifBadge('APERTURE', exif.aperture)),
              const SizedBox(width: 6),
              Expanded(child: _exifBadge('SHUTTER', exif.shutterSpeed)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _exifBadge('ISO', 'ISO ${exif.iso}')),
              const SizedBox(width: 6),
              Expanded(child: _exifBadge('FOCAL', exif.focalLength)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: StudioColors.panelBorder),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    syncStatus == 'completed'
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                    size: 14,
                    color: syncStatus == 'completed'
                        ? StudioColors.statusSuccess
                        : StudioColors.accentAmber,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    syncStatus == 'completed'
                        ? 'Drive: Synced ✓'
                        : 'Drive: Queued •',
                    style: TextStyle(
                      fontSize: 11,
                      color: syncStatus == 'completed'
                          ? StudioColors.statusSuccess
                          : StudioColors.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 26,
                child: OutlinedButton(
                  onPressed: onManualUpload,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: const BorderSide(color: StudioColors.panelBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Upload Now',
                    style: TextStyle(
                      fontSize: 10,
                      color: StudioColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exifBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: StudioColors.canvasBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: StudioColors.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: StudioColors.textMuted,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: StudioColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: StudioTheme.monospaceFont,
            ),
          ),
        ],
      ),
    );
  }
}

