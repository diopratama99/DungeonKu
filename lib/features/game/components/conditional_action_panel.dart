import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/features/game/components/action_panel.dart';
import 'package:dungeonku/features/game/game_providers.dart';

/// Wraps [ActionPanel] in show/hide logic so the option buttons only
/// appear when the player is actually allowed to act.
///
/// Rules:
/// - `idle` + options non-empty  → slide up the action panel
/// - `awaitingRoll` + requiresRoll non-null → single Roll Dice CTA
/// - `submitting` / `combatSubmitting` / `resolvingRoll` → nothing here
///   (the chat shows a "DM is composing..." typing bubble instead;
///   the dice overlay takes over during resolvingRoll)
/// - `gameOver` → hidden (we route away)
///
/// Hiding the panel when it isn’t actionable removes the previous
/// confusion of grayed-out buttons sitting at the bottom of the screen.
class ConditionalActionPanel extends StatelessWidget {
  const ConditionalActionPanel({
    required this.uiMode,
    required this.options,
    required this.onTapOption,
    this.requiresRoll,
    this.onTapRoll,
    this.suppress = false,
    super.key,
  });

  final GameUiMode uiMode;
  final List<ChatOption> options;
  final void Function(ChatOption option) onTapOption;

  /// When non-null AND uiMode is awaitingRoll, the panel renders a single
  /// dice CTA ("Roll d20 vs DC 14 • DEX") instead of the option list. Tapping
  /// it fires [onTapRoll] which kicks off resolve-roll on the backend.
  final RequiresRoll? requiresRoll;
  final VoidCallback? onTapRoll;

  /// External hide override. When `true` the panel collapses regardless of
  /// uiMode/options — used while the DM bubble is still typewriter-animating
  /// so the player isn't prompted to act mid-sentence.
  final bool suppress;

  @override
  Widget build(BuildContext context) {
    final isRollPrompt = uiMode == GameUiMode.awaitingRoll &&
        requiresRoll != null &&
        onTapRoll != null;
    final canAct = uiMode == GameUiMode.idle && options.isNotEmpty;
    final isCombat = uiMode == GameUiMode.inCombat && options.isNotEmpty;
    final visible = (canAct || isCombat || isRollPrompt) && !suppress;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: visible
            ? Column(
                key: const ValueKey('panel'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PromptHeader(
                    uiMode: uiMode,
                    options: options,
                    isRollPrompt: isRollPrompt,
                  ),
                  if (isRollPrompt)
                    _RollPromptBody(
                      requiresRoll: requiresRoll!,
                      onTapRoll: onTapRoll!,
                    )
                  else
                    ActionPanel(
                      options: options,
                      disabled: false,
                      onTapOption: onTapOption,
                    ),
                ],
              )
            : const SizedBox(
                key: ValueKey('hidden'),
                width: double.infinity,
              ),
      ),
    );
  }
}

class _PromptHeader extends StatelessWidget {
  const _PromptHeader({
    required this.uiMode,
    required this.options,
    this.isRollPrompt = false,
  });
  final GameUiMode uiMode;
  final List<ChatOption> options;
  final bool isRollPrompt;

  @override
  Widget build(BuildContext context) {
    final pivotal = options.any((o) => o.kind == 'pivotal');
    final tone = isRollPrompt
        ? PixelColors.accentRed
        : uiMode == GameUiMode.inCombat
            ? PixelColors.accentRed
            : (pivotal ? PixelColors.accentRed : PixelColors.accentGold);
    final label = isRollPrompt
        ? 'ROLL THE DICE'
        : uiMode == GameUiMode.inCombat
            ? 'YOUR MOVE \u2014 COMBAT'
            : (pivotal ? 'PIVOTAL CHOICE' : 'YOUR TURN');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      decoration: BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(
          top: BorderSide(color: tone, width: 2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 8, height: 8, color: tone),
          const SizedBox(width: 8),
          Text(label, style: AppTheme.pressStart(9, color: tone)),
        ],
      ),
    );
  }
}

/// Single CTA card shown in place of the option list when the DM has
/// requested a dice roll. Tapping fires [onTapRoll] which transitions the
/// game into resolvingRoll mode — the dice overlay then handles the
/// animation and result reveal.
class _RollPromptBody extends StatelessWidget {
  const _RollPromptBody({required this.requiresRoll, required this.onTapRoll});
  final RequiresRoll requiresRoll;
  final VoidCallback onTapRoll;

  @override
  Widget build(BuildContext context) {
    final dice = requiresRoll.dice.toUpperCase();
    final stat = requiresRoll.modifierStat;
    final subline =
        '$dice vs DC ${requiresRoll.dc}${stat != null ? ' · ${stat.toUpperCase()}' : ''}';
    return Container(
      width: double.infinity,
      color: PixelColors.panelBackground,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            requiresRoll.purpose,
            textAlign: TextAlign.center,
            style: AppTheme.vt323(18, color: PixelColors.textOnInk),
          ),
          const SizedBox(height: 4),
          Text(
            subline,
            textAlign: TextAlign.center,
            style: AppTheme.pressStart(8, color: PixelColors.textMuted),
          ),
          const SizedBox(height: 10),
          PixelButton(
            label: 'Roll $dice',
            icon: Icons.casino,
            onPressed: onTapRoll,
          ),
        ],
      ),
    );
  }
}
