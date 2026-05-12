import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Decorative wrapper that adds small fantasy-style corner ornaments to a
/// rectangular frame.
///
/// We compose via a [Stack] so the existing border / fill of the wrapped
/// [child] is preserved — the ornaments are tiny gold accents painted
/// over the corners, evoking the brass corner studs of an old leather
/// tome rather than an aggressive scrollwork. Inset slightly from each
/// edge so they sit *inside* the frame rather than bursting through it.
///
/// Use anywhere a plain rectangle feels too sterile (panels, tiles,
/// custom buttons).
class OrnateFrame extends StatelessWidget {
  const OrnateFrame({
    required this.child,
    this.color,
    this.cornerSize = 9,
    this.inset = 3,
    super.key,
  });

  final Widget child;
  final Color? color;
  final double cornerSize;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? PixelColors.accentGold;
    return Stack(
      children: [
        child,
        Positioned(
          top: inset,
          left: inset,
          child: _CornerOrnament(color: accent, size: cornerSize),
        ),
        Positioned(
          top: inset,
          right: inset,
          child: _CornerOrnament(color: accent, size: cornerSize),
        ),
        Positioned(
          bottom: inset,
          left: inset,
          child: _CornerOrnament(color: accent, size: cornerSize),
        ),
        Positioned(
          bottom: inset,
          right: inset,
          child: _CornerOrnament(color: accent, size: cornerSize),
        ),
      ],
    );
  }
}

class _CornerOrnament extends StatelessWidget {
  const _CornerOrnament({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size(size, size),
        painter: _OrnamentPainter(color: color),
      ),
    );
  }
}

/// Paints a tiny 4-point diamond (filled rotated square) inside the
/// supplied size. Drawn as a vector path so it scales crisply at any
/// physical pixel ratio without needing a separate asset.
class _OrnamentPainter extends CustomPainter {
  _OrnamentPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Filled diamond (rotated square).
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(size.width, cy)
      ..lineTo(cx, size.height)
      ..lineTo(0, cy)
      ..close();
    canvas.drawPath(path, fill);
    // Tiny inner highlight to make the gold feel jewel-cut rather than
    // flat.
    final highlight = Paint()..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawRect(
      Rect.fromLTWH(cx - 0.5, cy - size.height * 0.35, 1, 1.5),
      highlight,
    );
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) => old.color != color;
}
