import 'package:flutter/material.dart';

/// Muted parchment + ink palette inspired by classic SNES JRPGs and Sea of Stars.
/// Use these constants instead of hardcoded color literals — keeps the palette honest.
class PixelColors {
  PixelColors._();

  // Backgrounds
  static const Color parchment = Color(0xFFE8DCB8);
  static const Color parchmentDark = Color(0xFFC8B885);
  static const Color inkBackground = Color(0xFF1E1A14);
  static const Color panelBackground = Color(0xFF2A2418);
  static const Color panelInner = Color(0xFF3A3120);

  // Borders
  static const Color borderOuter = Color(0xFF000000);
  static const Color borderHighlight = Color(0xFFD4AF37);
  static const Color borderSoft = Color(0xFF6B5A3A);

  // Text
  static const Color textOnParchment = Color(0xFF1E1A14);
  static const Color textOnInk = Color(0xFFE8DCB8);
  static const Color textMuted = Color(0xFF8E7E58);
  static const Color textNarration = Color(0xFFE8DCB8);
  static const Color textPlayer = Color(0xFFE8C66A);

  // Accents
  static const Color accentGold = Color(0xFFD4AF37);
  static const Color accentRed = Color(0xFFC64545);
  static const Color accentBlue = Color(0xFF4F8CB0);
  static const Color accentGreen = Color(0xFF3B6E58);
  static const Color accentPurple = Color(0xFF8A4EC6);

  // Status bars
  static const Color hpBar = Color(0xFFC64545);
  static const Color mpBar = Color(0xFF4F8CB0);
  static const Color staminaBar = Color(0xFF6FBF73);
  static const Color xpBar = Color(0xFFE8C66A);
}
