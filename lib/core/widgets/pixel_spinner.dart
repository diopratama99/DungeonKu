import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Tiny pixel-art spinner: 8 dots arranged in a ring, lighting up clockwise.
/// Used during DM "thinking" moments. Pure paint, no image asset.
class PixelSpinner extends StatefulWidget {
  const PixelSpinner({this.size = 24, this.color = PixelColors.accentGold, super.key});

  final double size;
  final Color color;

  @override
  State<PixelSpinner> createState() => _PixelSpinnerState();
}

class _PixelSpinnerState extends State<PixelSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _DotPainter(progress: _ctrl.value, color: widget.color),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dotCount = 8;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide / 2 - 2;
    final dotSize = (size.shortestSide / 8).clamp(2.0, 4.0);
    final activeIndex = (progress * dotCount).floor() % dotCount;
    for (var i = 0; i < dotCount; i++) {
      final angle = (i / dotCount) * 6.283185307179586;
      final dx = cx + r * angleCos(angle);
      final dy = cy + r * angleSin(angle);
      final paint = Paint()
        ..color = i == activeIndex
            ? color
            : color.withValues(alpha: 0.25);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(dx, dy), width: dotSize, height: dotSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => old.progress != progress || old.color != color;
}

double angleCos(double a) {
  // Local trig wrappers so we don't need to import dart:math at the call site.
  return _cos(a);
}

double angleSin(double a) {
  return _sin(a);
}

// Pulled out as functions so the const-eval doesn't fight with the painter.
double _cos(double x) => _polynomialCos(_normalize(x));
double _sin(double x) => _polynomialCos(_normalize(x - 1.5707963267948966));

double _normalize(double x) {
  const twoPi = 6.283185307179586;
  var v = x % twoPi;
  if (v < 0) v += twoPi;
  return v;
}

// Tiny polynomial approximation of cos(x), accurate enough for a spinner.
double _polynomialCos(double x) {
  // Reduce to [-pi, pi].
  if (x > 3.141592653589793) x -= 6.283185307179586;
  final x2 = x * x;
  return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
}
