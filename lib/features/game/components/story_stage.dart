import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/utils/asset_index.dart';
import 'package:dungeonku/core/utils/story_assets.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';

/// A light-novel / VN style stage rendered above the action panel.
///
/// Layers (bottom → top):
///   1. Background scene (Image.asset) or procedural fallback.
///   2. Vignette + parchment-tinted overlay.
///   3. Optional enemy portrait (left), player portrait (right).
///   4. Dialogue panel with speaker name + typed-out narration.
///
/// Tapping the dialogue:
///   - while typing → reveals full text instantly
///   - when fully shown → opens [onTapHistory] (the chat log).
class StoryStage extends ConsumerWidget {
  const StoryStage({
    required this.campaign,
    required this.character,
    required this.messages,
    required this.combat,
    required this.onTapHistory,
    super.key,
  });

  final Campaign campaign;
  final CampaignCharacter character;
  final List<GameMessage> messages;
  final CombatTurnResult? combat;
  final VoidCallback onTapHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetIndexAsync = ref.watch(assetIndexProvider);
    final charactersAsync = ref.watch(charactersListProvider);

    return assetIndexAsync.when(
      loading: () => const _Fallback(text: 'Setting the scene...'),
      error: (_, __) => const _Fallback(text: 'The scene refuses to load.'),
      data: (index) {
        final resolver = StoryAssetResolver(index);
        final roster = charactersAsync.valueOrNull ?? const [];
        final base = roster.isEmpty
            ? null
            : roster.firstWhere(
                (c) => c.id == character.characterId,
                orElse: () => roster.first,
              );

        final latest = _latestVisibleMessage();
        final inCombat = combat != null && combat!.kind == 'ongoing';
        final firstEnemy = (combat?.enemies.isNotEmpty ?? false)
            ? combat!.enemies.first
            : null;

        final bgPath = resolver.backgroundFor(
          templateId: campaign.templateId,
          phase: campaign.phase,
          situationType: latest?.situationType,
          inCombat: inCombat,
          bossName: firstEnemy?.isBoss == true ? firstEnemy?.name : null,
          element: firstEnemy?.element ?? character.baseElement,
        );
        final playerPath = resolver.playerPortrait(
          avatarId: base?.avatarId,
          classId: base?.classId,
        );
        final enemyPath = inCombat
            ? resolver.enemyPortrait(
                bossName: firstEnemy?.name,
                element: firstEnemy?.element,
                isBoss: firstEnemy?.isBoss ?? false,
              )
            : null;
        // Treat the first DM narration as pivotal so the opening CG (named
        // <template>_opening.png by convention) lights up automatically.
        GameMessage? firstDm;
        for (final m in messages) {
          if (m.role == 'dm') {
            firstDm = m;
            break;
          }
        }
        final isOpeningBeat =
            latest != null && firstDm != null && latest.id == firstDm.id;
        final cgPath = resolver.storyArt(
          templateId: campaign.templateId,
          phase: campaign.phase,
          pivotal: (latest?.pivotalMoment ?? false) || isOpeningBeat,
        );

        return _Stage(
          bgPath: bgPath,
          cgPath: cgPath,
          enemyPath: enemyPath,
          playerPath: playerPath,
          enemyName: firstEnemy?.name,
          playerName: base?.name ?? 'Hero',
          message: latest,
          onTapHistory: onTapHistory,
        );
      },
    );
  }

  GameMessage? _latestVisibleMessage() {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == 'system') continue;
      return m;
    }
    return null;
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.bgPath,
    required this.cgPath,
    required this.enemyPath,
    required this.playerPath,
    required this.enemyName,
    required this.playerName,
    required this.message,
    required this.onTapHistory,
  });

  final String? bgPath;
  final String? cgPath;
  final String? enemyPath;
  final String? playerPath;
  final String? enemyName;
  final String playerName;
  final GameMessage? message;
  final VoidCallback onTapHistory;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background — file if available, else procedural pixel gradient.
          if (cgPath != null)
            Image.asset(cgPath!,
                fit: BoxFit.cover, filterQuality: FilterQuality.none)
          else if (bgPath != null)
            Image.asset(bgPath!,
                fit: BoxFit.cover, filterQuality: FilterQuality.none)
          else
            const _ProceduralBackdrop(),

          // 2. Vignette so text always reads.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // 3. Portraits.
          if (enemyPath != null)
            Positioned(
              left: -8,
              bottom: 110,
              top: 16,
              child: _Portrait(
                path: enemyPath!,
                label: enemyName ?? '???',
                facingRight: true,
                tone: PixelColors.accentRed,
              ),
            ),
          if (playerPath != null)
            Positioned(
              right: -8,
              bottom: 110,
              top: 16,
              child: _Portrait(
                path: playerPath!,
                label: playerName,
                facingRight: false,
                tone: PixelColors.accentGold,
              ),
            ),

          // 4. Dialogue panel pinned to bottom.
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _DialoguePanel(
              message: message,
              speakerOverride:
                  message?.role == 'player' ? playerName.toUpperCase() : null,
              onTap: onTapHistory,
            ),
          ),
        ],
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.path,
    required this.label,
    required this.facingRight,
    required this.tone,
  });

  final String path;
  final String label;
  final bool facingRight;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      path,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      alignment: facingRight ? Alignment.bottomLeft : Alignment.bottomRight,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    return SizedBox(
      width: 180,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment:
            facingRight ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Expanded(
            child: facingRight
                ? image
                : Transform.flip(flipX: false, child: image),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: PixelColors.borderOuter,
            child: Text(
              label.toUpperCase(),
              style: AppTheme.pressStart(8, color: tone),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _DialoguePanel extends StatefulWidget {
  const _DialoguePanel({
    required this.message,
    required this.speakerOverride,
    required this.onTap,
  });

  final GameMessage? message;
  final String? speakerOverride;
  final VoidCallback onTap;

  @override
  State<_DialoguePanel> createState() => _DialoguePanelState();
}

class _DialoguePanelState extends State<_DialoguePanel> {
  String _renderedFor = '';
  bool _skip = false;
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_DialoguePanel old) {
    super.didUpdateWidget(old);
    if (old.message?.id != widget.message?.id) {
      setState(() => _skip = false);
      // The previous message may have been long and the user may have
      // scrolled to read it; without this reset the new (often shorter)
      // message would render outside the viewport and look invisible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final text = m?.content ?? 'The world holds its breath...';
    final speaker = widget.speakerOverride ??
        (m == null
            ? 'NARRATOR'
            : m.role == 'player'
                ? 'YOU'
                : m.role == 'dm'
                    ? 'DUNGEON MASTER'
                    : 'NARRATOR');
    final isPlayer = m?.role == 'player';
    final speakerColor =
        isPlayer ? PixelColors.textPlayer : PixelColors.accentGold;

    // Identifier so we don't re-animate the same text between rebuilds.
    if (_renderedFor != (m?.id ?? '__none__')) {
      _renderedFor = m?.id ?? '__none__';
    }

    final duration =
        Duration(milliseconds: (text.length * 16).clamp(400, 4000));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_skip) {
          setState(() => _skip = true);
        } else {
          widget.onTap();
        }
      },
      child: PixelPanel(
        color: PixelColors.parchment,
        borderColor: PixelColors.borderHighlight,
        innerBorderColor: PixelColors.parchmentDark,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, color: speakerColor),
                const SizedBox(width: 8),
                Text(speaker,
                    style: AppTheme.pressStart(10, color: speakerColor)),
                const Spacer(),
                Text('TAP',
                    style:
                        AppTheme.pressStart(8, color: PixelColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                controller: _scroll,
                child: _skip
                    ? Text(
                        text,
                        style: AppTheme.vt323(20,
                            color: PixelColors.textOnParchment),
                      )
                    : TweenAnimationBuilder<int>(
                        key: ValueKey(_renderedFor),
                        tween: IntTween(begin: 0, end: text.length),
                        duration: duration,
                        builder: (_, value, __) {
                          // Auto-track typing so the most recent character is
                          // always visible (typewriter effect should never
                          // outrun the viewport).
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!_scroll.hasClients) return;
                            final max = _scroll.position.maxScrollExtent;
                            if (max > 0 && _scroll.offset < max) {
                              _scroll.jumpTo(max);
                            }
                          });
                          return Text(
                            text.substring(0, value.clamp(0, text.length)),
                            style: AppTheme.vt323(20,
                                color: PixelColors.textOnParchment),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: PixelColors.inkBackground,
      child: Center(
        child:
            Text(text, style: AppTheme.vt323(18, color: PixelColors.textMuted)),
      ),
    );
  }
}

class _ProceduralBackdrop extends StatelessWidget {
  const _ProceduralBackdrop();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E1A14),
            Color(0xFF2A2418),
            Color(0xFF1E1A14),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _PixelStarsPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PixelStarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x33D4AF37);
    const cell = 22.0;
    for (double y = 6; y < size.height; y += cell) {
      for (double x = ((y / cell).round() % 2) * (cell / 2);
          x < size.width;
          x += cell) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
