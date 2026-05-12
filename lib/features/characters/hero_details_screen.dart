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
import 'package:dungeonku/core/widgets/skill_icon.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';
import 'package:dungeonku/data/supabase_providers.dart';

const _kMageElements = ['fire', 'water', 'wind', 'earth', 'lightning', 'dark'];

/// Step 2 of character creation. Reached by tapping a class on the
/// [CharacterCreationScreen]; shows that class\u2019s identity, lets the
/// player pick an avatar (and element if Mage), name the hero, and commit.
///
/// Lives on its own route so the player can\u2019t miss the form appearing
/// "below the fold" of the class list \u2014 a complaint we got from
/// playtesters who selected a class and didn\u2019t notice anything had
/// happened.
class HeroDetailsScreen extends ConsumerStatefulWidget {
  const HeroDetailsScreen({required this.cls, super.key});

  final ClassDefinition cls;

  @override
  ConsumerState<HeroDetailsScreen> createState() => _HeroDetailsScreenState();
}

class _HeroDetailsScreenState extends ConsumerState<HeroDetailsScreen> {
  final _nameCtrl = TextEditingController();
  String? _selectedAvatarId;
  String? _selectedMageElement;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cls = widget.cls;
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
      final element =
          cls.id == 'mage' ? _selectedMageElement! : cls.baseElementDefault;
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
    final cls = widget.cls;
    final avatarsAsync = ref.watch(avatarTemplatesProvider);
    final avatars = (avatarsAsync.valueOrNull ?? const <AvatarTemplate>[])
        .where((a) => a.fitsClass(cls.id))
        .toList(growable: false);

    final isMage = cls.id == 'mage';
    final stepCount = isMage ? 4 : 3;

