import 'package:flutter/material.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/core/utils/exif_and_histogram_utils.dart';

class RgbHistogramWidget extends StatelessWidget {
  final RgbHistogramData data;
  final bool isLoading;

  const RgbHistogramWidget({
    super.key,
    required this.data,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: StudioColors.canvasBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: StudioColors.panelBorder),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RgbHistogramPainter(data: data),
            ),
          ),
          Positioned(
            top: 2,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _channelDot(const Color(0xFFEF4444), 'R'),
                const SizedBox(width: 6),
                _channelDot(const Color(0xFF10B981), 'G'),
                const SizedBox(width: 6),
                _channelDot(const Color(0xFF3B82F6), 'B'),
                const SizedBox(width: 6),
                _channelDot(const Color(0xFFD1D5DB), 'L'),
              ],
            ),
          ),
          if (isLoading)
            const Positioned(
              bottom: 4,
              right: 4,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: StudioColors.accentAmber,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _channelDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: StudioColors.textMuted,
            fontFamily: StudioTheme.monospaceFont,
          ),
        ),
      ],
    );
  }
}

class _RgbHistogramPainter extends CustomPainter {
  final RgbHistogramData data;

  _RgbHistogramPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw subtle studio grid lines (25%, 50%, 75%)
    final gridPaint = Paint()
      ..color = StudioColors.panelBorder.withValues(alpha: 0.6)
      ..strokeWidth = 0.7;

    for (int i = 1; i <= 3; i++) {
      final x = size.width * (i / 4);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      gridPaint,
    );

    _drawChannel(
      canvas,
      size,
      data.luminance,
      const Color(0xFFE5E7EB).withValues(alpha: 0.18),
      const Color(0xFFE5E7EB).withValues(alpha: 0.55),
    );
    _drawChannel(
      canvas,
      size,
      data.red,
      const Color(0xFFEF4444).withValues(alpha: 0.22),
      const Color(0xFFEF4444).withValues(alpha: 0.85),
    );
    _drawChannel(
      canvas,
      size,
      data.green,
      const Color(0xFF10B981).withValues(alpha: 0.22),
      const Color(0xFF10B981).withValues(alpha: 0.85),
    );
    _drawChannel(
      canvas,
      size,
      data.blue,
      const Color(0xFF3B82F6).withValues(alpha: 0.22),
      const Color(0xFF3B82F6).withValues(alpha: 0.85),
    );
  }

  void _drawChannel(
    Canvas canvas,
    Size size,
    List<double> bins,
    Color fillColor,
    Color strokeColor,
  ) {
    if (bins.isEmpty) return;

    final fillPath = Path()..moveTo(0, size.height);
    final strokePath = Path();

    final count = bins.length;
    for (int i = 0; i < count; i++) {
      final x = (i / (count - 1)) * size.width;
      final normalized = bins[i].clamp(0.0, 1.0);
      final y = size.height - (normalized * (size.height - 8));
      fillPath.lineTo(x, y);
      if (i == 0) {
        strokePath.moveTo(x, y);
      } else {
        strokePath.lineTo(x, y);
      }
    }

    fillPath
      ..lineTo(size.width, size.height)
      ..close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus;

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(strokePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _RgbHistogramPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

