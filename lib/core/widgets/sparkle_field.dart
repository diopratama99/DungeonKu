import 'dart:math';

import 'package:flutter/material.dart';

/// Animated background sparkle layer.
///
/// Generates a fixed list of pseudo-random "stars" with their own twinkle
/// phase / speed, and repaints them via a single shared [AnimationController]
/// so the cost is one TickerProvider regardless of how many particles we
/// draw. Each particle is a small 4-point cross that fades in and out on
/// a sine schedule.
///
/// Tuned for the title screen: drop it into a [Stack] above the backdrop
/// gradient and below the foreground content — `IgnorePointer` is wrapped
/// in for free so it never eats taps from buttons sitting above.
class SparkleField extends StatefulWidget {
  const SparkleField({
    this.count = 32,
    this.color = const Color(0xFFE8C66A),
    this.maxSize = 5,
    this.minSize = 1.5,
    this.seed = 42,
    super.key,
  });

  final int count;
  final Color color;
  final double maxSize;
  final double minSize;

  /// Seed for the deterministic particle layout. Pass a different number
  /// per screen if you want each one to feel slightly different.
  final int seed;

  @override
  State<SparkleField> createState() => _SparkleFieldState();
}

class _SparkleFieldState extends State<SparkleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Sparkle> _sparkles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Long loop so the twinkle pattern doesn't visibly repeat. Sparkles
      // each have their own speed multiplier on top of this.
      duration: const Duration(seconds: 8),
    )..repeat();

    final r = Random(widget.seed);
    _sparkles = List.generate(widget.count, (_) {
      return _Sparkle(
        // Distribute across full width but bias toward upper 75% so the
        // bottom menu area stays clean.
        x: r.nextDouble(),
        y: r.nextDouble() * 0.75,
        // Phase offset so they don't twinkle in unison.
        phase: r.nextDouble(),
        size:
            widget.minSize + r.nextDouble() * (widget.maxSize - widget.minSize),
        // Per-particle speed multiplier (some twinkle faster than
        // others) — keeps the layer feeling alive.
        speed: 0.6 + r.nextDouble() * 1.6,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => CustomPaint(
          painter: _SparklePainter(
            sparkles: _sparkles,
            t: _controller.value,
            color: widget.color,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Sparkle {
  _Sparkle({
    required this.x,
    required this.y,
    required this.phase,
    required this.size,
    required this.speed,
  });

  /// All values are normalized 0..1 except `size` (logical pixels) and
  /// `speed` (multiplier on top of the controller).
  final double x;
  final double y;
  final double phase;
  final double size;
  final double speed;
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({
    required this.sparkles,
    required this.t,
    required this.color,
  });

  final List<_Sparkle> sparkles;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final phase = (t * s.speed + s.phase) * 2 * pi;
      // Cube the sin term so each sparkle sits dim most of the time
      // and only briefly flashes at full brightness — that's what reads
      // as "twinkle" instead of a static field of dots. Final 0.55 caps
      // the peak so even the brightest sparkle never dominates.
      final wave = sin(phase).abs();
      final opacity = wave * wave * wave * 0.55;
      if (opacity < 0.05) continue;
      final paint = Paint()..color = color.withValues(alpha: opacity);
      final cx = s.x * size.width;
      final cy = s.y * size.height;
      // 4-point cross shape via two thin rectangles.
      final w = s.size;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: 1, height: w),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: w, height: 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) =>
      old.t != t || old.color != color || old.sparkles != sparkles;
}