    return Scaffold(
      appBar: RetroAppBar(
        title: cls.name.toUpperCase(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _ClassBanner(cls: cls),
          const SizedBox(height: 20),
          if (isMage) ...[
            _StepLabel(step: 1, total: stepCount, text: 'Pick your element'),
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
            const SizedBox(height: 20),
          ],
          _StepLabel(
              step: isMage ? 2 : 1, total: stepCount, text: 'Pick an avatar'),
          const SizedBox(height: 8),
          if (avatarsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (avatars.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No portraits found for this class.',
                style: AppTheme.vt323(18, color: PixelColors.textMuted),
              ),
            )
          else
            // Grid is friendlier than a horizontal strip on phones \u2014 every
            // portrait is fully visible at once and obvious to tap.
            GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [
                for (final a in avatars)
                  _AvatarTile(
                    avatar: a,
                    selected: _selectedAvatarId == a.id,
                    onTap: () => setState(() => _selectedAvatarId = a.id),
                  ),
              ],
            ),
          // Show the chosen avatar's lore + signature ability inline so
          // the player can read what they're committing to without
          // hunting for it elsewhere. Hidden until a tile is tapped, and
          // skipped entirely for legacy rows that have no lore wired.
          if (_selectedAvatarId != null) ...[
            const SizedBox(height: 14),
            _AvatarLoreCard(
              avatar: avatars.firstWhere(
                (a) => a.id == _selectedAvatarId,
                orElse: () => avatars.first,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _StepLabel(step: isMage ? 3 : 2, total: stepCount, text: 'Name'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLength: 32,
            style: AppTheme.vt323(20),
            decoration: InputDecoration(
              hintText: 'e.g. ${cls.name}',
              hintStyle: AppTheme.vt323(20, color: PixelColors.textMuted),
              filled: true,
              fillColor: PixelColors.panelInner,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: PixelColors.borderSoft),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StepLabel(
              step: isMage ? 4 : 3, total: stepCount, text: 'Starting stats'),
          const SizedBox(height: 8),
          _DerivedStatsCard(cls: cls),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: AppTheme.vt323(16, color: PixelColors.accentRed)),
          ],
          const SizedBox(height: 20),
          PixelButton(
            label: 'Forge Character',
            icon: Icons.check,
            fullWidth: true,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _ClassBanner extends StatelessWidget {
  const _ClassBanner({required this.cls});
  final ClassDefinition cls;

  @override
  Widget build(BuildContext context) {
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, color: PixelColors.accentGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cls.name.toUpperCase(),
                    style:
                        AppTheme.pressStart(14, color: PixelColors.accentGold)),
              ),
              Text(cls.resourceType.toUpperCase(),
                  style: AppTheme.pressStart(8, color: PixelColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(cls.description, style: AppTheme.vt323(18)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _StatPill('HP ${cls.startingHp}', PixelColors.accentRed),
              _StatPill(
                  '${cls.resourceType.toUpperCase()} ${cls.startingResource}',
                  PixelColors.accentBlue),
              _StatPill('AC ${cls.startingAc}', PixelColors.accentGreen),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill(this.text, this.tone);
  final String text;
  final Color tone;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: PixelColors.panelInner,
          border: Border.all(color: tone, width: 1),
        ),
        child: Text(text, style: AppTheme.pressStart(8, color: tone)),
      );
}

class _StepLabel extends StatelessWidget {
  const _StepLabel(
      {required this.step, required this.total, required this.text});
  final int step;
  final int total;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 8, height: 8, color: PixelColors.accentGold),
          const SizedBox(width: 8),
          Text('STEP $step/$total',
              style: AppTheme.pressStart(8, color: PixelColors.textMuted)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text.toUpperCase(),
                style: AppTheme.pressStart(11, color: PixelColors.accentGold)),
          ),
        ],
      );
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile(
      {required this.avatar, required this.selected, required this.onTap});
  final AvatarTemplate avatar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? PixelColors.accentGold : PixelColors.borderSoft;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: PixelColors.panelInner,
                border: Border.all(color: accent, width: selected ? 3 : 1),
              ),
              child: AssetOrNetworkImage(
                imageUrl: avatar.imageUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Avatar display name — kept legible (vt323 reads faster than
          // tiny press-start) so the player can scan portraits without
          // tapping each one. Two-line cap with ellipsis handles the
          // longer names like "The Crimson Lance Captain".
          Text(
            avatar.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.vt323(
              14,
              color: selected ? PixelColors.accentGold : PixelColors.textOnInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _ElementChip extends StatelessWidget {
  const _ElementChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = elementTone(label);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: PixelColors.panelInner,
          border: Border.all(
            color: selected ? tone : PixelColors.borderSoft,
            width: selected ? 3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElementIcon(element: label, size: selected ? 28 : 24),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: AppTheme.pressStart(
                10,
                color: selected ? tone : PixelColors.textOnInk,
              ),
            ),
          ],
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
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: stats.entries
            .map((e) =>
                Text('${e.key} ${e.value}', style: AppTheme.pressStart(10)))
            .toList(growable: false),
      ),
    );
  }
}

/// Lore + signature-ability preview rendered under the avatar grid when
/// the player taps a portrait.
///
/// All four data sections (backstory / personality / hooks / signature)
/// are independently optional — if a row was seeded before migration
/// 20260510 we silently skip the missing pieces instead of showing
/// empty headers. If *nothing* is wired we collapse to SizedBox.shrink().
class _AvatarLoreCard extends StatelessWidget {
  const _AvatarLoreCard({required this.avatar});
  final AvatarTemplate avatar;

  @override
  Widget build(BuildContext context) {
    if (!avatar.hasLore) return const SizedBox.shrink();
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: display name + tiny "lore" tag so it's clear this is
          // the chosen portrait's flavor, not the class's.
          Row(
            children: [
              Container(width: 8, height: 8, color: PixelColors.accentGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  avatar.displayName.toUpperCase(),
                  style: AppTheme.pressStart(11, color: PixelColors.accentGold),
                ),
              ),
              Text(
                'LORE',
                style: AppTheme.pressStart(8, color: PixelColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (avatar.backstory != null && avatar.backstory!.isNotEmpty) ...[
            Text(
              avatar.backstory!,
              style: AppTheme.vt323(18, color: PixelColors.textOnInk),
            ),
            const SizedBox(height: 10),
          ],
          if (avatar.personalityTags.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in avatar.personalityTags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: PixelColors.panelInner,
                      border:
                          Border.all(color: PixelColors.borderSoft, width: 1),
                    ),
                    child: Text(
                      tag,
                      style: AppTheme.vt323(15, color: PixelColors.textOnInk),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (avatar.storyHooks.isNotEmpty) ...[
            Text(
              'DM MAY PULL ON',
              style: AppTheme.pressStart(8, color: PixelColors.textMuted),
            ),
            const SizedBox(height: 4),
            for (final hook in avatar.storyHooks)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style:
                            AppTheme.vt323(18, color: PixelColors.accentGold)),
                    Expanded(
                      child: Text(
                        hook,
                        style: AppTheme.vt323(17, color: PixelColors.textOnInk),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
          ],
          if (avatar.signatureSkillName != null) ...[
            // Signature ability: visually emphasized as the gameplay
            // payoff — granted as a real skill at campaign start.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PixelColors.panelInner,
                border: Border.all(color: PixelColors.accentGold, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (avatar.signatureSkillId != null) ...[
                    SkillIcon(
                      skillId: avatar.signatureSkillId!,
                      size: 46,
                      borderColor: PixelColors.accentGold,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: PixelColors.accentGold, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'SIGNATURE — ${avatar.signatureSkillName!.toUpperCase()}',
                                style: AppTheme.pressStart(9,
                                    color: PixelColors.accentGold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (avatar.signatureSkillDescription != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            avatar.signatureSkillDescription!,
                            style: AppTheme.vt323(17,
                                color: PixelColors.textOnInk),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
