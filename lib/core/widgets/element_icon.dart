import 'package:flutter/material.dart';

import 'package:dungeonku/core/utils/element_palette.dart';

/// Renders an element\u2019s PNG icon (from `assets/images/elements/`) inside
/// a square, tinted-bordered tile. If the asset is missing the widget
/// falls back to a flat colour swatch so the UI never breaks for custom
/// or future elements.
///
/// Use [size] for the outer box edge length. The PNG itself fits inside
/// minus a 2-pixel border + 1-pixel inner mat (so a 32-pixel icon shows
/// art on roughly 26 pixels). For inline list-row use ~20-24, for chips
/// 28-32, for codex hero tiles 56-64.
class ElementIcon extends StatelessWidget {
  const ElementIcon({
    required this.element,
    this.size = 28,
    this.bordered = true,
    this.label,
    super.key,
  });

  final String element;
  final double size;

  /// When true, wraps the icon in a 1px element-tinted border + dark mat
  /// so it reads as a heraldic tile (used in codex / chips). Set to false
  /// for inline list rows where the tone-bordered background would be
  /// visual noise.
  final bool bordered;

  /// Optional accessibility label. If omitted defaults to the element id.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tone = elementTone(element);
    final image = Image.asset(
      elementAssetPath(element),
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.none, // keep pixel-art crisp
      errorBuilder: (_, __, ___) => Container(color: tone),
    );

    if (!bordered) {
      return Semantics(
        label: label ?? element,
        child: SizedBox(width: size, height: size, child: image),
      );
    }

    return Semantics(
      label: label ?? element,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF0E0B07),
          border: Border.all(color: tone, width: 1),
        ),
        child: ClipRect(child: image),
      ),
    );
  }
}
