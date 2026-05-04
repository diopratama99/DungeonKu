import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(campaignsListProvider);
    final charactersAsync = ref.watch(charactersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CAMPAIGNS'),
        leading: IconButton(
          icon: const Icon(Icons.person),
          tooltip: 'Characters',
          onPressed: () => context.go('/characters'),
        ),
      ),
      body: campaignsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTheme.vt323(18))),
        data: (campaigns) {
          if (campaigns.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No campaigns yet. Pick a character and start one.',
                  textAlign: TextAlign.center,
                  style: AppTheme.vt323(20),
                ),
              ),
            );
          }
          final active = campaigns.where((c) => c.status == 'active').toList(growable: false);
          final completed = campaigns.where((c) => c.status == 'completed').toList(growable: false);
          final failed = campaigns.where((c) => c.status == 'failed').toList(growable: false);
          final characters = charactersAsync.valueOrNull ?? const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active.isNotEmpty) ...[
                _SectionHeader('ACTIVE'),
                for (final c in active)
                  _CampaignCard(campaign: c, characterName: _nameFor(characters, c.characterId)),
              ],
              if (completed.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionHeader('COMPLETED'),
                for (final c in completed)
                  _CampaignCard(campaign: c, characterName: _nameFor(characters, c.characterId)),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionHeader('FALLEN HEROES'),
                for (final c in failed)
                  _CampaignCard(campaign: c, characterName: _nameFor(characters, c.characterId)),
              ],
            ],
          );
        },
      ),
    );
  }

  String _nameFor(List<dynamic> characters, String characterId) {
    final c = characters.firstWhere(
      (e) => (e as dynamic).id == characterId,
      orElse: () => null,
    );
    return c == null ? '(deleted)' : (c as dynamic).name as String;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: AppTheme.pressStart(11, color: PixelColors.accentGold)),
      );
}

class _CampaignCard extends ConsumerWidget {
  const _CampaignCard({required this.campaign, required this.characterName});
  final Campaign campaign;
  final String characterName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('MMM d, h:mm a');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PixelPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    campaign.name.toUpperCase(),
                    style: AppTheme.pressStart(12, color: PixelColors.accentGold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _PhaseBadge(phase: campaign.phase),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$characterName · ${campaign.totalTurns} turns · ${dateFmt.format(campaign.lastPlayedAt)}',
              style: AppTheme.vt323(16, color: PixelColors.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (campaign.status == 'active')
                  PixelButton(
                    label: 'Resume',
                    icon: Icons.play_arrow,
                    onPressed: () => context.go('/game/${campaign.id}'),
                  )
                else if (campaign.status == 'failed')
                  PixelButton(
                    label: 'View',
                    icon: Icons.visibility,
                    onPressed: () => context.go('/game-over/${campaign.id}'),
                  ),
                const SizedBox(width: 8),
                PixelButton(
                  label: 'Delete',
                  tone: PixelButtonTone.danger,
                  icon: Icons.delete,
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        backgroundColor: PixelColors.panelBackground,
                        title: Text('Delete this run?', style: AppTheme.pressStart(12)),
                        content: Text('Permanently delete "${campaign.name}"? This cannot be undone.',
                            style: AppTheme.vt323(18)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: Text('Cancel', style: AppTheme.pressStart(10)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: Text('Delete', style: AppTheme.pressStart(10, color: PixelColors.accentRed)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await ref.read(campaignsRepositoryProvider).delete(campaign.id);
                    ref.invalidate(campaignsListProvider);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.phase});
  final String phase;

  Color get _tone {
    switch (phase) {
      case 'intro':      return PixelColors.accentBlue;
      case 'rising':     return PixelColors.accentGreen;
      case 'climax':     return PixelColors.accentRed;
      case 'resolution': return PixelColors.accentGold;
      default:           return PixelColors.borderSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: PixelColors.panelInner,
        border: Border.all(color: _tone, width: 1),
      ),
      child: Text(phase.toUpperCase(), style: AppTheme.pressStart(7, color: _tone)),
    );
  }
}
