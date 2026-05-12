import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';
import 'package:dungeonku/data/supabase_providers.dart';

/// Step 2 of campaign creation. Reached by tapping a story on the
/// [TemplatePickerScreen]; shows the cover art full-bleed, the lore, and
/// the optional run name + Begin button. Splitting this off the picker
/// makes the "Begin" CTA impossible to miss \u2014 previously it appeared
/// inline at the bottom of the picker, below the fold.
class TemplateDetailScreen extends ConsumerStatefulWidget {
  const TemplateDetailScreen({
    required this.template,
    required this.characterId,
    super.key,
  });

  final StoryTemplate template;
  final String characterId;

  @override
  ConsumerState<TemplateDetailScreen> createState() =>
      _TemplateDetailScreenState();
}

class _TemplateDetailScreenState extends ConsumerState<TemplateDetailScreen> {
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw StateError('not signed in');
      final t = widget.template;
      final name =
          _nameCtrl.text.trim().isEmpty ? t.title : _nameCtrl.text.trim();
      final campaign = await ref.read(campaignsRepositoryProvider).create(
            userId: user.id,
            characterId: widget.characterId,
            templateId: t.id,
            name: name,
          );
      ref.invalidate(campaignsListProvider);
      if (mounted) context.go('/game/${campaign.id}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return Scaffold(
      appBar: RetroAppBar(
        title: t.title.toUpperCase(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _CoverHeader(template: t),
          const SizedBox(height: 16),
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 8, height: 8, color: PixelColors.accentGold),
                    const SizedBox(width: 8),
                    Text('PROLOGUE',
                        style: AppTheme.pressStart(11,
                            color: PixelColors.accentGold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t.shortDescription, style: AppTheme.vt323(18)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 8, height: 8, color: PixelColors.accentBlue),
                    const SizedBox(width: 8),
                    Text('THE WORLD',
                        style: AppTheme.pressStart(11,
                            color: PixelColors.accentBlue)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t.worldSetting, style: AppTheme.vt323(18)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 8, height: 8, color: PixelColors.accentPurple),
                    const SizedBox(width: 8),
                    Text('OPENING SCENE',
                        style: AppTheme.pressStart(11,
                            color: PixelColors.accentPurple)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t.openingScene, style: AppTheme.vt323(18)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(width: 8, height: 8, color: PixelColors.accentGold),
              const SizedBox(width: 8),
              Text('NAME THIS RUN  (OPTIONAL)',
                  style:
                      AppTheme.pressStart(11, color: PixelColors.accentGold)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLength: 60,
            style: AppTheme.vt323(20),
            decoration: InputDecoration(
              hintText: t.title,
              hintStyle: AppTheme.vt323(20, color: PixelColors.textMuted),
              filled: true,
              fillColor: PixelColors.panelInner,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: PixelColors.borderSoft),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: AppTheme.vt323(16, color: PixelColors.accentRed)),
          ],
          const SizedBox(height: 16),
          PixelButton(
            label: 'Begin Quest',
            icon: Icons.play_arrow,
            iconAsset: 'assets/images/icons/processed/ui_play.png',
            fullWidth: true,
            onPressed: _busy ? null : _start,
          ),
        ],
      ),
    );
  }
}

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.template});
  final StoryTemplate template;

  @override
  Widget build(BuildContext context) {
    final cover = template.coverImageUrl;
    return Container(
      decoration: BoxDecoration(
        color: PixelColors.inkBackground,
        border: Border.all(color: PixelColors.borderHighlight, width: 2),
      ),
      child: Column(
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
                        stops: [0.45, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: PixelColors.borderOuter,
                        border: Border.all(color: PixelColors.accentGold),
                      ),
                      child: Text(template.genre.toUpperCase(),
                          style: AppTheme.pressStart(8,
                              color: PixelColors.accentGold)),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Text(
                      template.title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.pressStart(15,
                          color: PixelColors.accentGold),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(template.title.toUpperCase(),
                        style: AppTheme.pressStart(14,
                            color: PixelColors.accentGold)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: PixelColors.panelInner,
                      border: Border.all(color: PixelColors.borderSoft),
                    ),
                    child: Text(template.genre.toUpperCase(),
                        style: AppTheme.pressStart(8,
                            color: PixelColors.textMuted)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
