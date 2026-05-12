// StoryScreen — story-graph engine renderer.
//
// Intentionally mirrors GameScreen's UX so all campaigns feel unified once
// legacy templates are ported to the node graph.
//
// Layout (top → bottom, identical to GameScreen):
//   _StoryTopBar       — campaign name + phase dots + back + logo
//   _StoryStatusStrip  — HP + resource bars
//   [content area]     — scrollable chat: history bubbles + current DM bubble
//   [action panel]     — AnimatedSize "YOUR TURN" + PixelButton options
//                        SUPPRESSED while DM bubble is typewriter-animating
//   [bottom bar]       — stats / story-log / pencil (free-text Role B)
//
// Typewriter: new DM bubbles animate character-by-character, matching
// ChatGameView. Tapping the bubble skips to full text. The action panel
// slides in only after the animation finishes, preventing accidental taps.
//
// History: every _take() pushes the current node body + chosen option label
// into _history before loading the next node, rendering as alternating
// DM/player bubbles (same visual as Sunken Crown etc. in GameScreen).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/utils/asset_index.dart';
import 'package:dungeonku/core/utils/story_assets.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/pixel_progress_bar.dart';
import 'package:dungeonku/core/widgets/pixel_spinner.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/core/widgets/typewriter_text.dart';
import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/models/story_node.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';
import 'package:dungeonku/data/repositories/profiles_repository.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';
import 'package:dungeonku/data/repositories/story_engine_repository.dart';
import 'package:dungeonku/data/supabase_providers.dart';
import 'package:dungeonku/features/game/components/stats_sheet.dart';

// ---------------------------------------------------------------------------
// History entry
// ---------------------------------------------------------------------------

