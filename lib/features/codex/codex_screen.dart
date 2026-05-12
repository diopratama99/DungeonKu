import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dungeonku/core/audio/bgm_manager.dart';
import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/utils/element_palette.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/element_icon.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/core/widgets/skill_icon.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';
import 'package:dungeonku/features/codex/codex_detail_screen.dart';
import 'package:dungeonku/features/codex/data/codex_items.dart';

/// In-game encyclopedia. Each tab presents a visual catalogue (using assets
/// from `assets/images/`) and tapping any entry opens a [CodexDetailScreen]
/// with full art and lore.
class CodexScreen extends ConsumerStatefulWidget {
  const CodexScreen({super.key});

  @override
  ConsumerState<CodexScreen> createState() => _CodexScreenState();
}

class _CodexScreenState extends ConsumerState<CodexScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    // Same reasoning as the other ex-tab screens: nudge the menu BGM
    // back on in case we landed here from a deep link / pop. Deferred to
    // post-frame so we don't read providers during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(bgmManagerProvider).playMenu();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RetroAppBar(
        title: 'CODEX',
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: PixelColors.accentGold,
          labelColor: PixelColors.accentGold,
          unselectedLabelColor: PixelColors.textMuted,
          labelStyle: AppTheme.pressStart(9),
          unselectedLabelStyle: AppTheme.pressStart(9),
          tabs: const [
            Tab(text: 'CLASSES'),
            Tab(text: 'SKILLS'),
            Tab(text: 'ITEMS'),
            Tab(text: 'ELEMENTS'),
            Tab(text: 'PLAY'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _ClassesTab(),
          _SkillsTab(),
          _ItemsTab(),
          _ElementsTab(),
          _HowToPlayTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CLASSES — grid of class portraits, tap → carousel detail
// ---------------------------------------------------------------------------

class _ClassesTab extends ConsumerWidget {
  const _ClassesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classDefinitionsProvider);
    final avatarsAsync = ref.watch(avatarTemplatesProvider);
    final skillsAsync = ref.watch(skillsCatalogProvider);

    if (classesAsync.isLoading || avatarsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (classesAsync.hasError) {
      return Center(child: Text('Error: ${classesAsync.error}'));
    }
    final classes = classesAsync.valueOrNull ?? const <ClassDefinition>[];
    final avatars = avatarsAsync.valueOrNull ?? const <AvatarTemplate>[];
    final skills = skillsAsync.valueOrNull ?? const <Skill>[];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: classes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (_, i) {
        final cls = classes[i];
        // Build the per-class portrait list once. We track names in a
        // parallel array so the detail screen can label each carousel
        // slide with the avatar it actually belongs to (warrior_01 →
        // "Aric the Sworn", etc.).
        final classAvatars =
            avatars.where((a) => a.fitsClass(cls.id)).toList(growable: false);
        final portraits =
            classAvatars.map((a) => a.imageUrl).toList(growable: false);
        final portraitNames =
            classAvatars.map((a) => a.displayName).toList(growable: false);
        final cover = portraits.isNotEmpty
            ? portraits.first
            : 'assets/images/avatars/${cls.id}_01.png';
        return _GridTile(
          imageAsset: cover,
          title: cls.name,
          subtitle: cls.resourceType.toUpperCase(),
          accent: PixelColors.accentGold,
          onTap: () =>
              _openClassDetail(context, cls, portraits, portraitNames, skills),
        );
      },
    );
  }

  void _openClassDetail(
    BuildContext context,
    ClassDefinition cls,
    List<String> portraits,
    List<String> portraitNames,
    List<Skill> allSkills,
  ) {
    final classSkills = allSkills
        .where((s) => s.availableToClasses.contains(cls.id) || s.isBasicAttack)
        .toList(growable: false);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CodexDetailScreen(
          title: cls.name,
          subtitle:
              '${cls.resourceType.toUpperCase()} CASTER \u00b7 ${cls.baseElementDefault.toUpperCase()} AFFINITY',
          imageAssets: portraits.isEmpty
              ? ['assets/images/avatars/${cls.id}_01.png']
              : portraits,
          imageCaptions: portraitNames.isEmpty ? null : portraitNames,
          accent: PixelColors.accentGold,
          sections: [
            CodexSection(title: 'Lore', body: cls.description),
            CodexSection(
              title: 'Starting Loadout',
              pills: [
                CodexPill('HP ${cls.startingHp}', PixelColors.accentRed),
                CodexPill(
                    '${cls.resourceType.toUpperCase()} ${cls.startingResource}',
                    PixelColors.accentBlue),
                CodexPill('AC ${cls.startingAc}', PixelColors.accentGreen),
              ],
            ),
            CodexSection(
              title: 'Base Stats',
              pills: [
                for (final e in cls.baseStats.entries)
                  CodexPill('${e.key} ${e.value}', PixelColors.borderHighlight),
              ],
            ),
            if (cls.notes.isNotEmpty)
              CodexSection(title: 'Notes', body: cls.notes),
            if (classSkills.isNotEmpty)
              CodexSection(
                title: 'Signature Skills',
                bullets: [
                  for (final s in classSkills)
                    '${s.name} \u2014 ${s.description}',
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SKILLS — list with skill PNG icons + filter chips, tap → detail
// ---------------------------------------------------------------------------

class _SkillsTab extends ConsumerStatefulWidget {
  const _SkillsTab();

  @override
  ConsumerState<_SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends ConsumerState<_SkillsTab> {
  String _classFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final skillsAsync = ref.watch(skillsCatalogProvider);
    final classesAsync = ref.watch(classDefinitionsProvider);
    return skillsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (skills) {
        final classes = classesAsync.valueOrNull ?? const <ClassDefinition>[];
        final filtered = _classFilter == 'all'
            ? skills
            : skills
                .where((s) =>
                    s.availableToClasses.isEmpty ||
                    s.availableToClasses.contains(_classFilter))
                .toList(growable: false);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ChipBtn(
                      label: 'ALL',
                      selected: _classFilter == 'all',
                      onTap: () => setState(() => _classFilter = 'all'),
                    ),
                    for (final c in classes)
                      _ChipBtn(
                        label: c.name.toUpperCase(),
                        selected: _classFilter == c.id,
                        onTap: () => setState(() => _classFilter = c.id),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No skills for this class.',
                          style:
                              AppTheme.vt323(18, color: PixelColors.textMuted)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _SkillRow(
                        skill: filtered[i],
                        onTap: () => _openSkillDetail(context, filtered[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _openSkillDetail(BuildContext context, Skill s) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CodexDetailScreen(
          title: s.name,
          subtitle:
              '${s.kind.toUpperCase()} \u00b7 ${s.element.toUpperCase()} \u00b7 LV ${s.requiredLevel}',
          imageAssets: ['assets/images/skills/${s.id}.png'],
          accent: elementTone(s.element),
          sections: [
            CodexSection(title: 'Description', body: s.description),
            CodexSection(
              title: 'Specifications',
              pills: [
                CodexPill(
                  'COST ${s.costType == 'free' ? 'FREE' : '${s.costAmount} ${s.costType.toUpperCase()}'}',
                  PixelColors.accentBlue,
                ),
                if (s.dice != null)
                  CodexPill('DICE ${s.dice}', PixelColors.accentGreen),
                if (s.modifierStat != null)
                  CodexPill('MOD ${s.modifierStat!.toUpperCase()}',
                      PixelColors.accentPurple),
                CodexPill('LV ${s.requiredLevel}', PixelColors.borderSoft),
                if (s.isBasicAttack)
                  CodexPill('BASIC', PixelColors.borderHighlight),
              ],
            ),
            if (s.availableToClasses.isNotEmpty)
              CodexSection(
                title: 'Available To',
                pills: [
                  for (final c in s.availableToClasses)
                    CodexPill(c.toUpperCase(), PixelColors.borderHighlight),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill, required this.onTap});
  final Skill skill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = elementTone(skill.element);
    final cost = skill.costType == 'free'
        ? 'FREE'
        : '${skill.costAmount} ${skill.costType.toUpperCase()}';
    return InkWell(
      onTap: onTap,
      child: PixelPanel(
        child: Row(
          children: [
            // Pixel-art icon — skill ids match filenames in assets/skills/.
            SkillIcon(
              skillId: skill.id,
              size: 60,
              borderColor: tone,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(skill.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.pressStart(11, color: tone)),
                  const SizedBox(height: 4),
                  Text(skill.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.vt323(16, color: PixelColors.textOnInk)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _TinyPill(
                          skill.kind.toUpperCase(), PixelColors.accentPurple),
                      const SizedBox(width: 6),
                      _TinyPill(cost, PixelColors.accentBlue),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: PixelColors.borderSoft),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ITEMS — static catalogue with art, tap → detail
// ---------------------------------------------------------------------------

class _ItemsTab extends StatelessWidget {
  const _ItemsTab();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: kCodexItems.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (_, i) {
        final item = kCodexItems[i];
        return _GridTile(
          imageAsset: item.imageAsset,
          title: item.name,
          subtitle:
              '${item.kind.toUpperCase()} \u00b7 ${item.rarity.toUpperCase()}',
          accent: _rarityTone(item.rarity),
          onTap: () => _openItemDetail(context, item),
        );
      },
    );
  }

  void _openItemDetail(BuildContext context, CodexItem item) {
    final tone = _rarityTone(item.rarity);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CodexDetailScreen(
          title: item.name,
          subtitle:
              '${item.kind.toUpperCase()} \u00b7 ${item.rarity.toUpperCase()}',
          imageAssets: [item.imageAsset],
          accent: tone,
          sections: [
            CodexSection(title: 'Description', body: item.description),
            CodexSection(title: 'Lore', body: item.lore),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ELEMENTS — color tile + flavor
// ---------------------------------------------------------------------------

const _kElements = <_Elem>[
  _Elem('fire',
      'Burns through armor and lingers as DoT. Strong vs. wind, weak vs. water.'),
  _Elem('water',
      'Quenches flames and erodes stone. Strong vs. fire, weak vs. lightning.'),
  _Elem('wind',
      'Fast strikes that ignore some cover. Strong vs. earth, weak vs. fire.'),
  _Elem('earth',
      'Heavy hits, high physical defense. Strong vs. lightning, weak vs. wind.'),
  _Elem('lightning', 'Crit-friendly bursts. Strong vs. water, weak vs. earth.'),
  _Elem(
      'dark', 'Drains and curses. Useful vs. holy/light foes; risky to wield.'),
  _Elem('light',
      'Cleansing radiance. Strong vs. dark and undead; gentler against the living.'),
  _Elem('neutral',
      'No elemental affinity — reliable damage that no enemy is specifically immune to.'),
];

class _Elem {
  const _Elem(this.id, this.text);
  final String id;
  final String text;
}

class _ElementsTab extends StatelessWidget {
  const _ElementsTab();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _kElements.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final e = _kElements[i];
        final tone = elementTone(e.id);
        return PixelPanel(
          borderColor: tone,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElementIcon(element: e.id, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.id.toUpperCase(),
                        style: AppTheme.pressStart(12, color: tone)),
                    const SizedBox(height: 6),
                    Text(e.text, style: AppTheme.vt323(18)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HOW TO PLAY — parchment sections, no images
// ---------------------------------------------------------------------------

class _HowToPlayTab extends StatelessWidget {
  const _HowToPlayTab();

  static const _sections = <_HowSection>[
    _HowSection(
      icon: '\u2756',
      title: 'THE LOOP',
      body:
          'DungeonKu is an AI-driven solo DnD. The Dungeon Master narrates a scene, '
          'offers you choices, and asks for dice rolls when the outcome is uncertain. '
          'You answer with an option, a free-form action, or a skill from your sheet.',
    ),
    _HowSection(
      icon: '\u2694',
      title: 'COMBAT',
      body:
          'Combat is turn-based. Pick an attack or skill, the DM rolls hit and damage '
          'against the enemy AC, then the enemy retaliates. HP at 0 = game over; '
          'win to claim XP, loot, and a bit more story.',
    ),
    _HowSection(
      icon: '\u2728',
      title: 'SKILLS & RESOURCES',
      body:
          'Each class spends MP (mages) or Stamina (warriors/rangers/etc.). Skills cost '
          'resource per use; basic attacks are free. Some skills scale off STR, DEX, '
          'or INT \u2014 your starting stats matter.',
    ),
    _HowSection(
      icon: '\u2620',
      title: 'DEATH & SAVES',
      body:
          'Your campaign auto-saves after every turn. Dying drops you on the Game Over '
          'screen, but your roster lives on \u2014 forge a new hero or start a fresh '
          'story with the same one.',
    ),
    _HowSection(
      icon: '\u270D',
      title: 'TIPS',
      body:
          '\u2022 Read the DM\'s flavor \u2014 clues are hidden in the prose.\n'
          '\u2022 Free-form actions are valid; don\'t feel locked into the listed options.\n'
          '\u2022 Open the stats sheet (top of game screen) to inspect HP, status & inventory.\n'
          '\u2022 Match elements to enemy weaknesses for bigger damage rolls.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final s = _sections[i];
        return PixelPanel(
          color: PixelColors.parchment,
          borderColor: PixelColors.accentGold,
          innerBorderColor: PixelColors.parchmentDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.icon,
                      style: AppTheme.pressStart(16,
                          color: PixelColors.accentGold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.title,
                        style: AppTheme.pressStart(11,
                            color: PixelColors.textOnParchment)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(s.body,
                  style:
                      AppTheme.vt323(18, color: PixelColors.textOnParchment)),
            ],
          ),
        );
      },
    );
  }
}

class _HowSection {
  const _HowSection(
      {required this.icon, required this.title, required this.body});
  final String icon;
  final String title;
  final String body;
}

// ---------------------------------------------------------------------------
// Shared UI bits
// ---------------------------------------------------------------------------

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.imageAsset,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final String imageAsset;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: PixelColors.panelBackground,
          border: Border.all(color: accent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: PixelColors.inkBackground,
                padding: const EdgeInsets.all(8),
                child: AssetOrNetworkImage(
                  imageUrl: imageAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: const BoxDecoration(
                color: PixelColors.panelBackground,
                border: Border(
                  top: BorderSide(color: PixelColors.borderSoft, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.pressStart(10, color: accent)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTheme.pressStart(7, color: PixelColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipBtn extends StatelessWidget {
  const _ChipBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = selected ? PixelColors.accentGold : PixelColors.borderSoft;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: PixelColors.panelInner,
            border: Border.all(color: tone, width: selected ? 2 : 1),
          ),
          child: Text(label, style: AppTheme.pressStart(8, color: tone)),
        ),
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  const _TinyPill(this.text, this.tone);
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: PixelColors.panelInner,
        border: Border.all(color: tone, width: 1),
      ),
      child: Text(text, style: AppTheme.pressStart(7, color: tone)),
    );
  }
}

Color _rarityTone(String rarity) {
  switch (rarity.toLowerCase()) {
    case 'common':
      return PixelColors.borderSoft;
    case 'uncommon':
      return PixelColors.accentGreen;
    case 'rare':
      return PixelColors.accentBlue;
    case 'epic':
      return PixelColors.accentPurple;
    case 'legendary':
      return PixelColors.accentGold;
    default:
      return PixelColors.borderSoft;
  }
}
