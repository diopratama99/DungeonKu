import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Single source of truth for element \u2192 colour mapping.
///
/// Element ids are lowercase (e.g. `fire`, `lightning`, `dark`). The
/// fallback covers anything else (`neutral`, custom mod elements, etc.)
/// with the soft border colour so the UI never crashes on an unknown id.
Color elementTone(String element) {
  switch (element.toLowerCase()) {
    case 'fire':
      return PixelColors.accentRed;
    case 'water':
      return PixelColors.accentBlue;
    case 'wind':
      return PixelColors.accentGreen;
    case 'earth':
      return const Color(0xFF8E7E58);
    case 'lightning':
      return PixelColors.accentGold;
    case 'dark':
      return PixelColors.accentPurple;
    case 'light':
      return const Color(0xFFE8E2C9);
    case 'neutral':
      return PixelColors.textMuted;
    default:
      return PixelColors.borderSoft;
  }
}

/// Resolve the asset path for the corresponding element PNG. The file may
/// not exist for custom elements \u2014 callers should fall back to a swatch
/// using [elementTone] when the image fails to load.
String elementAssetPath(String element) =>
    'assets/images/elements/${element.toLowerCase()}.png';
