import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Pixel-art retro theme. Two type styles:
///   * `pressStart2P` for chunky UI labels (buttons, screen titles, stat counters).
///   * `vt323` for body / chat content (still pixely but readable at long lengths).
class AppTheme {
  AppTheme._();

  static TextStyle pressStart(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.pressStart2p(
        fontSize: size,
        color: color ?? PixelColors.textOnInk,
        fontWeight: weight,
        height: 1.4,
      );

  static TextStyle vt323(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.vt323(
        fontSize: size,
        color: color ?? PixelColors.textOnInk,
        fontWeight: weight,
        height: 1.25,
      );

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: PixelColors.inkBackground,
      colorScheme: const ColorScheme.dark(
        primary: PixelColors.accentGold,
        onPrimary: PixelColors.inkBackground,
        secondary: PixelColors.accentBlue,
        onSecondary: PixelColors.inkBackground,
        surface: PixelColors.panelBackground,
        onSurface: PixelColors.textOnInk,
        error: PixelColors.accentRed,
        onError: PixelColors.textOnInk,
      ),
      textTheme: TextTheme(
        displayLarge: pressStart(20),
        displayMedium: pressStart(16),
        headlineMedium: pressStart(14),
        titleLarge: pressStart(12),
        titleMedium: pressStart(10),
        bodyLarge: vt323(20),
        bodyMedium: vt323(18),
        bodySmall: vt323(16, color: PixelColors.textMuted),
        labelLarge: pressStart(10),
        labelMedium: pressStart(9),
        labelSmall: pressStart(8, color: PixelColors.textMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: PixelColors.panelBackground,
        foregroundColor: PixelColors.accentGold,
        titleTextStyle: pressStart(12, color: PixelColors.accentGold),
        elevation: 0,
        centerTitle: true,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PixelColors.panelBackground,
        modalBackgroundColor: PixelColors.panelBackground,
      ),
      dividerColor: PixelColors.borderSoft,
      iconTheme: const IconThemeData(color: PixelColors.accentGold),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: PixelColors.accentGold,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PixelColors.panelBackground,
        contentTextStyle: vt323(18),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }
}
