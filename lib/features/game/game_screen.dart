import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_progress_bar.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/features/game/components/chat_game_view.dart';
import 'package:dungeonku/features/game/components/chat_view.dart';
import 'package:dungeonku/features/game/components/conditional_action_panel.dart';
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
  // True while at least one fresh DM/NPC bubble is still typewriter-animating.
  // We hide the YOUR TURN panel during this so the player isn't prompted
  // to act while the DM is mid-sentence.
  bool _dmTyping = false;

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
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(s.error!, style: AppTheme.vt323(18)),
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              backgroundColor: PixelColors.panelBackground,
              action: SnackBarAction(
                label: 'RETRY',
                textColor: PixelColors.accentGold,
                onPressed: () {
                  ref.read(gameNotifierProvider.notifier).retry();
                },
              ),
            ),
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
          error: (e, _) =>
              Center(child: Text('Error: $e', style: AppTheme.vt323(18))),
          data: (s) => _buildBody(context, s),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, GameState s) {
    final busy = s.uiMode == GameUiMode.submitting ||
        s.uiMode == GameUiMode.combatSubmitting ||
        s.uiMode == GameUiMode.resolvingRoll;

    return Stack(
      children: [
        Column(
          children: [
            _TopBar(campaignName: s.campaign.name, phase: s.campaign.phase),
            _StatusStrip(character: s.character),
            Expanded(
              child: ChatGameView(
                campaign: s.campaign,
                character: s.character,
                messages: s.messages,
                combat: s.combat,
                busy: busy,
                onTypewriterActiveChange: (active) {
                  if (!mounted) return;
                  if (_dmTyping == active) return;
                  setState(() => _dmTyping = active);
                },
              ),
            ),
            ConditionalActionPanel(
              uiMode: s.uiMode,
              options: s.currentOptions,
              requiresRoll: s.requiresRoll,
              onTapRoll: () =>
                  ref.read(gameNotifierProvider.notifier).resolvePendingRoll(),
              suppress: _dmTyping,
              onTapOption: (o) =>
                  ref.read(gameNotifierProvider.notifier).tapOption(o),
            ),
            _BottomBar(
              busy: busy,
              customOpen: _customOpen,
              customCtrl: _customCtrl,
              onToggleCustom: () => setState(() => _customOpen = !_customOpen),
              onSubmitCustom: (text) {
                _customCtrl.clear();
                setState(() => _customOpen = false);
                ref
                    .read(gameNotifierProvider.notifier)
                    .submitPlayerMessage(text);
              },
              onShowStats: () => _openStatsSheet(context, s),
              onShowHistory: () => _openHistorySheet(context, s.messages, busy),
            ),
          ],
        ),
        // The dice overlay now appears only AFTER the player taps the Roll
        // button in the action panel (which transitions us into
        // resolvingRoll). It auto-starts its tumble animation and stays
        // mounted until finishRollFlow() clears the state — so the result
        // face has time to settle before the new DM bubble starts typing.
        if (s.uiMode == GameUiMode.resolvingRoll && s.requiresRoll != null)
          DiceOverlay(
            requiresRoll: s.requiresRoll!,
            result: s.lastRollResult,
            autoStart: true,
            onDone: () =>
                ref.read(gameNotifierProvider.notifier).finishRollFlow(),
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

  void _openHistorySheet(
      BuildContext context, List<GameMessage> messages, bool busy) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PixelColors.panelBackground,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('STORY LOG',
                  style:
                      AppTheme.pressStart(11, color: PixelColors.accentGold)),
            ),
            Expanded(
              child: ChatView(messages: messages, busy: busy),
            ),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(
          bottom: BorderSide(color: PixelColors.borderHighlight, width: 2),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: PixelColors.accentGold),
            tooltip: 'Back to campaigns',
            onPressed: () => context.go('/campaigns'),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: Image.asset(
              'assets/images/logo/dungeonku_app-icon.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  campaignName.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.pressStart(11, color: PixelColors.accentGold),
                ),
                Text(
                  'CHAPTER · ${phase.toUpperCase()}',
                  style: AppTheme.pressStart(7, color: PixelColors.textMuted),
                ),
              ],
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
            ? (i == currentIdx
                ? PixelColors.accentGold
                : PixelColors.accentGreen)
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
    required this.onShowHistory,
  });

  final bool busy;
  final bool customOpen;
  final TextEditingController customCtrl;
  final VoidCallback onToggleCustom;
  final void Function(String) onSubmitCustom;
  final VoidCallback onShowStats;
  final VoidCallback onShowHistory;

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
                icon:
                    const Icon(Icons.bar_chart, color: PixelColors.accentGold),
                tooltip: 'Stats',
                onPressed: onShowStats,
              ),
              IconButton(
                icon:
                    const Icon(Icons.menu_book, color: PixelColors.accentGold),
                tooltip: 'Story log',
                onPressed: onShowHistory,
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
