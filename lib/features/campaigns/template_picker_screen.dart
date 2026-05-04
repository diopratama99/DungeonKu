import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';
import 'package:dungeonku/data/supabase_providers.dart';

class TemplatePickerScreen extends ConsumerStatefulWidget {
  const TemplatePickerScreen({required this.characterId, super.key});
  final String characterId;

  @override
  ConsumerState<TemplatePickerScreen> createState() => _TemplatePickerScreenState();
}

class _TemplatePickerScreenState extends ConsumerState<TemplatePickerScreen> {
  String? _selectedTemplateId;
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _start(StoryTemplate template) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw StateError('not signed in');
      final name = _nameCtrl.text.trim().isEmpty ? template.title : _nameCtrl.text.trim();
      final campaign = await ref.read(campaignsRepositoryProvider).create(
            userId: user.id,
            characterId: widget.characterId,
            templateId: template.id,
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
    final templatesAsync = ref.watch(storyTemplatesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('PICK A STORY'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/characters'),
        ),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (templates) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final t in templates) ...[
                _TemplateCard(
                  template: t,
                  selected: _selectedTemplateId == t.id,
                  onTap: () => setState(() => _selectedTemplateId = t.id),
                ),
                const SizedBox(height: 12),
              ],
              if (_selectedTemplateId != null) ...[
                const SizedBox(height: 8),
                Text('NAME THIS RUN (optional)',
                    style: AppTheme.pressStart(10, color: PixelColors.accentGold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 60,
                  style: AppTheme.vt323(20),
                  decoration: InputDecoration(
                    hintText: templates.firstWhere((t) => t.id == _selectedTemplateId).title,
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
                  Text(_error!, style: AppTheme.vt323(16, color: PixelColors.accentRed)),
                ],
                const SizedBox(height: 16),
                PixelButton(
                  label: 'Begin',
                  icon: Icons.play_arrow,
                  fullWidth: true,
                  onPressed: _busy
                      ? null
                      : () => _start(templates.firstWhere((t) => t.id == _selectedTemplateId)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.selected, required this.onTap});
  final StoryTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PixelPanel(
        borderColor: selected ? PixelColors.accentGold : PixelColors.borderSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.title.toUpperCase(),
                    style: AppTheme.pressStart(13, color: PixelColors.accentGold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PixelColors.panelInner,
                    border: Border.all(color: PixelColors.borderSoft),
                  ),
                  child: Text(template.genre.toUpperCase(),
                      style: AppTheme.pressStart(7, color: PixelColors.textMuted)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(template.shortDescription, style: AppTheme.vt323(18)),
          ],
        ),
      ),
    );
  }
}
