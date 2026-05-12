import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/pixel_progress_bar.dart';
import 'package:dungeonku/core/widgets/skill_icon.dart';
import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/models/reference.dart';

/// Read-only character sheet rendered as a draggable bottom sheet. Shows HP, MP/Stamina,
/// XP, stats, status effects, inventory, and the player's known skills with affordability.
class StatsSheet extends StatelessWidget {
  const StatsSheet({
    required this.character,
    required this.inventory,
    required this.skillIds,
    required this.allSkills,
    super.key,
  });

  final CampaignCharacter character;
  final List<InventoryItem> inventory;
  final List<String> skillIds;
  final List<Skill> allSkills;

  @override
  Widget build(BuildContext context) {
    final knownSkills =
        allSkills.where((s) => skillIds.contains(s.id)).toList(growable: false);
    final resourceColor = character.resourceType == 'mp'
        ? PixelColors.mpBar
        : PixelColors.staminaBar;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (ctx, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: PixelColors.panelBackground,
            border: Border(
              top: BorderSide(color: PixelColors.borderHighlight, width: 2),
            ),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                    width: 60, height: 4, color: PixelColors.borderHighlight),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(width: 8, height: 8, color: PixelColors.accentGold),
                  const SizedBox(width: 8),
                  Text('CHARACTER',
                      style: AppTheme.pressStart(12,
                          color: PixelColors.accentGold)),
                ],
              ),
              const SizedBox(height: 12),
              PixelPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PixelProgressBar(
                      label: 'HP',
                      current: character.hp,
                      max: character.maxHp,
                      fillColor: PixelColors.hpBar,
                    ),
                    const SizedBox(height: 8),
                    PixelProgressBar(
                      label: character.resourceType.toUpperCase(),
                      current: character.resourceCurrent,
                      max: character.resourceMax,
                      fillColor: resourceColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'LVL ${character.level} · AC ${character.ac} · XP ${character.xp}',
                        style: AppTheme.pressStart(10,
                            color: PixelColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SheetLabel('STATS', PixelColors.accentBlue),
              const SizedBox(height: 8),
              PixelPanel(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: character.currentStats.entries
                      .map((e) => Text('${e.key} ${e.value}',
                          style: AppTheme.pressStart(10)))
                      .toList(growable: false),
                ),
              ),
              if (character.statusEffects.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SheetLabel('STATUS', PixelColors.accentRed),
                const SizedBox(height: 8),
                PixelPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in character.statusEffects)
                        Text('${s.label} (${s.expiresInTurns} turns)',
                            style: AppTheme.vt323(18)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SheetLabel('SKILLS', PixelColors.accentPurple),
              const SizedBox(height: 8),
              PixelPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: knownSkills.isEmpty
                      ? [
                          Text('(none)',
                              style: AppTheme.vt323(18,
                                  color: PixelColors.textMuted))
                        ]
                      : [
                          for (final s in knownSkills)
                            _SkillRow(skill: s, character: character),
                        ],
                ),
              ),
              const SizedBox(height: 16),
              _SheetLabel('INVENTORY', PixelColors.accentGreen),
              const SizedBox(height: 8),
              PixelPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: inventory.isEmpty
                      ? [
                          Text('(empty)',
                              style: AppTheme.vt323(18,
                                  color: PixelColors.textMuted))
                        ]
                      : [
                          for (final i in inventory)
                            Text('${i.name} x${i.qty} · ${i.itemType}',
                                style: AppTheme.vt323(18)),
                        ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text, this.tone);
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(width: 8, height: 8, color: tone),
            const SizedBox(width: 8),
            Text(text, style: AppTheme.pressStart(11, color: tone)),
          ],
        ),
      );
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill, required this.character});
  final Skill skill;
  final CampaignCharacter character;

  @override
  Widget build(BuildContext context) {
    final affordable = skill.costType == 'free' ||
        (skill.costType == character.resourceType &&
            character.resourceCurrent >= skill.costAmount);
    final color = affordable ? PixelColors.textOnInk : PixelColors.textMuted;
    final costText = skill.costType == 'free'
        ? 'free'
        : '${skill.costAmount} ${skill.costType}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 8),
            child: SkillIcon(
              skillId: skill.id,
              size: 34,
              borderColor: color,
              disabled: !affordable,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.name, style: AppTheme.pressStart(9, color: color)),
                Text(skill.description,
                    style: AppTheme.vt323(16, color: color)),
              ],
            ),
          ),
          Text(costText, style: AppTheme.pressStart(8, color: color)),
        ],
      ),
    );
  }
}
