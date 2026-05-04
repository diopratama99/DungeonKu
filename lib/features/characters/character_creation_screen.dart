import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';
import 'package:dungeonku/data/supabase_providers.dart';

const _kMageElements = ['fire', 'water', 'wind', 'earth', 'lightning', 'dark'];

class CharacterCreationScreen extends ConsumerStatefulWidget {
  const CharacterCreationScreen({super.key});

  @override
  ConsumerState<CharacterCreationScreen> createState() => _CharacterCreationScreenState();
}

class _CharacterCreationScreenState extends ConsumerState<CharacterCreationScreen> {
  final _nameCtrl = TextEditingController();
  String? _selectedClassId;
  String? _selectedAvatarId;
  String? _selectedMageElement;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(ClassDefinition cls) async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Pick a name');
      return;
    }
    if (_selectedAvatarId == null) {
      setState(() => _error = 'Pick an avatar');
      return;
    }
    if (cls.id == 'mage' && _selectedMageElement == null) {
      setState(() => _error = 'Pick an element');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw StateError('not signed in');
      final element = cls.id == 'mage' ? _selectedMageElement! : cls.baseElementDefault;
      await ref.read(charactersRepositoryProvider).create(
            userId: user.id,
            name: _nameCtrl.text.trim(),
            classId: cls.id,
            baseElement: element,
            avatarId: _selectedAvatarId!,
            stats: cls.baseStats,
          );
      ref.invalidate(charactersListProvider);
      if (mounted) context.go('/characters');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classDefinitionsProvider);
    final avatarsAsync = ref.watch(avatarTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NEW CHARACTER'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/characters'),
        ),
      ),
      body: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (classes) {
          final selectedClass = _selectedClassId == null
              ? null
              : classes.firstWhere((c) => c.id == _selectedClassId);
          final avatars = (avatarsAsync.valueOrNull ?? const <AvatarTemplate>[])
              .where((a) => selectedClass == null || a.fitsClass(selectedClass.id))
              .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionLabel('1. Pick a class'),
              const SizedBox(height: 8),
              ...classes.map((c) => _ClassTile(
                    cls: c,
                    selected: _selectedClassId == c.id,
                    onTap: () => setState(() {
                      _selectedClassId = c.id;
                      _selectedAvatarId = null;
                      _selectedMageElement = null;
                    }),
                  )),
              if (selectedClass != null) ...[
                const SizedBox(height: 24),
                if (selectedClass.id == 'mage') ...[
                  _SectionLabel('2. Pick your element'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kMageElements.map((e) {
                      final selected = _selectedMageElement == e;
                      return _ElementChip(
                        label: e,
                        selected: selected,
                        onTap: () => setState(() => _selectedMageElement = e),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel('3. Pick an avatar'),
                ] else
                  _SectionLabel('2. Pick an avatar'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: avatars.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final a = avatars[i];
                      final selected = _selectedAvatarId == a.id;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedAvatarId = a.id),
                        child: Container(
                          width: 100,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selected ? PixelColors.accentGold : PixelColors.borderSoft,
                              width: selected ? 3 : 1,
                            ),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: a.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const ColoredBox(color: PixelColors.panelInner),
                            errorWidget: (_, __, ___) => const ColoredBox(color: PixelColors.panelInner),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _SectionLabel(selectedClass.id == 'mage' ? '4. Name' : '3. Name'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 32,
                  style: AppTheme.vt323(20),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: PixelColors.panelInner,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: PixelColors.borderSoft),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _DerivedStatsCard(cls: selectedClass),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: AppTheme.vt323(16, color: PixelColors.accentRed)),
                  ),
                PixelButton(
                  label: 'Create character',
                  icon: Icons.check,
                  fullWidth: true,
                  onPressed: _busy ? null : () => _submit(selectedClass),
                ),
                const SizedBox(height: 24),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTheme.pressStart(11, color: PixelColors.accentGold));
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({required this.cls, required this.selected, required this.onTap});
  final ClassDefinition cls;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: PixelPanel(
          borderColor: selected ? PixelColors.accentGold : PixelColors.borderSoft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cls.name.toUpperCase(),
                        style: AppTheme.pressStart(12, color: PixelColors.accentGold)),
                    const SizedBox(height: 4),
                    Text(cls.description, style: AppTheme.vt323(16)),
                    const SizedBox(height: 6),
                    Text(
                      'HP ${cls.startingHp} · ${cls.resourceType.toUpperCase()} ${cls.startingResource} · AC ${cls.startingAc}',
                      style: AppTheme.pressStart(8, color: PixelColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElementChip extends StatelessWidget {
  const _ElementChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: PixelColors.panelInner,
          border: Border.all(
            color: selected ? PixelColors.accentGold : PixelColors.borderSoft,
            width: selected ? 3 : 1,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTheme.pressStart(10,
              color: selected ? PixelColors.accentGold : PixelColors.textOnInk),
        ),
      ),
    );
  }
}

class _DerivedStatsCard extends StatelessWidget {
  const _DerivedStatsCard({required this.cls});
  final ClassDefinition cls;

  @override
  Widget build(BuildContext context) {
    final stats = cls.baseStats;
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STARTING STATS', style: AppTheme.pressStart(10, color: PixelColors.accentGold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: stats.entries.map((e) {
              return Text('${e.key} ${e.value}', style: AppTheme.pressStart(10));
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}
