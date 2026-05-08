import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/utils/element_palette.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/element_icon.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';

const int kMaxCharacters = 3;

class CharactersScreen extends ConsumerWidget {
  const CharactersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charactersAsync = ref.watch(charactersListProvider);
    final avatarsAsync = ref.watch(avatarTemplatesProvider);
    final classesAsync = ref.watch(classDefinitionsProvider);

    return Scaffold(
      appBar: const RetroAppBar(title: 'PARTY ROSTER'),
      body: charactersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Error: $e', style: AppTheme.vt323(18))),
        data: (characters) {
          // Wait for the reference data to land before rendering rows so we
          // don't crash on empty avatar/class lookups during a cold start.
          if (classesAsync.isLoading ||
              avatarsAsync.isLoading ||
              classesAsync.hasError ||
              avatarsAsync.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          final classes = classesAsync.valueOrNull ?? const [];
          final avatars = avatarsAsync.valueOrNull ?? const [];
          final slots = List<Character?>.generate(
            kMaxCharacters,
            (i) => i < characters.length ? characters[i] : null,
          );

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: kMaxCharacters,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final c = slots[i];
              if (c == null) return _EmptySlotCard(slotIndex: i);
              final cls = classes.firstWhereOrNull((k) => k.id == c.classId);
              final avatar =
                  avatars.firstWhereOrNull((a) => a.id == c.avatarId);
              return _CharacterCard(
                character: c,
                cls: cls,
                avatarUrl: avatar?.imageUrl ??
                    'assets/images/avatars/${c.avatarId}.png',
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptySlotCard extends StatelessWidget {
  const _EmptySlotCard({required this.slotIndex});
  final int slotIndex;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/characters/new'),
      child: PixelPanel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: PixelColors.inkBackground,
                  border: Border.all(color: PixelColors.borderSoft, width: 2),
                ),
                child: Center(
                  child: Text('+',
                      style: AppTheme.pressStart(32,
                          color: PixelColors.borderSoft)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SLOT ${slotIndex + 1}',
                        style: AppTheme.pressStart(11,
                            color: PixelColors.borderSoft)),
                    const SizedBox(height: 4),
                    Text('EMPTY',
                        style: AppTheme.pressStart(9,
                            color: PixelColors.textMuted)),
                    const SizedBox(height: 8),
                    Text('Tap to forge a hero.',
                        style:
                            AppTheme.vt323(18, color: PixelColors.textMuted)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.chevron_right, color: PixelColors.borderSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterCard extends ConsumerWidget {
  const _CharacterCard({
    required this.character,
    required this.cls,
    required this.avatarUrl,
  });

  final Character character;
  final ClassDefinition? cls;
  final String avatarUrl;

  Future<void> _confirmDelete(BuildContext ctx, WidgetRef ref) async {
    final repo = ref.read(charactersRepositoryProvider);
    final activeCount = await repo.activeCampaignCount(character.id);
    if (!ctx.mounted) return;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: PixelColors.panelBackground,
        title:
            Text('Delete ${character.name}?', style: AppTheme.pressStart(12)),
        content: Text(
          activeCount > 0
              ? 'This character is in $activeCount active campaign(s). Those campaigns will reference a deleted character. Continue?'
              : 'Permanently delete ${character.name}? This cannot be undone.',
          style: AppTheme.vt323(18),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: Text('Cancel', style: AppTheme.pressStart(10))),
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child: Text('Delete',
                  style:
                      AppTheme.pressStart(10, color: PixelColors.accentRed))),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.delete(character.id);
    ref.invalidate(charactersListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final className = cls?.name ?? character.classId.toUpperCase();
    final tone = elementTone(character.baseElement);
    // Pull the top three stats so the player gets a build-at-a-glance.
    final entries = character.stats.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    final topStats = entries.take(3).toList(growable: false);

    return PixelPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Framed portrait — gold border + inner ink mat so the
                // pixel art reads as a heraldic crest, not a thumbnail.
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: PixelColors.inkBackground,
                    border: Border.all(
                        color: PixelColors.borderHighlight, width: 2),
                  ),
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: AssetOrNetworkImage(
                      imageUrl: avatarUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              character.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.pressStart(13,
                                  color: PixelColors.accentGold),
                            ),
                          ),
                          // Overflow menu — keeps the destructive Erase
                          // action one tap away without polluting the row
                          // with a second wide button.
                          _CharacterMenu(
                            onErase: () => _confirmDelete(context, ref),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        className.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.pressStart(9,
                            color: PixelColors.textOnInk),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElementIcon(element: character.baseElement, size: 18),
                          const SizedBox(width: 6),
                          Text(character.baseElement.toUpperCase(),
                              style: AppTheme.pressStart(8, color: tone)),
                          const SizedBox(width: 12),
                          if (cls != null)
                            Text(
                              cls!.resourceType.toUpperCase(),
                              style: AppTheme.pressStart(8,
                                  color: PixelColors.textMuted),
                            ),
                        ],
                      ),
                      if (topStats.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in topStats)
                              _StatChip(label: s.key, value: s.value),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Subtle gold separator so the action area reads as a banner.
            Container(height: 1, color: PixelColors.borderSoft),
            const SizedBox(height: 12),
            PixelButton(
              label: 'Begin Quest',
              icon: Icons.play_arrow,
              fullWidth: true,
              onPressed: () =>
                  context.go('/campaigns/new?character_id=${character.id}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: PixelColors.panelInner,
        border: Border.all(color: PixelColors.borderSoft, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: AppTheme.pressStart(8, color: PixelColors.textMuted)),
          const SizedBox(width: 4),
          Text('$value',
              style: AppTheme.pressStart(9, color: PixelColors.accentGold)),
        ],
      ),
    );
  }
}

class _CharacterMenu extends StatelessWidget {
  const _CharacterMenu({required this.onErase});
  final VoidCallback onErase;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: PixelColors.borderSoft),
      color: PixelColors.panelBackground,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: PixelColors.borderHighlight, width: 2),
        borderRadius: BorderRadius.zero,
      ),
      onSelected: (v) {
        if (v == 'erase') onErase();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'erase',
          child: Row(
            children: [
              const Icon(Icons.delete, size: 16, color: PixelColors.accentRed),
              const SizedBox(width: 8),
              Text('Erase',
                  style: AppTheme.pressStart(9, color: PixelColors.accentRed)),
            ],
          ),
        ),
      ],
    );
  }
}
