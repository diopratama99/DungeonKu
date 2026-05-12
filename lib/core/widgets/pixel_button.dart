import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Chunky pixel-style button. Pressed state slightly darkens and inverts the inner shadow.
class PixelButton extends StatefulWidget {
  const PixelButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconAsset,
    this.tone = PixelButtonTone.gold,
    this.fullWidth = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Optional asset path (e.g. `assets/images/icons/processed/support_eye.png`).
  /// When provided, the asset is rendered instead of [icon] — used to swap
  /// in our pixel-art icons while keeping a Material fallback for cases
  /// where no matching asset exists yet.
  final String? iconAsset;
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
      case PixelButtonTone.gold:
        return PixelColors.accentGold;
      case PixelButtonTone.neutral:
        return PixelColors.borderSoft;
      case PixelButtonTone.danger:
        return PixelColors.accentRed;
      case PixelButtonTone.blue:
        return PixelColors.accentBlue;
      case PixelButtonTone.green:
        return PixelColors.accentGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final accent = disabled ? PixelColors.borderSoft : _accent;
    // Single-layer chunky button. The previous version stacked an outer
    // black-bg container around the gold-bordered cell which read as a
    // distracting black halo on dark panels — especially when the button
    // was full-width. We keep the retro depth via a 2px offset drop-shadow
    // and a tiny press translation, all on one container.
    final offset = _pressed ? 0.0 : 2.0;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.fullWidth ? double.infinity : null,
        transform:
            Matrix4.translationValues(_pressed ? 1 : 0, _pressed ? 1 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: disabled
              ? PixelColors.panelInner.withValues(alpha: 0.5)
              : PixelColors.panelInner,
          border: Border.all(color: accent, width: 2),
          boxShadow: disabled
              ? const []
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.55),
                    offset: Offset(offset, offset),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.iconAsset != null) ...[
              // Pixel-art icon: keep the grid sharp with FilterQuality.none
              // and avoid Image.asset's default smoothing. errorBuilder
              // falls back to the Material icon (or nothing) if the asset
              // is missing on this build.
              Image.asset(
                widget.iconAsset!,
                width: 18,
                height: 18,
                filterQuality: FilterQuality.none,
                color: disabled ? accent.withValues(alpha: 0.6) : null,
                errorBuilder: (_, __, ___) => widget.icon != null
                    ? Icon(widget.icon, color: accent, size: 14)
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
            ] else if (widget.icon != null) ...[
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
                // Allow wrap up to 3 lines so long action labels like
                // "Follow the scuff marks toward the cellar door" stay
                // readable. Ellipsis only kicks in past line 3 — a safety
                // net for absurdly long LLM output.
                maxLines: 3,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
