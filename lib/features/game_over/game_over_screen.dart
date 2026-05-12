import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/audio/bgm_manager.dart';
import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';

/// Final death-narration view. We pull the last DM message (which the death-narration
/// pipeline persists), plus the campaign character snapshot at the moment of death.
class GameOverScreen extends ConsumerStatefulWidget {
  const GameOverScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  ConsumerState<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends ConsumerState<GameOverScreen> {
  /// Whether we've already triggered the audio side effects for this mount.
  /// FutureBuilder rebuilds many times and we only want one stinger.
  bool _audioFired = false;

  @override
  void initState() {
    super.initState();
    // Drop the looping campaign BGM the moment we land here — either the
    // hero is dead (silence is the right beat) or they've won and the
    // quest-complete fanfare is about to fire over silence.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(bgmManagerProvider).stop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(campaignsRepositoryProvider);

    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dimmed ambient art so the death-screen reads as a dirge.
          Image.asset(
            'assets/images/splash/loading_screen.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: PixelColors.inkBackground),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0x66000000), Color(0xEE000000)],
                stops: [0.4, 1.0],
                radius: 1.0,
              ),
            ),
          ),
          SafeArea(
            child: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                repo.loadMessages(widget.campaignId, limit: 200),
                repo.loadCampaignCharacter(widget.campaignId),
                ref.read(campaignsListProvider.future),
              ]),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final messages = snap.data![0] as List<dynamic>;
                final character = snap.data![1];
                final campaigns = snap.data![2] as List<dynamic>;
                final campaign = campaigns.firstWhereOrNull(
                    (c) => (c as dynamic).id == widget.campaignId);
                final completed = campaign != null &&
                    (campaign as dynamic).status == 'completed';
                // One-shot: fire the quest-complete fanfare on first build
                // after the data resolves, but only if the player won.
                if (!_audioFired) {
                  _audioFired = true;
                  if (completed) {
                    ref.read(bgmManagerProvider).playQuestComplete();
                  }
                }
                final lastDm = messages.lastWhereOrNull(
                  (m) => (m as dynamic).role == 'dm',
                );
                final narration = lastDm == null
                    ? 'Your story ends here.'
                    : (lastDm as dynamic).content as String;
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Text('\u2620',
                          textAlign: TextAlign.center,
                          style: AppTheme.pressStart(40,
                              color: PixelColors.accentRed)),
                      const SizedBox(height: 8),
                      Text('GAME OVER',
                          textAlign: TextAlign.center,
                          style: AppTheme.pressStart(22,
                              color: PixelColors.accentRed)),
                      const SizedBox(height: 4),
                      Text('Here ends the tale.',
                          textAlign: TextAlign.center,
                          style: AppTheme.pressStart(8,
                              color: PixelColors.textMuted)),
                      const SizedBox(height: 20),
                      Expanded(
                        child: SingleChildScrollView(
                          child: PixelPanel(
                            color: PixelColors.parchment,
                            borderColor: PixelColors.accentRed,
                            innerBorderColor: PixelColors.parchmentDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                        width: 8,
                                        height: 8,
                                        color: PixelColors.accentRed),
                                    const SizedBox(width: 8),
                                    Text('LAST WORDS',
                                        style: AppTheme.pressStart(10,
                                            color: PixelColors.accentRed)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(narration,
                                    style: AppTheme.vt323(20,
                                        color: PixelColors.textOnParchment)),
                                const SizedBox(height: 16),
                                Container(
                                    height: 1,
                                    color: PixelColors.parchmentDark),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Container(
                                        width: 8,
                                        height: 8,
                                        color: PixelColors.textOnParchment),
                                    const SizedBox(width: 8),
                                    Text('FINAL STATE',
                                        style: AppTheme.pressStart(10,
                                            color:
                                                PixelColors.textOnParchment)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Level ${(character as dynamic).level}  \u00b7  XP ${(character as dynamic).xp}\n'
                                  'HP ${(character as dynamic).hp}/${(character as dynamic).maxHp}\n'
                                  '${(character as dynamic).resourceType.toString().toUpperCase()} '
                                  '${(character as dynamic).resourceCurrent}/${(character as dynamic).resourceMax}',
                                  style: AppTheme.vt323(18,
                                      color: PixelColors.textOnParchment),
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
        ],
      ),
    );
  }
}
