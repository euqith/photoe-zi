import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photoe_zi/features/film_sim/domain/cube_lut_parser.dart';

class GpuLutImageRenderer extends StatefulWidget {
  final Uint8List imageBytes;
  final CubeLutData? lutData;
  final ui.Image? lutTexture;
  final double intensity;
  final bool bypassLut;

  const GpuLutImageRenderer({
    super.key,
    required this.imageBytes,
    required this.lutData,
    required this.lutTexture,
    required this.intensity,
    this.bypassLut = false,
  });

  @override
  State<GpuLutImageRenderer> createState() => _GpuLutImageRendererState();
}

class _GpuLutImageRendererState extends State<GpuLutImageRenderer> {
  static ui.FragmentProgram? _cachedProgram;
  ui.FragmentProgram? _program;
  ui.Image? _decodedPhoto;
  Uint8List? _lastBytes;

  @override
  void initState() {
    super.initState();
    _initShader();
    _decodePhotoBytes(widget.imageBytes);
  }

  @override
  void didUpdateWidget(covariant GpuLutImageRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.imageBytes, widget.imageBytes)) {
      _decodePhotoBytes(widget.imageBytes);
    }
  }

  Future<void> _initShader() async {
    if (_cachedProgram != null) {
      _program = _cachedProgram;
      return;
    }
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/lut_3d.frag');
      _cachedProgram = program;
      if (mounted) {
        setState(() {
          _program = program;
        });
      }
    } catch (_) {
      // Fallback to standard Image rendering if shader is unavailable in headless test
    }
  }

  Future<void> _decodePhotoBytes(Uint8List bytes) async {
    _lastBytes = bytes;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted && identical(_lastBytes, bytes)) {
        setState(() {
          _decodedPhoto = frame.image;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final photoImg = _decodedPhoto;
    final lutTex = widget.lutTexture;
    final lutData = widget.lutData;
    final prog = _program;

    if (widget.bypassLut ||
        widget.intensity <= 0.005 ||
        lutData == null) {
      return Image.memory(
        widget.imageBytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );
    }

    if (lutTex == null || prog == null || photoImg == null) {
      // Fallback color matrix while shader is compiling or in headless test mode
      final c0 = lutData.lookupRgb8(255, 0, 0, intensity: widget.intensity);
      final c1 = lutData.lookupRgb8(0, 255, 0, intensity: widget.intensity);
      final c2 = lutData.lookupRgb8(0, 0, 255, intensity: widget.intensity);
      final blk = lutData.lookupRgb8(0, 0, 0, intensity: widget.intensity);
      return ColorFiltered(
        colorFilter: ColorFilter.matrix([
          (c0[0] - blk[0]) / 255.0, (c1[0] - blk[0]) / 255.0, (c2[0] - blk[0]) / 255.0, 0, blk[0].toDouble(),
          (c0[1] - blk[1]) / 255.0, (c1[1] - blk[1]) / 255.0, (c2[1] - blk[1]) / 255.0, 0, blk[1].toDouble(),
          (c0[2] - blk[2]) / 255.0, (c1[2] - blk[2]) / 255.0, (c2[2] - blk[2]) / 255.0, 0, blk[2].toDouble(),
          0, 0, 0, 1, 0,
        ]),
        child: Image.memory(
          widget.imageBytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final imgAspect = photoImg.width / photoImg.height;
        double drawW = constraints.maxWidth;
        double drawH = constraints.maxHeight;

        if (drawW.isInfinite || drawH.isInfinite) {
          drawW = photoImg.width.toDouble();
          drawH = photoImg.height.toDouble();
        } else {
          final boxAspect = drawW / drawH;
          if (imgAspect > boxAspect) {
            drawH = drawW / imgAspect;
          } else {
            drawW = drawH * imgAspect;
          }
        }

        return Center(
          child: SizedBox(
            width: drawW,
            height: drawH,
            child: CustomPaint(
              painter: _GpuLutShaderPainter(
                program: prog,
                photoImage: photoImg,
                lutTexture: lutTex,
                lutSize: lutData.size.toDouble(),
                intensity: widget.intensity,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GpuLutShaderPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final ui.Image photoImage;
  final ui.Image lutTexture;
  final double lutSize;
  final double intensity;

  _GpuLutShaderPainter({
    required this.program,
    required this.photoImage,
    required this.lutTexture,
    required this.lutSize,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    // uniform vec2 uSize (floats 0, 1)
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    // uniform float uLutSize (float 2)
    shader.setFloat(2, lutSize);
    // uniform float uIntensity (float 3)
    shader.setFloat(3, intensity.clamp(0.0, 1.0));
    // uniform sampler2D uPhotoTex (sampler 0)
    shader.setImageSampler(0, photoImage);
    // uniform sampler2D uLutTex (sampler 1)
    shader.setImageSampler(1, lutTexture);

    final paint = Paint()
      ..shader = shader
      ..filterQuality = FilterQuality.high;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GpuLutShaderPainter oldDelegate) {
    return oldDelegate.photoImage != photoImage ||
        oldDelegate.lutTexture != lutTexture ||
        oldDelegate.lutSize != lutSize ||
        oldDelegate.intensity != intensity;
  }
}