class _HistoryEntry {
  const _HistoryEntry({
    required this.body,
    required this.choiceLabel,
    this.speaker,
  });
  final String body;
  final String? speaker;
  final String choiceLabel;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class StoryScreen extends ConsumerStatefulWidget {
  const StoryScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  ConsumerState<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends ConsumerState<StoryScreen> {
  StoryNodePayload? _payload;
  CampaignCharacter? _character;
  List<InventoryItem> _inventory = [];
  List<String> _skillIds = [];
  final List<_HistoryEntry> _history = [];

  bool _busy = true;
  String? _error;

  // Typewriter gate: true while the CURRENT DM bubble is still animating.
  // Action panel is suppressed until this clears, just like GameScreen's
  // _dmTyping / suppress logic.
  bool _isTyping = false;

  // Whether the NEXT payload received should trigger the typewriter on its
  // DM bubble. False on initial bootstrap (player already knows the state);
  // true whenever _take() or post-combat bootstrap loads a genuinely new node.
  bool _animateNextBubble = false;

  // Tracks the last measured height of the chat viewport (set via LayoutBuilder).
  // Used to re-pin scroll to bottom when the action panel slides in and shrinks
  // the available height — mirrors ChatGameView._onViewportHeightChanged.
  double _lastViewportHeight = 0;

  // Free-text pencil panel (Role B) open/closed in the bottom bar.
  bool _customOpen = false;

  final _scrollCtrl = ScrollController();
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---- scroll helpers (mirrors ChatGameView) ----

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        final target = _scrollCtrl.position.maxScrollExtent;
        if (animate) {
          _scrollCtrl.animateTo(target,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        } else {
          _scrollCtrl.jumpTo(target);
        }
      });
    });
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer =
        Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_isTyping) {
        _stopAutoScroll();
        return;
      }
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if ((_scrollCtrl.position.pixels - target).abs() > 0.5) {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  // Mirrors ChatGameView._onViewportHeightChanged: when the action panel slides
  // in it shrinks the chat area. If we were at the bottom, re-pin so the last
  // DM bubble stays visible rather than hiding behind the incoming panel.
  void _onViewportHeightChanged(double newHeight) {
    if (newHeight <= 0) return;
    final old = _lastViewportHeight;
    _lastViewportHeight = newHeight;
    if (old <= 0 || newHeight >= old) return; // only handle shrinks
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final wasNearBottom = (pos.maxScrollExtent - pos.pixels).abs() <= 30;
    if (!wasNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  // Called by _DmBubble's TypewriterText.onDone.
  void _onBubbleAnimationDone() {
    _stopAutoScroll();
    if (mounted) setState(() => _isTyping = false);
    _scrollToBottom();
  }

  // ---- data loading ----

  Future<void> _bootstrap() async {
    final shouldAnimate = _animateNextBubble;
    _animateNextBubble = false;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final storyRepo = ref.read(storyEngineRepositoryProvider);
      final campaignsRepo = ref.read(campaignsRepositoryProvider);
      final db = ref.read(dbProvider);

      final p = await storyRepo.currentTurn(campaignId: widget.campaignId);
      final char =
          await campaignsRepo.loadCampaignCharacter(widget.campaignId);

      final invRows = await db
          .from('campaign_inventory')
          .select()
          .eq('campaign_id', widget.campaignId)
          .gt('qty', 0);
      final inventory = (invRows as List)
          .map((r) => InventoryItem.fromJson(
              Map<String, dynamic>.from(r as Map)))
          .toList();

      final skillRows = await db
          .from('campaign_skills')
          .select('skill_id')
          .eq('campaign_id', widget.campaignId);
      final skillIds = (skillRows as List)
          .map((r) =>
              (r as Map<String, dynamic>)['skill_id'] as String)
          .toList();

      if (!mounted) return;
      setState(() {
        _payload = p;
        _character = char;
        _inventory = inventory;
        _skillIds = skillIds;
        _busy = false;
        _isTyping = shouldAnimate;
      });

      if (shouldAnimate) {
        _startAutoScroll();
        _scrollToBottom();
      } else {
        _scrollToBottom(animate: false);
      }
      _maybeHandleEndState(p);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _take(StoryOption opt) async {
    if (opt.locked || _busy) return;

    // Push current node to history before loading next.
    final current = _payload;
    if (current != null) {
      setState(() {
        _history.add(_HistoryEntry(
          body: current.body,
          speaker: current.speaker,
          choiceLabel: opt.label,
        ));
      });
    }

    _animateNextBubble = true;
    setState(() {
      _busy = true;
      _customOpen = false; // close free-text panel on navigation
    });

    try {
      final storyRepo = ref.read(storyEngineRepositoryProvider);
      final campaignsRepo = ref.read(campaignsRepositoryProvider);

      final p = await storyRepo.takeOption(
        campaignId: widget.campaignId,
        optionId: opt.id,
      );
      final char =
          await campaignsRepo.loadCampaignCharacter(widget.campaignId);

      if (!mounted) return;
      ref.invalidate(campaignsListProvider);
      setState(() {
        _payload = p;
        _character = char;
        _busy = false;
        _isTyping = true; // suppress action panel while typewriter runs
      });
      _startAutoScroll();
      _scrollToBottom();
      _maybeHandleEndState(p);
    } catch (e) {
      // Roll back the optimistic history push.
      if (!mounted) return;
      if (_history.isNotEmpty) _history.removeLast();
      setState(() {
        _error = e.toString();
        _busy = false;
        _animateNextBubble = false;
      });
    }
  }

  void _maybeHandleEndState(StoryNodePayload p) {
    if (p.endedCampaign != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future<void>.delayed(const Duration(seconds: 4), () {
          if (!mounted) return;
          context.go('/game-over/${widget.campaignId}');
        });
      });
      return;
    }
    if (p.pendingCombatId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.push('/story-combat/${widget.campaignId}').then((_) {
          if (!mounted) return;
          _animateNextBubble = true;
          _bootstrap();
        });
      });
    }
  }

  Future<void> _submitFreeText(String text) async {
    final p = _payload;
    if (p == null || _busy) return;
    setState(() {
      _busy = true;
      _customOpen = false;
    });

    // Push current node to history optimistically.
    if (p.options.isNotEmpty) {
      setState(() {
        _history.add(_HistoryEntry(
          body: p.body,
          speaker: p.speaker,
          choiceLabel: '"$text"',
        ));
      });
    }

    _animateNextBubble = true;

    try {
      final repo = ref.read(storyEngineRepositoryProvider);
      final campaignsRepo = ref.read(campaignsRepositoryProvider);

      final res = await repo.mapIntent(
        campaignId: widget.campaignId,
        freeText: text,
      );

      if (res.optionId == null) {
        // Intent not matched — roll back history push, show reason.
        if (!mounted) return;
        if (_history.isNotEmpty) _history.removeLast();
        setState(() {
          _busy = false;
          _animateNextBubble = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              res.reason.isNotEmpty ? res.reason : 'Could not match your input to an option.',
              style: AppTheme.vt323(18)),
          backgroundColor: PixelColors.panelBackground,
          duration: const Duration(seconds: 4),
        ));
        return;
      }

      final next = await repo.takeOption(
        campaignId: widget.campaignId,
        optionId: res.optionId!,
      );
      final char =
          await campaignsRepo.loadCampaignCharacter(widget.campaignId);

      if (!mounted) return;
      ref.invalidate(campaignsListProvider);
      setState(() {
        _payload = next;
        _character = char;
        _busy = false;
        _isTyping = true;
      });
      _startAutoScroll();
      _scrollToBottom();
      _maybeHandleEndState(next);
    } catch (e) {
      if (!mounted) return;
      if (_history.isNotEmpty) _history.removeLast();
      setState(() {
        _error = e.toString();
        _busy = false;
        _animateNextBubble = false;
      });
    }
  }

  void _openStatsSheet(BuildContext context, List<Skill> allSkills) {
    final char = _character;
    if (char == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PixelColors.panelBackground,
      builder: (_) => StatsSheet(
        character: char,
        inventory: _inventory,
        skillIds: _skillIds,
        allSkills: allSkills,
      ),
    );
  }

  void _openHistoryLog(BuildContext context, String? playerAvatar) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PixelColors.panelBackground,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('STORY LOG',
                  style: AppTheme.pressStart(11,
                      color: PixelColors.accentGold)),
            ),
            Expanded(
              child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: _history.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final e = _history[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DmBubble(
                        body: e.body,
                        speaker: e.speaker,
                        isPivotal: false,
                        isEnding: false,
                      ),
                      const SizedBox(height: 6),
                      _PlayerBubble(
                          label: e.choiceLabel,
                          avatarPath: playerAvatar),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final campaign = ref.watch(campaignsListProvider).maybeWhen(
          data: (list) {
            for (final c in list) {
              if (c.id == widget.campaignId) return c;
            }
            return null;
          },
          orElse: () => null,
        );

    final allSkills = ref.watch(skillsCatalogProvider).maybeWhen(
          data: (s) => s,
          orElse: () => <Skill>[],
        );

    // Resolve player avatar.
    final char = _character;
    final chars = ref.watch(charactersListProvider).maybeWhen(
          data: (l) => l,
          orElse: () => <Character>[],
        );
    Character? baseChar;
    if (char != null) {
      for (final c in chars) {
        if (c.id == char.characterId) {
          baseChar = c;
          break;
        }
      }
    }

    // Backdrop + player portrait via same resolver as ChatGameView.
    final resolver = ref.watch(assetIndexProvider).maybeWhen(
          data: (idx) => StoryAssetResolver(idx),
          orElse: () => null,
        );
    final bgPath = campaign != null
        ? resolver?.backgroundFor(
            templateId: campaign.templateId,
            phase: campaign.phase,
            inCombat: false,
          )
        : null;
    final playerAvatar = resolver?.playerPortrait(
          avatarId: baseChar?.avatarId,
          classId: baseChar?.classId,
        ) ??
        (baseChar != null
            ? 'assets/images/avatars/${baseChar.avatarId}.png'
            : null);

    // Role B availability.
    final intentMapperOn =
        ref.watch(aiTogglesProvider).maybeWhen(
              data: (v) => v.intentMapper,
              orElse: () => false,
            );

    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: SafeArea(
        child: Column(
          children: [
            _StoryTopBar(
              campaign: campaign,
              onBack: () => context.go('/campaigns'),
            ),
            if (_character != null)
              _StoryStatusStrip(character: _character!),
            Expanded(
              child: _buildContent(
                bgPath: bgPath,
                playerAvatar: playerAvatar,
              ),
            ),
            _buildActionPanel(),
            _StoryBottomBar(
              busy: _busy,
              customOpen: _customOpen && intentMapperOn,
              showPencil: intentMapperOn,
              onStats: _character != null
                  ? () => _openStatsSheet(context, allSkills)
                  : null,
              onHistory: _history.isNotEmpty
                  ? () => _openHistoryLog(context, playerAvatar)
                  : null,
              onToggleCustom: intentMapperOn
                  ? () => setState(() => _customOpen = !_customOpen)
                  : null,
              onSubmitCustom: (text) => _submitFreeText(text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({String? bgPath, String? playerAvatar}) {
    if (_error != null && _payload == null) {
      return _ErrorView(message: _error!, onRetry: _bootstrap);
    }
    if (_busy && _payload == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final p = _payload!;

    return LayoutBuilder(
      builder: (context, constraints) {
        _onViewportHeightChanged(constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bgPath != null)
              Opacity(
                opacity: 0.32,
                child: Image.asset(
                  bgPath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _ProceduralBackdrop(),
                ),
              )
            else
              const _ProceduralBackdrop(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xCC0E0B07)],
                ),
              ),
            ),
            ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              children: [
                // --- chat history (previous nodes + player choices) ---
                for (final entry in _history) ...[
                  _DmBubble(
                    body: entry.body,
                    speaker: entry.speaker,
                    isPivotal: false,
                    isEnding: false,
                  ),
                  const SizedBox(height: 8),
                  _PlayerBubble(
                      label: entry.choiceLabel, avatarPath: playerAvatar),
                  const SizedBox(height: 10),
                ],
                // --- current node ---
                // Hidden during transitions (_busy after a choice was made) to
                // prevent the old node from rendering twice (once as the last
                // history entry, once as the "current" bubble). On initial load
                // _history is empty so the spinner returns before reaching here.
                if (!_busy || _history.isEmpty) ...[
                  if (p.isPivotal) const _PivotalSystemLine(),
                  _DmBubble(
                    key: ValueKey('bubble_${p.nodeId}'),
                    body: p.body,
                    speaker: p.speaker,
                    isPivotal: p.isPivotal,
                    isEnding: p.isEnding,
                    aiRoleUsed: p.aiRoleUsed,
                    animate: _isTyping,
                    onAnimationDone: _onBubbleAnimationDone,
                  ),
                  if (p.endedCampaign != null) ...[
                    const SizedBox(height: 12),
                    _EndingBubble(ending: p.endedCampaign!),
                  ],
                ],
                // Waiting bubble only during transitions (initial load uses the
                // full-screen spinner above, so _history is empty then).
                if (_busy && _history.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const _WaitingBubble(),
                ],
                if (_error != null && _payload != null) ...[
                  const SizedBox(height: 10),
                  _InlineError(message: _error!, onRetry: _bootstrap),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  // Action panel — suppressed while typewriter is running, same as GameScreen.
  Widget _buildActionPanel() {
    final p = _payload;
    final isCombat =
        p != null && p.isCombat && p.pendingCombatId != null;
    final opts = p?.options ?? [];
    final hasEnded = p?.endedCampaign != null;

    final canAct =
        !_isTyping && !_busy && !hasEnded && !isCombat && opts.isNotEmpty;
    final showCombat = isCombat && !_isTyping;

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
        child: showCombat
            ? const _CombatQueuedPanel(key: ValueKey('combat'))
            : canAct
                ? _ActionPanel(
                    key: const ValueKey('panel'),
                    options: opts,
                    isPivotal: p!.isPivotal,
                    onTap: _take,
                  )
                : const SizedBox(
                    key: ValueKey('hidden'), width: double.infinity),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar  (identical to GameScreen._TopBar)
// ---------------------------------------------------------------------------

class _StoryTopBar extends StatelessWidget {
  const _StoryTopBar({required this.campaign, required this.onBack});

  final Campaign? campaign;
  final VoidCallback onBack;

  static const _phases = ['intro', 'rising', 'climax', 'resolution'];

  @override
  Widget build(BuildContext context) {
    final name = campaign?.name.toUpperCase() ?? '...';
    final phase = campaign?.phase ?? '';
    final phaseIdx = _phases.indexOf(phase);

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
          PixelBackButton(onTap: onBack),
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
                  name,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTheme.pressStart(11, color: PixelColors.accentGold),
                ),
                if (phase.isNotEmpty)
                  Text(
                    'CHAPTER · ${phase.toUpperCase()}',
                    style: AppTheme.pressStart(
                        7, color: PixelColors.textMuted),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_phases.length, (i) {
              final reached = i <= phaseIdx;
              final color = reached
                  ? (i == phaseIdx
                      ? PixelColors.accentGold
                      : PixelColors.accentGreen)
                  : PixelColors.borderSoft;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(width: 14, height: 14, color: color),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status strip  (identical to GameScreen._StatusStrip)
// ---------------------------------------------------------------------------

class _StoryStatusStrip extends StatelessWidget {
  const _StoryStatusStrip({required this.character});
  final CampaignCharacter character;

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
              current: character.hp,
              max: character.maxHp,
              fillColor: PixelColors.hpBar,
              compact: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PixelProgressBar(
              label: character.resourceType.toUpperCase(),
              current: character.resourceCurrent,
              max: character.resourceMax,
              fillColor: character.resourceType == 'mp'
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

// ---------------------------------------------------------------------------
// Action panel  (mirrors ActionPanel + ConditionalActionPanel headers)
// ---------------------------------------------------------------------------

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.options,
    required this.isPivotal,
    required this.onTap,
    super.key,
  });

  final List<StoryOption> options;
  final bool isPivotal;
  final void Function(StoryOption) onTap;

  @override
  Widget build(BuildContext context) {
    final tone = isPivotal ? PixelColors.accentRed : PixelColors.accentGold;
    final label = isPivotal ? 'PIVOTAL CHOICE' : 'YOUR TURN';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header strip — matches ConditionalActionPanel._PromptHeader.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          decoration: BoxDecoration(
            color: PixelColors.panelBackground,
            border: Border(top: BorderSide(color: tone, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, color: tone),
              const SizedBox(width: 8),
              Text(label, style: AppTheme.pressStart(9, color: tone)),
            ],
          ),
        ),
        // Options — matches ActionPanel layout.
        Container(
          color: PixelColors.panelBackground,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: PixelButton(
                    label: o.locked
                        ? '${o.label}  [${o.lockReason ?? 'locked'}]'
                        : o.label,
                    icon: o.locked
                        ? Icons.lock_outline
                        : Icons.arrow_forward,
                    tone: o.locked
                        ? PixelButtonTone.neutral
                        : (isPivotal
                            ? PixelButtonTone.danger
                            : PixelButtonTone.gold),
                    fullWidth: true,
                    onPressed: o.locked ? null : () => onTap(o),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar  (mirrors GameScreen._BottomBar with inline free-text)
// ---------------------------------------------------------------------------

class _StoryBottomBar extends StatefulWidget {
  const _StoryBottomBar({
    required this.busy,
    required this.customOpen,
    required this.showPencil,
    required this.onStats,
    required this.onHistory,
    required this.onToggleCustom,
    required this.onSubmitCustom,
  });

  final bool busy;
  final bool customOpen;
  final bool showPencil;
  final VoidCallback? onStats;
  final VoidCallback? onHistory;
  final VoidCallback? onToggleCustom;
  final void Function(String) onSubmitCustom;

  @override
  State<_StoryBottomBar> createState() => _StoryBottomBarState();
}

class _StoryBottomBarState extends State<_StoryBottomBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isNotEmpty && !widget.busy) {
      _ctrl.clear();
      widget.onSubmitCustom(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(top: BorderSide(color: PixelColors.borderSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.bar_chart,
                    color: PixelColors.accentGold),
                tooltip: 'Stats',
                onPressed: widget.onStats,
              ),
              IconButton(
                icon: const Icon(Icons.menu_book,
                    color: PixelColors.accentGold),
                tooltip: 'Story log',
                onPressed: widget.onHistory,
              ),
              if (widget.showPencil)
                IconButton(
                  icon: Icon(
                    widget.customOpen
                        ? Icons.expand_more
                        : Icons.edit,
                    color: PixelColors.accentGold,
                  ),
                  tooltip: 'Free-text action',
                  onPressed: widget.onToggleCustom,
                ),
              if (widget.customOpen) ...[
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: AppTheme.vt323(20),
                    enabled: !widget.busy,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'What do you do?',
                      filled: true,
                      fillColor: PixelColors.panelInner,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide:
                            BorderSide(color: PixelColors.borderSoft),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                PixelButton(
                  label: 'Send',
                  icon: Icons.send,
                  onPressed: widget.busy ? null : _submit,
                ),
              ] else
                Expanded(
                  child: Text(
                    'Tap an option above, or use the pencil for free text.',
                    style:
                        AppTheme.vt323(16, color: PixelColors.textMuted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DM bubble
// ---------------------------------------------------------------------------

class _DmBubble extends StatelessWidget {
  const _DmBubble({
    required this.body,
    required this.speaker,
    required this.isPivotal,
    required this.isEnding,
    this.aiRoleUsed,
    this.animate = false,
    this.onAnimationDone,
    super.key,
  });

  final String body;
  final String? speaker;
  final bool isPivotal;
  final bool isEnding;
  final String? aiRoleUsed;
  // If true, body is revealed via TypewriterText instead of a plain Text.
  final bool animate;
  final VoidCallback? onAnimationDone;

  static const _dmAvatar = 'assets/images/logo/dungeonku_app-icon.png';

  @override
  Widget build(BuildContext context) {
    final speakerLabel =
        speaker != null ? speaker!.toUpperCase() : 'DUNGEON MASTER';
    final bubbleColor =
        isPivotal ? PixelColors.parchment : PixelColors.panelBackground;
    final borderColor =
        isPivotal ? PixelColors.accentGold : PixelColors.borderHighlight;
    final innerBorderColor =
        isPivotal ? PixelColors.parchmentDark : PixelColors.borderSoft;
    final textColor =
        isPivotal ? PixelColors.textOnParchment : PixelColors.textOnInk;
    final fontSize = isEnding ? 20.0 : 18.0;
    final textStyle = AppTheme.vt323(fontSize, color: textColor);

    final Widget textWidget = animate
        ? TypewriterText(
            text: body,
            style: textStyle,
            onDone: onAnimationDone,
          )
        : Text(body, style: textStyle);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: PixelColors.inkBackground,
            border:
                Border.all(color: PixelColors.accentGold, width: 2),
          ),
          child: const AssetOrNetworkImage(
              imageUrl: _dmAvatar, fit: BoxFit.cover),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 6,
                        height: 6,
                        color: PixelColors.accentGold),
                    const SizedBox(width: 6),
                    Text(speakerLabel,
                        style: AppTheme.pressStart(
                            8, color: PixelColors.accentGold)),
                    if (isPivotal) ...[
                      const SizedBox(width: 8),
                      Text('❖ PIVOTAL',
                          style: AppTheme.pressStart(
                              7, color: PixelColors.accentGold)),
                    ],
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: PixelPanel(
                  color: bubbleColor,
                  borderColor: borderColor,
                  innerBorderColor: innerBorderColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (aiRoleUsed != null) ...[
                        _AiBadge(role: aiRoleUsed!),
                        const SizedBox(height: 6),
                      ],
                      textWidget,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Player bubble  (right-aligned, mirrors GameScreen player bubbles)
// ---------------------------------------------------------------------------

class _PlayerBubble extends StatelessWidget {
  const _PlayerBubble({required this.label, this.avatarPath});
  final String label;
  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 6,
                        height: 6,
                        color: PixelColors.textPlayer),
                    const SizedBox(width: 6),
                    Text('YOU',
                        style: AppTheme.pressStart(
                            8, color: PixelColors.textPlayer)),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: PixelPanel(
                  color: PixelColors.panelInner,
                  borderColor: PixelColors.borderSoft,
                  innerBorderColor: PixelColors.borderSoft,
                  child: Text(label,
                      style: AppTheme.vt323(
                          20, color: PixelColors.textPlayer)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: PixelColors.inkBackground,
            border:
                Border.all(color: PixelColors.textPlayer, width: 2),
          ),
          child: avatarPath != null
              ? AssetOrNetworkImage(
                  imageUrl: avatarPath!, fit: BoxFit.cover)
              : const Icon(Icons.person,
                  color: PixelColors.textPlayer, size: 20),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Misc widgets
// ---------------------------------------------------------------------------

class _ProceduralBackdrop extends StatelessWidget {
  const _ProceduralBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [Color(0xFF1E1A14), Color(0xFF0E0B07)],
        ),
      ),
    );
  }
}

class _PivotalSystemLine extends StatelessWidget {
  const _PivotalSystemLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Expanded(
              child:
                  Divider(color: PixelColors.accentGold, thickness: 1)),
          const SizedBox(width: 8),
          Text('❖  PIVOTAL MOMENT  ❖',
              style: AppTheme.pressStart(
                  7, color: PixelColors.accentGold)),
          const SizedBox(width: 8),
          const Expanded(
              child:
                  Divider(color: PixelColors.accentGold, thickness: 1)),
        ],
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final label = role == 'npc_voice' ? 'AI VOICE' : 'AI FLAVOR';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PixelColors.panelInner,
        border: Border.all(color: PixelColors.accentGold, width: 1),
      ),
      child: Text('✨  $label',
          style:
              AppTheme.pressStart(7, color: PixelColors.accentGold)),
    );
  }
}

class _EndingBubble extends StatelessWidget {
  const _EndingBubble({required this.ending});
  final EndedCampaign ending;

  @override
  Widget build(BuildContext context) {
    final isWin = ending.outcome == 'success';
    final tone =
        isWin ? PixelColors.accentGreen : PixelColors.accentRed;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PixelColors.panelInner,
        border: Border.all(color: tone, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isWin ? 'CAMPAIGN COMPLETE' : 'CAMPAIGN ENDED',
              style: AppTheme.pressStart(12, color: tone)),
          if (ending.summarySeed.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(ending.summarySeed,
                style: AppTheme.vt323(
                    16, color: PixelColors.textOnInk)),
          ],
        ],
      ),
    );
  }
}

class _CombatQueuedPanel extends StatelessWidget {
  const _CombatQueuedPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(
            top: BorderSide(color: PixelColors.accentRed, width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PixelSpinner(size: 14),
          const SizedBox(width: 10),
          Text('ENTERING COMBAT...',
              style: AppTheme.pressStart(
                  9, color: PixelColors.accentRed)),
        ],
      ),
    );
  }
}

class _WaitingBubble extends StatelessWidget {
  const _WaitingBubble();
  static const _dmAvatar = 'assets/images/logo/dungeonku_app-icon.png';

  static const _phrases = [
    'The DM weaves the tale...',
    'Threads of fate gather...',
    'The DM consults the omens...',
    'Spinning the next moment...',
    'The dice murmur to the DM...',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: PixelColors.inkBackground,
            border:
                Border.all(color: PixelColors.accentGold, width: 2),
          ),
          child: const AssetOrNetworkImage(
              imageUrl: _dmAvatar, fit: BoxFit.cover),
        ),
        const SizedBox(width: 8),
        PixelPanel(
          color: PixelColors.panelBackground,
          borderColor: PixelColors.borderSoft,
          innerBorderColor: PixelColors.borderSoft,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelSpinner(size: 12),
              const SizedBox(width: 8),
              Text(_phrases[0],
                  style: AppTheme.vt323(
                      18, color: PixelColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('STORY ENGINE ERROR',
                style: AppTheme.pressStart(
                    11, color: PixelColors.accentRed)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: AppTheme.vt323(16,
                    color: PixelColors.textOnInk)),
            const SizedBox(height: 16),
            PixelButton(
                label: 'RETRY',
                icon: Icons.refresh,
                onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PixelColors.panelInner,
        border: Border.all(color: PixelColors.accentRed, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: AppTheme.vt323(
                    14, color: PixelColors.accentRed)),
          ),
          const SizedBox(width: 8),
          PixelButton(
              label: 'RETRY',
              icon: Icons.refresh,
              onPressed: onRetry),
        ],
      ),
    );
  }
}
