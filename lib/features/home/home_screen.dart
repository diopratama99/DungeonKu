import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/audio/bgm_manager.dart';
import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/icon_only_button.dart';
import 'package:dungeonku/core/widgets/ornate_frame.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/sparkle_field.dart';
import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';

/// JRPG-style title screen + main menu.
///
/// Layered Stack (back → front):
///   1. Deep-indigo gradient (no longer pure black so the screen has
///      mood without a busy painted backdrop).
///   2. Soft radial highlight behind the logo to focus attention.
///   3. Animated sparkle field — small twinkling particles over the
///      upper portion of the canvas.
///   4. Foreground content (top-bar Settings gear + logo + menu).
///
/// All major frames (Continue button, nav tiles, top-bar gear) wear
/// [OrnateFrame] corner ornaments to break the rectangular monotony.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Idempotent — keeps the menu theme looping across rebuilds.
    ref.read(bgmManagerProvider).playMenu();

    final campaignsAsync = ref.watch(campaignsListProvider);
    final activeCampaign =
        _pickActiveCampaign(campaignsAsync.valueOrNull ?? const []);

    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Warm ink gradient — stays in the parchment/ink family the
          //    app's palette is built on (see `PixelColors`), but with
          //    enough depth (panel brown → ink → deep warm black) that
          //    the screen never reads as a flat black panel.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF2A2418),
                  Color(0xFF1E1A14),
                  Color(0xFF12100B),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // 2. Cool moonlight halo. Steel-blue at low alpha supports
          //    the logo's existing cool accents (d20 face, sword blade,
          //    purple jewels) instead of fighting them — and against
          //    the warm ink backdrop creates a temperature contrast
          //    that adds depth without saturating any one hue.
          const Align(
            alignment: Alignment(0, -0.35),
            child: SizedBox(
              width: 620,
              height: 620,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0x404F8CB0),
                      Color(0x202E5274),
                      Color(0x0012100B),
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 3. Animated sparkles — fewer particles + cubed-sine fade
          //    means each twinkle is rare and dim, so the bg reads as
          //    starry atmosphere rather than dotted noise.
          const Positioned.fill(
            child: SparkleField(count: 18, minSize: 1, maxSize: 3),
          ),
          // 4. Foreground content.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(child: _LogoBlock()),
                  if (activeCampaign != null) ...[
                    _ContinueQuestButton(campaign: activeCampaign),
                    const SizedBox(height: 10),
                  ],
                  PixelButton(
                    label: 'New Adventure',
                    icon: Icons.auto_awesome,
                    iconAsset:
                        'assets/images/icons/processed/support_quill.png',
                    fullWidth: true,
                    onPressed: () => context.push('/characters'),
                  ),
                  const SizedBox(height: 18),
                  const _NavTileRow(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the campaign the player should drop back into when tapping
  /// "Continue Quest" — the most recently played `active` run, or null
  /// if nothing matches (in which case the Continue button hides).
  Campaign? _pickActiveCampaign(List<Campaign> campaigns) {
    final active =
        campaigns.where((c) => c.status == 'active').toList(growable: false);
    if (active.isEmpty) return null;
    active.sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    return active.first;
  }
}

// ---------------------------------------------------------------------------
// Top bar: Settings gear pinned to the right.
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const Spacer(),
          IconOnlyButton(
            iconAsset: 'assets/images/icons/processed/ui_settings.png',
            tooltip: 'Settings',
            fallbackIcon: Icons.settings,
            // 40px button is too cramped for corner studs — they end
            // up looking like noise. Plain bordered button is cleaner.
            ornate: false,
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logo + tagline block.
// ---------------------------------------------------------------------------

class _LogoBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Image.asset(
            'assets/images/logo/dungeonku_logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, __, ___) => Text(
              'DUNGEONKU',
              style: AppTheme.pressStart(28, color: PixelColors.accentGold),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'A Solo Tale of Dice & Daring',
          textAlign: TextAlign.center,
          style: AppTheme.vt323(18, color: PixelColors.textMuted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Primary CTA: Continue Quest. Custom button so we can fit both action
// label *and* campaign name as a subtitle. Wrapped in [OrnateFrame] for
// the corner-stud accents.
// ---------------------------------------------------------------------------

class _ContinueQuestButton extends StatefulWidget {
  const _ContinueQuestButton({required this.campaign});
  final Campaign campaign;

  @override
  State<_ContinueQuestButton> createState() => _ContinueQuestButtonState();
}

class _ContinueQuestButtonState extends State<_ContinueQuestButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const accent = PixelColors.accentGold;
    final offset = _pressed ? 0.0 : 2.0;
    return OrnateFrame(
      color: accent,
      cornerSize: 8,
      inset: 4,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () => context.push('/game/${widget.campaign.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          width: double.infinity,
          transform:
              Matrix4.translationValues(_pressed ? 1 : 0, _pressed ? 1 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: PixelColors.panelInner,
            border: Border.all(color: accent, width: 2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.55),
                offset: Offset(offset, offset),
              ),
            ],
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/images/icons/processed/ui_play.png',
                width: 28,
                height: 28,
                filterQuality: FilterQuality.none,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.play_arrow, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CONTINUE QUEST',
                      style: AppTheme.pressStart(10, color: accent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.campaign.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.vt323(
                        18,
                        color: PixelColors.textOnInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom row of 3 navigation tiles (Settings extracted to top bar). Each
// tile gets its own corner ornaments via [OrnateFrame].
// ---------------------------------------------------------------------------

class _NavTileRow extends StatelessWidget {
  const _NavTileRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _NavTile(
            label: 'Heroes',
            iconAsset: 'assets/images/icons/processed/ui_profile.png',
            route: '/characters',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _NavTile(
            label: 'Tome',
            iconAsset: 'assets/images/icons/processed/support_book.png',
            route: '/campaigns',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _NavTile(
            label: 'Codex',
            iconAsset: 'assets/images/icons/processed/support_scroll_list.png',
            route: '/codex',
          ),
        ),
      ],
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.label,
    required this.iconAsset,
    required this.route,
  });

  final String label;
  final String iconAsset;
  final String route;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const accent = PixelColors.borderSoft;
    // No OrnateFrame here — a ~80px tile is too small to host visible
    // corner ornaments without them dominating the silhouette. The
    // gold label + brass border + pixel icon already give it character.
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () => context.push(widget.route),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform:
            Matrix4.translationValues(_pressed ? 1 : 0, _pressed ? 1 : 0, 0),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: PixelColors.panelInner,
          border: Border.all(color: accent, width: 2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.4),
              offset: Offset(_pressed ? 0 : 2, _pressed ? 0 : 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              widget.iconAsset,
              width: 36,
              height: 36,
              filterQuality: FilterQuality.none,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.help_outline, color: accent, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              widget.label.toUpperCase(),
              style: AppTheme.pressStart(9, color: PixelColors.accentGold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
