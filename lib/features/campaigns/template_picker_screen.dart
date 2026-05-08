import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';
import 'package:dungeonku/features/campaigns/template_detail_screen.dart';

/// Step 1 of campaign creation \u2014 a pure list of stories. Tapping a
/// story pushes [TemplateDetailScreen] (full page) so the optional name
/// + Begin button can\u2019t hide below the fold of a long template list.
class TemplatePickerScreen extends ConsumerWidget {
  const TemplatePickerScreen({required this.characterId, super.key});

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(storyTemplatesProvider);
    return Scaffold(
      appBar: RetroAppBar(
        title: 'PICK A STORY',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/characters'),
        ),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (templates) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: templates.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _TemplateCard(
            template: templates[i],
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => TemplateDetailScreen(
                  template: templates[i],
                  characterId: characterId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final StoryTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = template.coverImageUrl;
    return GestureDetector(
      onTap: onTap,
      child: PixelPanel(
        padding: EdgeInsets.zero,
        borderColor: PixelColors.borderSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null && cover.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AssetOrNetworkImage(imageUrl: cover, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xCC000000)],
                          stops: [0.55, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 6,
                      child: Text(
                        template.title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.pressStart(13,
                            color: PixelColors.accentGold),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: PixelColors.borderOuter,
                          border: Border.all(color: PixelColors.borderSoft),
                        ),
                        child: Text(template.genre.toUpperCase(),
                            style: AppTheme.pressStart(7,
                                color: PixelColors.accentGold)),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cover == null || cover.isEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            template.title.toUpperCase(),
                            style: AppTheme.pressStart(13,
                                color: PixelColors.accentGold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: PixelColors.panelInner,
                            border:
                                Border.all(color: PixelColors.borderSoft),
                          ),
                          child: Text(template.genre.toUpperCase(),
                              style: AppTheme.pressStart(7,
                                  color: PixelColors.textMuted)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(template.shortDescription,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.vt323(18)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right,
                          color: PixelColors.borderSoft),
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
