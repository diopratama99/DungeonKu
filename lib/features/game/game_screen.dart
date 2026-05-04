import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_progress_bar.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/features/game/components/action_panel.dart';
import 'package:dungeonku/features/game/components/chat_view.dart';
import 'package:dungeonku/features/game/components/dice_overlay.dart';
import 'package:dungeonku/features/game/components/stats_sheet.dart';
import 'package:dungeonku/features/game/game_providers.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final _customCtrl = TextEditingController();
  bool _customOpen = false;
  bool _initialised = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialised) {
      _initialised = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(gameNotifierProvider.notifier).init(widget.campaignId);
      });
    }

    final asyncState = ref.watch(gameNotifierProvider);

    // Side-effect listener: surface errors as snack bars; route on game over.
    ref.listen(gameNotifierProvider, (prev, next) {
      next.whenData((s) {
        if (s.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.error!, style: AppTheme.vt323(18))),
          );
          ref.read(gameNotifierProvider.notifier).clearError();
        }
        if (s.uiMode == GameUiMode.gameOver) {
          // Route to game-over screen.
          Future.microtask(() {
            if (mounted) context.go('/game-over/${widget.campaignId}');
          });
        }
      });
    });

    return Scaffold(
      body: SafeArea(
        child: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e', style: AppTheme.vt323(18))),
          data: (s) => _buildBody(context, s),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, GameState s) {
    final busy = s.uiMode == GameUiMode.submitting
        || s.uiMode == GameUiMode.combatSubmitting
        || s.uiMode == GameUiMode.resolvingRoll;
    final lockOptions = busy
        || s.uiMode == GameUiMode.awaitingRoll
        || s.uiMode == GameUiMode.gameOver;

    return Stack(
      children: [
        Column(
          children: [
            _TopBar(campaignName: s.campaign.name, phase: s.campaign.phase),
            _StatusStrip(character: s.character),
            Expanded(
              child: ChatView(messages: s.messages, busy: busy),
            ),
            ActionPanel(
              options: s.currentOptions,
              disabled: lockOptions,
              onTapOption: (o) => ref.read(gameNotifierProvider.notifier).tapOption(o),
            ),
            _BottomBar(
              busy: busy,
              customOpen: _customOpen,
              customCtrl: _customCtrl,
              onToggleCustom: () => setState(() => _customOpen = !_customOpen),
              onSubmitCustom: (text) {
                _customCtrl.clear();
                setState(() => _customOpen = false);
                ref.read(gameNotifierProvider.notifier).submitPlayerMessage(text);
              },
              onShowStats: () => _openStatsSheet(context, s),
            ),
          ],
        ),
        if (s.uiMode == GameUiMode.awaitingRoll || s.uiMode == GameUiMode.resolvingRoll)
          if (s.requiresRoll != null)
            DiceOverlay(
              requiresRoll: s.requiresRoll!,
              result: s.lastRollResult,
              onTapDice: () => ref.read(gameNotifierProvider.notifier).resolvePendingRoll(),
              onDone: () {
                // After dice settles, force a state refresh so awaitingRoll mode clears.
                ref.read(gameNotifierProvider.notifier).clearError();
              },
            ),
      ],
    );
  }

  void _openStatsSheet(BuildContext context, GameState s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PixelColors.panelBackground,
      builder: (_) => StatsSheet(
        character: s.character,
        inventory: s.inventory,
        skillIds: s.skillIds,
        allSkills: s.allSkills,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.campaignName, required this.phase});
  final String campaignName;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(bottom: BorderSide(color: PixelColors.borderSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: PixelColors.accentGold),
            onPressed: () => context.go('/campaigns'),
          ),
          Expanded(
            child: Text(
              campaignName.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: AppTheme.pressStart(11, color: PixelColors.accentGold),
            ),
          ),
          _PhaseProgress(phase: phase),
        ],
      ),
    );
  }
}

class _PhaseProgress extends StatelessWidget {
  const _PhaseProgress({required this.phase});
  final String phase;

  static const _phases = ['intro', 'rising', 'climax', 'resolution'];

  @override
  Widget build(BuildContext context) {
    final currentIdx = _phases.indexOf(phase);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_phases.length, (i) {
        final reached = i <= currentIdx;
        final color = reached
            ? (i == currentIdx ? PixelColors.accentGold : PixelColors.accentGreen)
            : PixelColors.borderSoft;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(width: 14, height: 14, color: color),
        );
      }),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.character});
  final dynamic character; // CampaignCharacter

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PixelColors.panelBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: PixelProgressBar(
              label: 'HP',
              current: character.hp as int,
              max: character.maxHp as int,
              fillColor: PixelColors.hpBar,
              compact: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PixelProgressBar(
              label: (character.resourceType as String).toUpperCase(),
              current: character.resourceCurrent as int,
              max: character.resourceMax as int,
              fillColor: (character.resourceType as String) == 'mp'
                  ? PixelColors.mpBar
                  : PixelColors.staminaBar,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.busy,
    required this.customOpen,
    required this.customCtrl,
    required this.onToggleCustom,
    required this.onSubmitCustom,
    required this.onShowStats,
  });

  final bool busy;
  final bool customOpen;
  final TextEditingController customCtrl;
  final VoidCallback onToggleCustom;
  final void Function(String) onSubmitCustom;
  final VoidCallback onShowStats;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(top: BorderSide(color: PixelColors.borderSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.bar_chart, color: PixelColors.accentGold),
                tooltip: 'Stats',
                onPressed: onShowStats,
              ),
              IconButton(
                icon: Icon(
                  customOpen ? Icons.expand_more : Icons.edit,
                  color: PixelColors.accentGold,
                ),
                tooltip: 'Custom action',
                onPressed: onToggleCustom,
              ),
              if (customOpen) ...[
                Expanded(
                  child: TextField(
                    controller: customCtrl,
                    style: AppTheme.vt323(20),
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'What do you do?',
                      filled: true,
                      fillColor: PixelColors.panelInner,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: PixelColors.borderSoft),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PixelButton(
                  label: 'Send',
                  icon: Icons.send,
                  onPressed: busy
                      ? null
                      : () {
                          final t = customCtrl.text.trim();
                          if (t.isNotEmpty) onSubmitCustom(t);
                        },
                ),
              ] else
                Expanded(
                  child: Text(
                    'Tap an option above, or use the pencil for free text.',
                    style: AppTheme.vt323(16, color: PixelColors.textMuted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
