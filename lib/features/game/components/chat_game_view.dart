import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/utils/asset_index.dart';
import 'package:dungeonku/core/utils/story_assets.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/pixel_spinner.dart';
import 'package:dungeonku/core/widgets/typewriter_text.dart';
import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';

/// Messaging-app style game view.
///
/// Each message is a chat bubble with the speaker’s avatar pinned to its
/// edge. The player’s bubbles align to the right (their portrait), DM &
/// NPC bubbles align to the left (the DM crest, or an enemy portrait when
/// the latest combat target is known). System lines collapse to a centred
/// divider so the conversation reads naturally.
///
/// A subtle backdrop image (resolved via [StoryAssetResolver] from the
/// current scene) sits under everything at low opacity so the chat keeps
/// the D&D vibe without overwhelming readability.
class ChatGameView extends ConsumerStatefulWidget {
  const ChatGameView({
    required this.campaign,
    required this.character,
    required this.messages,
    required this.combat,
    required this.busy,
    this.onTypewriterActiveChange,
    super.key,
  });

  final Campaign campaign;
  final CampaignCharacter character;
  final List<GameMessage> messages;
  final CombatTurnResult? combat;
  final bool busy;

  /// Fires `true` when at least one non-player message in the visible list
  /// is still typewriter-animating, and `false` once everything has settled.
  /// Use it to suppress the action panel until the DM finishes “speaking”.
  final ValueChanged<bool>? onTypewriterActiveChange;

  @override
  ConsumerState<ChatGameView> createState() => _ChatGameViewState();
}

class _ChatGameViewState extends ConsumerState<ChatGameView> {
  final _scrollCtrl = ScrollController();

  /// IDs of messages that were already rendered at least once.
  /// Messages NOT in this set get the typewriter animation; once
  /// finished (or if they belong to the player) they're added here.
  final _seenIds = <String>{};

  /// Last value we fired through [ChatGameView.onTypewriterActiveChange].
  /// We only fire on transitions to avoid setState storms.
  bool _lastTypewriterActive = false;

  /// Periodic timer that nudges the list to the bottom while the typewriter
  /// is mid-animation. Without this, the user would have to scroll manually
  /// every time the DM types a longer-than-viewport narration.
  Timer? _autoScrollTimer;

  /// Last viewport height we observed inside the LayoutBuilder. We use this
  /// to detect viewport shrinks (action panel slides up, keyboard opens) and
  /// keep the latest message pinned to the bottom — otherwise the new panel
  /// would slide *over* the freshly-revealed DM bubble.
  double _lastViewportHeight = 0;

  // Standard messenger UX:
  //   index 0          = oldest (visual TOP)
  //   index last       = newest (visual BOTTOM)
  //   typing indicator = appended after the last message
  // We jump-scroll to the bottom on first paint so the player lands on the
  // latest beat. Subsequent updates animate to the bottom. We schedule the
  // scroll via a *double* post-frame callback because Flutter's ListView is
  // lazy — maxScrollExtent isn't accurate until layout has run for the new
  // item; one extra frame is enough to settle it.

