import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Chunky pixel-style button. Pressed state slightly darkens and inverts the inner shadow.
class PixelButton extends StatefulWidget {
  const PixelButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = PixelButtonTone.gold,
    this.fullWidth = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PixelButtonTone tone;
  final bool fullWidth;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

enum PixelButtonTone { gold, neutral, danger, blue, green }

class _PixelButtonState extends State<PixelButton> {
  bool _pressed = false;

  Color get _accent {
    switch (widget.tone) {
      case PixelButtonTone.gold:    return PixelColors.accentGold;
      case PixelButtonTone.neutral: return PixelColors.borderSoft;
      case PixelButtonTone.danger:  return PixelColors.accentRed;
      case PixelButtonTone.blue:    return PixelColors.accentBlue;
      case PixelButtonTone.green:   return PixelColors.accentGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final accent = disabled ? PixelColors.borderSoft : _accent;
    final shift = _pressed ? 2.0 : 0.0;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.fullWidth ? double.infinity : null,
        padding: EdgeInsets.fromLTRB(14, 10 + shift, 14, 10 - shift),
        decoration: BoxDecoration(
          color: PixelColors.borderOuter,
          border: Border.all(color: accent, width: 2),
          boxShadow: _pressed || disabled
              ? const []
              : const [
                  BoxShadow(
                    color: PixelColors.borderOuter,
                    offset: Offset(2, 2),
                  ),
                ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: disabled ? PixelColors.panelInner.withValues(alpha: 0.5) : PixelColors.panelInner,
            border: Border.all(color: PixelColors.borderSoft, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: accent, size: 14),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: AppTheme.pressStart(
                    10,
                    color: disabled ? PixelColors.textMuted : accent,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
