import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';

/// Reusable retro detail page for any Codex entry. Caller supplies the hero
/// image(s), a title, an accent tone, and a list of [CodexSection]s. Keeps
/// every detail page visually consistent without copy/pasting layout.
class CodexDetailScreen extends StatefulWidget {
  const CodexDetailScreen({
    required this.title,
    required this.subtitle,
    required this.imageAssets,
    required this.accent,
    required this.sections,
    this.heroBackgroundAsset,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<String> imageAssets;
  final Color accent;
  final List<CodexSection> sections;
  final String? heroBackgroundAsset;

  @override
  State<CodexDetailScreen> createState() => _CodexDetailScreenState();
}

class _CodexDetailScreenState extends State<CodexDetailScreen> {
  int _selected = 0;
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RetroAppBar(
        title: widget.title.toUpperCase(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroFrame(
            assets: widget.imageAssets,
            accent: widget.accent,
            controller: _pageCtrl,
            selected: _selected,
            onChanged: (i) => setState(() => _selected = i),
            backgroundAsset: widget.heroBackgroundAsset,
          ),
          if (widget.imageAssets.length > 1) ...[
            const SizedBox(height: 8),
            _DotIndicator(
              count: widget.imageAssets.length,
              selected: _selected,
              accent: widget.accent,
            ),
          ],
          const SizedBox(height: 16),
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title.toUpperCase(),
                    style: AppTheme.pressStart(14, color: widget.accent)),
                const SizedBox(height: 6),
                Text(widget.subtitle,
                    style: AppTheme.pressStart(8,
                        color: PixelColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final s in widget.sections) ...[
            _SectionPanel(section: s, accent: widget.accent),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class CodexSection {
  const CodexSection({
    required this.title,
    this.body,
    this.bullets,
    this.pills,
  });

  final String title;
  final String? body;
  final List<String>? bullets;
  final List<CodexPill>? pills;
}

class CodexPill {
  const CodexPill(this.text, this.tone);
  final String text;
  final Color tone;
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({required this.section, required this.accent});
  final CodexSection section;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(section.title.toUpperCase(),
                    style: AppTheme.pressStart(11, color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (section.body != null)
            Text(section.body!,
                style: AppTheme.vt323(18,
                    color: PixelColors.textOnInk)),
          if (section.bullets != null) ...[
            for (final b in section.bullets!)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('\u2022  $b',
                    style: AppTheme.vt323(18,
                        color: PixelColors.textOnInk)),
              ),
          ],
          if (section.pills != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in section.pills!)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: PixelColors.panelInner,
                      border: Border.all(color: p.tone, width: 1),
                    ),
                    child: Text(p.text,
                        style: AppTheme.pressStart(8, color: p.tone)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroFrame extends StatelessWidget {
  const _HeroFrame({
    required this.assets,
    required this.accent,
    required this.controller,
    required this.selected,
    required this.onChanged,
    this.backgroundAsset,
  });

  final List<String> assets;
  final Color accent;
  final PageController controller;
  final int selected;
  final ValueChanged<int> onChanged;
  final String? backgroundAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PixelColors.inkBackground,
        border: Border.all(color: accent, width: 2),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backgroundAsset != null)
              Opacity(
                opacity: 0.18,
                child: Image.asset(backgroundAsset!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink()),
              ),
            PageView.builder(
              controller: controller,
              itemCount: assets.length,
              onPageChanged: onChanged,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(8),
                child: AssetOrNetworkImage(
                  imageUrl: assets[i],
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({
    required this.count,
    required this.selected,
    required this.accent,
  });

  final int count;
  final int selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              width: i == selected ? 12 : 6,
              height: 6,
              color: i == selected ? accent : PixelColors.borderSoft,
            ),
          ),
      ],
    );
  }
}
