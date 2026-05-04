import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Chunky 16-bit-style progress bar. Used for HP, MP/Stamina, XP, and the campaign phase
/// indicator. Always shows the numeric label inline because pixel UIs lean on numbers.
class PixelProgressBar extends StatelessWidget {
  const PixelProgressBar({
    required this.label,
    required this.current,
    required this.max,
    required this.fillColor,
    this.height = 14,
    this.compact = false,
    super.key,
  });

  final String label;
  final num current;
  final num max;
  final Color fillColor;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (current / max).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '$label  ${current.toInt()}/${max.toInt()}',
              style: AppTheme.pressStart(8, color: fillColor),
            ),
          ),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: PixelColors.borderOuter,
            border: Border.all(color: PixelColors.borderSoft, width: 1),
          ),
          child: ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: ratio == 0 ? 0.001 : ratio,
              child: Container(color: fillColor),
            ),
          ),
        ),
        if (compact)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$label ${current.toInt()}/${max.toInt()}',
              style: AppTheme.pressStart(7, color: fillColor),
            ),
          ),
      ],
    );
  }
}
