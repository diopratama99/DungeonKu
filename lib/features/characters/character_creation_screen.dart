import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:collection/collection.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';
import 'package:dungeonku/features/characters/hero_details_screen.dart';

/// Step 1 of character creation. A pure picker \u2014 every class is a
/// tappable card with a representative portrait so the player sees art
/// (not a wall of text) when choosing. Tapping a class pushes
/// [HeroDetailsScreen] (full page) so the avatar/element/name flow
/// can\u2019t silently appear under a long scroll list, which was the
/// confusing behaviour previously.
class CharacterCreationScreen extends ConsumerWidget {
  const CharacterCreationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classDefinitionsProvider);
    final avatarsAsync = ref.watch(avatarTemplatesProvider);

    return Scaffold(
      appBar: RetroAppBar(
        title: 'FORGE A HERO',
        leading: PixelBackButton(onTap: () => context.go('/characters')),
      ),
      body: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (classes) {
          final avatars = avatarsAsync.valueOrNull ?? const <AvatarTemplate>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _Header(),
              const SizedBox(height: 16),
              for (final c in classes) ...[
                _ClassCard(
                  cls: c,
                  // Pick the first portrait that fits this class as the cover.
                  coverUrl: avatars
                          .firstWhereOrNull((a) => a.fitsClass(c.id))
                          ?.imageUrl ??
                      'assets/images/avatars/${c.id}_01.png',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => HeroDetailsScreen(cls: c),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PixelPanel(
      color: PixelColors.parchment,
      borderColor: PixelColors.accentGold,
      innerBorderColor: PixelColors.parchmentDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('\u2756',
                  style:
                      AppTheme.pressStart(14, color: PixelColors.accentGold)),
              const SizedBox(width: 8),
              Text('CHOOSE A CLASS',
                  style: AppTheme.pressStart(12,
                      color: PixelColors.textOnParchment)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Each class shapes your starting stats, skills, and how the world treats you. Tap to read more.',
            style: AppTheme.vt323(18, color: PixelColors.textOnParchment),
          ),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.cls,
    required this.coverUrl,
    required this.onTap,
  });

  final ClassDefinition cls;
  final String coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PixelPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover portrait \u2014 makes the class identifiable at a glance,
            // beats a plain wall of text.
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: PixelColors.inkBackground,
                border:
                    Border.all(color: PixelColors.borderHighlight, width: 2),
              ),
              child: coverUrl.isEmpty
                  ? const ColoredBox(color: PixelColors.panelInner)
                  : AssetOrNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cls.name.toUpperCase(),
                      style: AppTheme.pressStart(13,
                          color: PixelColors.accentGold)),
                  const SizedBox(height: 4),
                  Text(cls.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.vt323(16)),
                  const SizedBox(height: 6),
                  Text(
                    'HP ${cls.startingHp} \u00b7 ${cls.resourceType.toUpperCase()} ${cls.startingResource} \u00b7 AC ${cls.startingAc}',
                    style: AppTheme.pressStart(8, color: PixelColors.textMuted),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4, top: 4),
              child: Icon(Icons.chevron_right, color: PixelColors.borderSoft),
            ),
          ],
        ),
      ),
    );
  }
}
