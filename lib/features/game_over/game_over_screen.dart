import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';

/// Final death-narration view. We pull the last DM message (which the death-narration
/// pipeline persists), plus the campaign character snapshot at the moment of death.
class GameOverScreen extends ConsumerWidget {
  const GameOverScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(campaignsRepositoryProvider);

    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: SafeArea(
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            repo.loadMessages(campaignId, limit: 200),
            repo.loadCampaignCharacter(campaignId),
          ]),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
            final messages = snap.data![0] as List<dynamic>;
            final character = snap.data![1];
            final lastDm = messages.lastWhere(
              (m) => (m as dynamic).role == 'dm',
              orElse: () => null,
            );
            final narration = lastDm == null ? 'Your story ends here.' : (lastDm as dynamic).content as String;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('GAME OVER',
                      textAlign: TextAlign.center,
                      style: AppTheme.pressStart(22, color: PixelColors.accentRed)),
                  const SizedBox(height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      child: PixelPanel(
                        color: PixelColors.parchment,
                        borderColor: PixelColors.accentRed,
                        innerBorderColor: PixelColors.parchmentDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(narration, style: AppTheme.vt323(20, color: PixelColors.textOnParchment)),
                            const SizedBox(height: 16),
                            Container(height: 1, color: PixelColors.parchmentDark),
                            const SizedBox(height: 12),
                            Text(
                              'FINAL STATE',
                              style: AppTheme.pressStart(10, color: PixelColors.textOnParchment),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Level ${(character as dynamic).level}  ·  XP ${(character as dynamic).xp}\n'
                              'HP ${(character as dynamic).hp}/${(character as dynamic).maxHp}\n'
                              '${(character as dynamic).resourceType.toString().toUpperCase()} '
                              '${(character as dynamic).resourceCurrent}/${(character as dynamic).resourceMax}',
                              style: AppTheme.vt323(18, color: PixelColors.textOnParchment),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PixelButton(
                    label: 'Return to Campaigns',
                    icon: Icons.list,
                    fullWidth: true,
                    onPressed: () => context.go('/campaigns'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
