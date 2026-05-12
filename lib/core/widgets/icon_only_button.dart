import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/ornate_frame.dart';

/// Compact square icon button — no label.
///
/// Used in places where an action doesn't deserve a full button slot
/// (Settings on the title screen, Delete in dense list rows, etc.). Has
/// the same press-translation feel as [PixelButton] so it reads as part
/// of the same visual family. Optional [tone] colors the border + drop
/// shadow; default is the soft border accent.
class IconOnlyButton extends StatefulWidget {
  const IconOnlyButton({
    required this.iconAsset,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.iconSize,
    this.tone,
    this.fallbackIcon,
    this.ornate = true,
    super.key,
  });

  final String iconAsset;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  /// Inner padding wraps the asset. Defaults to size * 0.7 so there's
  /// breathing room on each side for the corner ornaments.
  final double? iconSize;

  /// Border + shadow color. Defaults to [PixelColors.borderSoft].
  final Color? tone;

  /// Material icon to fall back to if the asset fails to load.
  final IconData? fallbackIcon;

  /// Adds tiny corner diamonds to the button via [OrnateFrame]. Off for
  /// callers that want the button to read as a flatter affordance.
  final bool ornate;

  @override
  State<IconOnlyButton> createState() => _IconOnlyButtonState();
}

class _IconOnlyButtonState extends State<IconOnlyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.tone ?? PixelColors.borderSoft;
    final iconSize = widget.iconSize ?? widget.size * 0.7;
    final body = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.size,
        height: widget.size,
        transform: Matrix4.translationValues(
            _pressed ? 1 : 0, _pressed ? 1 : 0, 0),
        decoration: BoxDecoration(
          color: PixelColors.panelInner,
          border: Border.all(color: accent, width: 2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.4),
              offset: Offset(_pressed ? 0 : 2, _pressed ? 0 : 2),
            ),
          ],
        ),
        child: Center(
          child: SizedBox(
            width: iconSize,
            height: iconSize,
            child: Image.asset(
              widget.iconAsset,
              filterQuality: FilterQuality.none,
              errorBuilder: (_, __, ___) => Icon(
                widget.fallbackIcon ?? Icons.help_outline,
                color: accent,
                size: iconSize * 0.8,
              ),
            ),
          ),
        ),
      ),
    );
    final wrapped = widget.ornate
        ? OrnateFrame(color: accent, cornerSize: 5, inset: 1, child: body)
        : body;
    return widget.tooltip != null
        ? Tooltip(message: widget.tooltip!, child: wrapped)
        : wrapped;
  }
}
