import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';

/// A chunky double-bordered panel — gold outer ring, soft inner ring, dark fill.
/// Used as the chrome around every framed UI element (chat bubbles, stat sheets, dialogs).
class PixelPanel extends StatelessWidget {
  const PixelPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color = PixelColors.panelBackground,
    this.borderColor = PixelColors.accentGold,
    this.innerBorderColor = PixelColors.borderSoft,
    this.borderWidth = 2,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final Color innerBorderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PixelColors.borderOuter,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: innerBorderColor, width: 1),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}
