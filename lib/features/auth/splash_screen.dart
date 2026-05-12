import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_spinner.dart';

/// Brief splash while go_router decides where to send the user.
///
/// Uses the painted `loading_screen.png` as a backdrop, fades the wordmark in,
/// and pulses a small spinner — sets the D&D table-tome tone before the user
/// even sees the home screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Painted backdrop.
          Image.asset(
            'assets/images/splash/loading_screen.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: PixelColors.inkBackground),
          ),
          // Vignette so the wordmark + spinner read on busy art.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0x00000000), Color(0xCC000000)],
                stops: [0.55, 1.0],
                radius: 0.95,
              ),
            ),
          ),
          // Logo + spinner stack.
          FadeTransition(
            opacity: CurvedAnimation(parent: _intro, curve: Curves.easeOut),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 280, maxHeight: 280),
                  child: Image.asset(
                    'assets/images/logo/dungeonku_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Text(
                      'DUNGEONKU',
                      style: AppTheme.pressStart(28,
                          color: PixelColors.accentGold),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                const PixelSpinner(size: 28),
                const SizedBox(height: 12),
                Text(
                  'PREPARING YOUR ADVENTURE...',
                  style: AppTheme.pressStart(8, color: PixelColors.accentGold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