  @override
  void initState() {
    super.initState();
    // Mark all initial messages as seen so they don't animate.
    for (final m in widget.messages) {
      _seenIds.add(m.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animate: false);
      _notifyTypewriterIfChanged();
    });
  }

  @override
  void didUpdateWidget(ChatGameView old) {
    super.didUpdateWidget(old);
    final newCame = widget.messages.length > old.messages.length ||
        (widget.busy && !old.busy);
    if (newCame) _scrollToBottom();
    // Recompute active-typewriter state after the new message list lands;
    // a fresh DM message just arrived in `widget.messages` not yet in
    // `_seenIds`, so we expect the callback to flip true → false on done.
    _notifyTypewriterIfChanged();
  }

  bool _computeTypewriterActive() {
    for (final m in widget.messages) {
      if (m.role == 'player' || m.role == 'system') continue;
      if (!_seenIds.contains(m.id)) return true;
    }
    return false;
  }

  void _notifyTypewriterIfChanged() {
    final next = _computeTypewriterActive();
    if (next == _lastTypewriterActive) return;
    _lastTypewriterActive = next;
    if (next) {
      _startAutoScroll();
    } else {
      _stopAutoScroll();
    }
    final cb = widget.onTypewriterActiveChange;
    if (cb != null) {
      // Defer to post-frame so we don't call setState in the parent during a
      // build pass.
      WidgetsBinding.instance.addPostFrameCallback((_) => cb(next));
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    // 80ms is a touch faster than the typewriter's min char delay (90ms
    // worst-case for very long text), so the latest character is on screen
    // before the next one paints.
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_lastTypewriterActive) {
        _stopAutoScroll();
        return;
      }
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      // Use jumpTo — calling animateTo every 80ms would queue overlapping
      // animations and feel jittery. The timer cadence already gives us a
      // smooth-feeling follow.
      if ((_scrollCtrl.position.pixels - target).abs() > 0.5) {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      // Second pass: after the new bubble is fully laid out, animate the
      // remaining distance smoothly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        final target = _scrollCtrl.position.maxScrollExtent;
        if (animate) {
          _scrollCtrl.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollCtrl.jumpTo(target);
        }
      });
    });
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indexAsync = ref.watch(assetIndexProvider);
    final charactersAsync = ref.watch(charactersListProvider);
    // The LayoutBuilder lets us detect when the chat's available height
    // changes (e.g. the action panel below it slides up). If we were already
    // at the bottom we re-pin to the bottom in a post-frame callback so the
    // latest bubble doesn't get hidden behind the new panel.
    return LayoutBuilder(
      builder: (context, constraints) {
        _onViewportHeightChanged(constraints.maxHeight);
        return indexAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => _buildList(null, charactersAsync.valueOrNull),
          data: (index) => _buildList(
              StoryAssetResolver(index), charactersAsync.valueOrNull),
        );
      },
    );
  }

  /// Called from the [LayoutBuilder] every time the chat's available height
  /// is computed. We only re-pin to bottom when the viewport SHRINKS —
  /// growing means the panel just retracted and there's no risk of hiding
  /// content. Threshold of 30px on "near bottom" tolerates the rounding /
  /// scroll inertia that's normal at the end of a list.
  void _onViewportHeightChanged(double newHeight) {
    if (newHeight <= 0) return;
    final old = _lastViewportHeight;
    _lastViewportHeight = newHeight;
    if (old <= 0 || newHeight >= old) return;
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final wasNearBottom = (pos.maxScrollExtent - pos.pixels).abs() <= 30;
    if (!wasNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Widget _buildList(StoryAssetResolver? resolver, List<Character>? roster) {
    // Resolve the underlying profile-level character for portrait + name.
    Character? base;
    if (roster != null && roster.isNotEmpty) {
      for (final c in roster) {
        if (c.id == widget.character.characterId) {
          base = c;
          break;
        }
      }
      base ??= roster.first;
    }
    final firstEnemy = (widget.combat?.enemies.isNotEmpty ?? false)
        ? widget.combat!.enemies.first
        : null;
    final inCombat = widget.combat != null && widget.combat!.kind == 'ongoing';
    final bgPath = resolver?.backgroundFor(
      templateId: widget.campaign.templateId,
      phase: widget.campaign.phase,
      situationType: _latestSituation(),
      inCombat: inCombat,
      bossName: firstEnemy?.isBoss == true ? firstEnemy?.name : null,
      element: firstEnemy?.element ?? widget.character.baseElement,
    );
    final playerAvatar = resolver?.playerPortrait(
          avatarId: base?.avatarId,
          classId: base?.classId,
        ) ??
        (base != null ? 'assets/images/avatars/${base.avatarId}.png' : null);
    final enemyAvatar = inCombat
        ? resolver?.enemyPortrait(
            bossName: firstEnemy?.name,
            element: firstEnemy?.element,
            isBoss: firstEnemy?.isBoss ?? false,
          )
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop \u2014 procedural fallback if no image. Low opacity so
        // bubbles stay legible.
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
        // Vertical gradient to lift the chat off the backdrop near the
        // bottom (where action panel + bottom bar sit).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0xCC0E0B07)],
              stops: [0.0, 1.0],
            ),
          ),
        ),
        // Natural top-to-bottom order:
        //   widget.messages[0]    = oldest → rendered at the TOP
        //   widget.messages[last] = newest → rendered at the BOTTOM
        // The typing bubble (when busy) is appended after the last message
        // so it sits just above the action panel.
        ListView.separated(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          itemCount: widget.messages.length + (widget.busy ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i >= widget.messages.length) {
              return _TypingBubble(
                avatarAsset: _dmAvatarAsset,
                seed: widget.messages.length,
              );
            }
            final m = widget.messages[i];
            final shouldAnimate =
                m.role != 'player' && !_seenIds.contains(m.id);
            return _ChatRow(
              message: m,
              playerAvatar: playerAvatar,
              dmAvatar: _dmAvatarAsset,
              enemyAvatar: enemyAvatar,
              enemyName: firstEnemy?.name,
              animate: shouldAnimate,
              onAnimationDone: () {
                _seenIds.add(m.id);
                // Scroll again after the text expands.
                _scrollToBottom();
                _notifyTypewriterIfChanged();
              },
            );
          },
        ),
      ],
    );
  }

  String? _latestSituation() {
    for (var i = widget.messages.length - 1; i >= 0; i--) {
      final s = widget.messages[i].situationType;
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static const _dmAvatarAsset = 'assets/images/logo/dungeonku_app-icon.png';
}

// ---------------------------------------------------------------------------
// Bubbles
// ---------------------------------------------------------------------------

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.message,
    required this.playerAvatar,
    required this.dmAvatar,
    required this.enemyAvatar,
    required this.enemyName,
    this.animate = false,
    this.onAnimationDone,
  });

  final GameMessage message;
  final String? playerAvatar;
  final String dmAvatar;
  final String? enemyAvatar;
  final String? enemyName;
  final bool animate;
  final VoidCallback? onAnimationDone;

  @override
  Widget build(BuildContext context) {
    if (message.role == 'system') return _SystemDivider(text: message.content);
    final isPlayer = message.role == 'player';
    // Pick the bubble's "speaker" \u2014 in combat we want enemy attacks to
    // visibly come from the foe, not the DM persona.
    final isEnemyVoice = !isPlayer &&
        enemyAvatar != null &&
        (message.situationType == 'enemy_attack' ||
            message.situationType == 'enemy_turn');
    final speakerName = isPlayer
        ? 'YOU'
        : (isEnemyVoice
            ? (enemyName ?? 'ENEMY').toUpperCase()
            : 'DUNGEON MASTER');
    final speakerColor = isPlayer
        ? PixelColors.textPlayer
        : (isEnemyVoice ? PixelColors.accentRed : PixelColors.accentGold);
    final bubbleColor = isPlayer
        ? PixelColors.panelInner
        : (message.pivotalMoment
            ? PixelColors.parchment
            : PixelColors.panelBackground);
    final borderColor = isPlayer
        ? PixelColors.borderSoft
        : (isEnemyVoice
            ? PixelColors.accentRed
            : (message.pivotalMoment
                ? PixelColors.accentGold
                : PixelColors.borderHighlight));
    final textStyle = isPlayer
        ? AppTheme.vt323(20, color: PixelColors.textPlayer)
        : (message.pivotalMoment
            ? AppTheme.vt323(20, color: PixelColors.textOnParchment)
            : AppTheme.vt323(20));
    final avatar =
        isPlayer ? playerAvatar : (isEnemyVoice ? enemyAvatar : dmAvatar);

    final Widget textContent = animate
        ? TypewriterText(
            key: ValueKey('tw_${message.id}'),
            text: message.content,
            style: textStyle,
            onDone: onAnimationDone,
          )
        : Text(message.content, style: textStyle);

    final bubble = _Bubble(
      speakerName: speakerName,
      speakerColor: speakerColor,
      bubbleColor: bubbleColor,
      borderColor: borderColor,
      tailOnRight: isPlayer,
      pivotal: message.pivotalMoment && !isPlayer,
      child: textContent,
    );

    final children = <Widget>[
      _AvatarBadge(asset: avatar, tone: speakerColor),
      const SizedBox(width: 8),
      Flexible(child: bubble),
    ];

    return Row(
      mainAxisAlignment:
          isPlayer ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: isPlayer ? children.reversed.toList(growable: false) : children,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.speakerName,
    required this.speakerColor,
    required this.bubbleColor,
    required this.borderColor,
    required this.tailOnRight,
    required this.pivotal,
    required this.child,
  });

  final String speakerName;
  final Color speakerColor;
  final Color bubbleColor;
  final Color borderColor;
  final bool tailOnRight;
  final bool pivotal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment:
            tailOnRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, color: speakerColor),
                const SizedBox(width: 6),
                Text(speakerName,
                    style: AppTheme.pressStart(8, color: speakerColor)),
                if (pivotal) ...[
                  const SizedBox(width: 8),
                  Text('\u2756 PIVOTAL',
                      style: AppTheme.pressStart(7,
                          color: PixelColors.accentGold)),
                ],
              ],
            ),
          ),
          PixelPanel(
            color: bubbleColor,
            borderColor: borderColor,
            innerBorderColor:
                pivotal ? PixelColors.parchmentDark : PixelColors.borderSoft,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.asset, required this.tone});
  final String? asset;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: PixelColors.inkBackground,
        border: Border.all(color: tone, width: 2),
      ),
      child: asset == null
          ? Icon(Icons.help_outline, color: tone, size: 20)
          : AssetOrNetworkImage(imageUrl: asset!, fit: BoxFit.cover),
    );
  }
}

