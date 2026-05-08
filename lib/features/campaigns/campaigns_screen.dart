import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';
import 'package:dungeonku/data/repositories/characters_repository.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(campaignsListProvider);
    final charactersAsync = ref.watch(charactersListProvider);
    final templatesAsync = ref.watch(storyTemplatesProvider);

    return Scaffold(
      appBar: const RetroAppBar(title: 'TOME OF DEEDS'),
      body: campaignsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Error: $e', style: AppTheme.vt323(18))),
        data: (campaigns) {
          if (campaigns.isEmpty) {
            return _EmptyCampaignsState(
              firstCoverUrl: (templatesAsync.valueOrNull ?? const [])
                  .map((t) => t.coverImageUrl)
                  .firstWhereOrNull((u) => u != null && u.isNotEmpty),
            );
          }
          final active = campaigns
              .where((c) => c.status == 'active')
              .toList(growable: false);
          final completed = campaigns
              .where((c) => c.status == 'completed')
              .toList(growable: false);
          final failed = campaigns
              .where((c) => c.status == 'failed')
              .toList(growable: false);
          final characters = charactersAsync.valueOrNull ?? const [];
          final templates = templatesAsync.valueOrNull ?? const [];
          String? coverFor(String templateId) {
            for (final t in templates) {
              if (t.id == templateId) return t.coverImageUrl;
            }
            return null;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active.isNotEmpty) ...[
                _SectionHeader('ACTIVE'),
                for (final c in active)
                  _CampaignCard(
                    campaign: c,
                    characterName: _nameFor(characters, c.characterId),
                    coverImageUrl: coverFor(c.templateId),
                  ),
              ],
              if (completed.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionHeader('COMPLETED'),
                for (final c in completed)
                  _CampaignCard(
                    campaign: c,
                    characterName: _nameFor(characters, c.characterId),
                    coverImageUrl: coverFor(c.templateId),
                  ),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionHeader('FALLEN HEROES'),
                for (final c in failed)
                  _CampaignCard(
                    campaign: c,
                    characterName: _nameFor(characters, c.characterId),
                    coverImageUrl: coverFor(c.templateId),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _nameFor(List<dynamic> characters, String characterId) {
    final c = characters.firstWhereOrNull(
      (e) => (e as dynamic).id == characterId,
    );
    return c == null ? '(deleted)' : (c as dynamic).name as String;
  }
}

class _EmptyCampaignsState extends StatelessWidget {
  const _EmptyCampaignsState({required this.firstCoverUrl});
  final String? firstCoverUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (firstCoverUrl != null && firstCoverUrl!.isNotEmpty)
          Opacity(
            opacity: 0.35,
            child: AssetOrNetworkImage(
              imageUrl: firstCoverUrl!,
              fit: BoxFit.cover,
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0xEE000000)],
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('❖  THE TOME IS BLANK  ❖',
                    style:
                        AppTheme.pressStart(10, color: PixelColors.accentGold)),
                const SizedBox(height: 12),
                Text(
                  'No tale has been written yet.\nChoose a hero and pen the first chapter.',
                  textAlign: TextAlign.center,
                  style: AppTheme.vt323(20),
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (ctx) => PixelButton(
                    label: 'Pick a hero',
                    icon: Icons.person,
                    onPressed: () => ctx.go('/characters'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: AppTheme.pressStart(11, color: PixelColors.accentGold)),
      );
}

class _CampaignCard extends ConsumerWidget {
  const _CampaignCard({
    required this.campaign,
    required this.characterName,
    required this.coverImageUrl,
  });
  final Campaign campaign;
  final String characterName;
  final String? coverImageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('MMM d, h:mm a');
    final cover = coverImageUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PixelPanel(
        padding: EdgeInsets.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cover != null && cover.isNotEmpty)
              SizedBox(
                width: 96,
                child: AssetOrNetworkImage(imageUrl: cover, fit: BoxFit.cover),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            campaign.name.toUpperCase(),
                            style: AppTheme.pressStart(12,
                                color: PixelColors.accentGold),
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
                            onPressed: () =>
                                context.go('/game-over/${campaign.id}'),
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
                                title: Text('Delete this run?',
                                    style: AppTheme.pressStart(12)),
                                content: Text(
                                    'Permanently delete "${campaign.name}"? This cannot be undone.',
                                    style: AppTheme.vt323(18)),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dctx).pop(false),
                                    child: Text('Cancel',
                                        style: AppTheme.pressStart(10)),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dctx).pop(true),
                                    child: Text('Delete',
                                        style: AppTheme.pressStart(10,
                                            color: PixelColors.accentRed)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            await ref
                                .read(campaignsRepositoryProvider)
                                .delete(campaign.id);
                            ref.invalidate(campaignsListProvider);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
      case 'intro':
        return PixelColors.accentBlue;
      case 'rising':
        return PixelColors.accentGreen;
      case 'climax':
        return PixelColors.accentRed;
      case 'resolution':
        return PixelColors.accentGold;
      default:
        return PixelColors.borderSoft;
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
      child: Text(phase.toUpperCase(),
          style: AppTheme.pressStart(7, color: _tone)),
    );
  }
}
