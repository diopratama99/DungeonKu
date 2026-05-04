import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/models/character.dart';
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
      appBar: AppBar(
        title: const Text('CHARACTERS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.collections_bookmark),
            tooltip: 'Campaigns',
            onPressed: () => context.go('/campaigns'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: charactersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTheme.vt323(18))),
        data: (characters) {
          final classes = classesAsync.valueOrNull ?? const [];
          final avatars = avatarsAsync.valueOrNull ?? const [];
          final slots = List<Character?>.generate(
            kMaxCharacters,
            (i) => i < characters.length ? characters[i] : null,
          );

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: kMaxCharacters,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final c = slots[i];
              if (c == null) return _EmptySlotCard(slotIndex: i);
              final cls = classes.firstWhere(
                (k) => k.id == c.classId,
                orElse: () => classes.isNotEmpty
                    ? classes.first
                    : (throw StateError('no classes loaded')),
              );
              final avatar = avatars.firstWhere(
                (a) => a.id == c.avatarId,
                orElse: () => avatars.isNotEmpty
                    ? avatars.first
                    : (throw StateError('no avatars loaded')),
              );
              return _CharacterCard(character: c, className: cls.name, avatarUrl: avatar.imageUrl);
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
    return PixelPanel(
      child: SizedBox(
        height: 110,
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: PixelColors.borderSoft, style: BorderStyle.solid, width: 2),
              ),
              child: Center(
                child: Text('+', style: AppTheme.pressStart(28, color: PixelColors.borderSoft)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SLOT ${slotIndex + 1}', style: AppTheme.pressStart(10, color: PixelColors.textMuted)),
                  const SizedBox(height: 6),
                  Text('Empty — create a character.', style: AppTheme.vt323(18, color: PixelColors.textMuted)),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (ctx) => PixelButton(
                      label: 'Create',
                      icon: Icons.add,
                      onPressed: () => ctx.go('/characters/new'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterCard extends ConsumerWidget {
  const _CharacterCard({
    required this.character,
    required this.className,
    required this.avatarUrl,
  });

  final Character character;
  final String className;
  final String avatarUrl;

  Future<void> _confirmDelete(BuildContext ctx, WidgetRef ref) async {
    final repo = ref.read(charactersRepositoryProvider);
    final activeCount = await repo.activeCampaignCount(character.id);
    if (!ctx.mounted) return;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: PixelColors.panelBackground,
        title: Text('Delete ${character.name}?', style: AppTheme.pressStart(12)),
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
              child: Text('Delete', style: AppTheme.pressStart(10, color: PixelColors.accentRed))),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.delete(character.id);
    ref.invalidate(charactersListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PixelPanel(
      child: SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(color: PixelColors.panelInner),
                errorWidget: (_, __, ___) => const ColoredBox(color: PixelColors.panelInner),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(character.name.toUpperCase(), style: AppTheme.pressStart(12, color: PixelColors.accentGold)),
                  const SizedBox(height: 4),
                  Text('$className · ${character.baseElement}', style: AppTheme.vt323(16, color: PixelColors.textMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      PixelButton(
                        label: 'Start',
                        icon: Icons.play_arrow,
                        onPressed: () => context.go('/campaigns/new?character_id=${character.id}'),
                      ),
                      const SizedBox(width: 8),
                      PixelButton(
                        label: 'Delete',
                        tone: PixelButtonTone.danger,
                        icon: Icons.delete,
                        onPressed: () => _confirmDelete(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