class _SystemDivider extends StatelessWidget {
  const _SystemDivider({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: PixelColors.borderSoft, thickness: 1),
          ),
          const SizedBox(width: 8),
          Text('\u2756  $text  \u2756',
              style: AppTheme.pressStart(7, color: PixelColors.textMuted)),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(color: PixelColors.borderSoft, thickness: 1),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.avatarAsset, required this.seed});
  final String avatarAsset;

  /// Stable per-turn seed (e.g. message count) used to pick which thematic
  /// phrase to show. Stable means the text won't flicker between frames
  /// while the spinner is running.
  final int seed;

  /// Pool of in-character phrases. We pick deterministically by `seed % len`
  /// so subsequent turns naturally rotate through them.
  static const _phrases = <String>[
    'The DM weaves the tale...',
    'Threads of fate gather...',
    'The DM consults the omens...',
    'Spinning the next moment...',
    'The dice murmur to the DM...',
    'The DM peers into the unfolding...',
  ];

  @override
  Widget build(BuildContext context) {
    final phrase = _phrases[seed.abs() % _phrases.length];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _AvatarBadge(asset: avatarAsset, tone: PixelColors.accentGold),
        const SizedBox(width: 8),
        PixelPanel(
          color: PixelColors.panelBackground,
          borderColor: PixelColors.borderSoft,
          innerBorderColor: PixelColors.borderSoft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelSpinner(size: 12),
              const SizedBox(width: 8),
              Text(phrase,
                  style: AppTheme.vt323(18, color: PixelColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

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
          stops: [0.0, 1.0],
        ),
      ),
    );
  }
}
