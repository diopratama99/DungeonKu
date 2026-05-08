import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/data/supabase_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: const RetroAppBar(title: 'SETTINGS'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      color: PixelColors.accentGold,
                    ),
                    const SizedBox(width: 8),
                    Text('ADVENTURER',
                        style: AppTheme.pressStart(11,
                            color: PixelColors.accentGold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(user?.email ?? '(not signed in)',
                    style: AppTheme.vt323(18)),
                const SizedBox(height: 4),
                Text('Signed in via Supabase auth',
                    style: AppTheme.vt323(14, color: PixelColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 8, height: 8, color: PixelColors.accentBlue),
                    const SizedBox(width: 8),
                    Text('ABOUT',
                        style: AppTheme.pressStart(11,
                            color: PixelColors.accentBlue)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                    'DungeonKu — a solo D&D-style RPG with an LLM dungeon master.',
                    style: AppTheme.vt323(16)),
                const SizedBox(height: 4),
                Text('Version 0.1.0',
                    style: AppTheme.vt323(14, color: PixelColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PixelButton(
            label: 'Sign out',
            icon: Icons.logout,
            tone: PixelButtonTone.danger,
            fullWidth: true,
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/sign-in');
            },
          ),
        ],
      ),
    );
  }
}
