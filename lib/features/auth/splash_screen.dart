import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_spinner.dart';

/// Brief splash while go_router decides where to send the user.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('DUNGEONKU', style: AppTheme.pressStart(20, color: PixelColors.accentGold)),
            const SizedBox(height: 24),
            const PixelSpinner(),
          ],
        ),
      ),
    );
  }
}
