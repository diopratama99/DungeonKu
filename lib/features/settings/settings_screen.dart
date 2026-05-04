import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/supabase_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/characters'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ACCOUNT', style: AppTheme.pressStart(11, color: PixelColors.accentGold)),
                const SizedBox(height: 8),
                Text(user?.email ?? '(not signed in)', style: AppTheme.vt323(18)),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
