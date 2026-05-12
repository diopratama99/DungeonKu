// AI Roles settings — opt in/out of the four LLM "roles" introduced
// by the story-engine redesign. Default is all off (zero-token mode).
//
// Each toggle costs roughly:
//   • Reskinner    (Role A) — ~150 in / ~80 out per pivotal node
//   • NPC voice    (Role C) — ~100 in / ~50 out per dialog node
//   • Intent map   (Role B) — ~200 in / ~30 out, capped 5/session
//   • Roll narrate (Role D) — ~100 in / ~80 out, only on crit/fumble
//
// Numbers are documented in STORY_ENGINE_REDESIGN.md §4 and shown to
// the user verbatim so they can decide.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/retro_app_bar.dart';
import 'package:dungeonku/data/repositories/profiles_repository.dart';
import 'package:dungeonku/data/supabase_providers.dart';

class AiRolesScreen extends ConsumerStatefulWidget {
  const AiRolesScreen({super.key});

  @override
  ConsumerState<AiRolesScreen> createState() => _AiRolesScreenState();
}

class _AiRolesScreenState extends ConsumerState<AiRolesScreen> {
  AiRoleToggles? _toggles;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() {
        _loading = false;
        _toggles = AiRoleToggles.allOff;
      });
      return;
    }
    try {
      final repo = ref.read(profilesRepositoryProvider);
      final t = await repo.loadAiToggles(user.id);
      if (!mounted) return;
      setState(() {
        _toggles = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save(AiRoleToggles next) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _toggles = next;
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profilesRepositoryProvider).saveAiToggles(user.id, next);
      if (!mounted) return;
      ref.invalidate(aiTogglesProvider);
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      appBar: const RetroAppBar(title: 'AI ROLES'),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = _toggles ?? AiRoleToggles.allOff;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WHAT ARE AI ROLES?',
                style: AppTheme.pressStart(11, color: PixelColors.accentGold),
              ),
              const SizedBox(height: 8),
              Text(
                'The story is authored by humans. AI roles only reshape narration — they never change the rules, dice, or branching outcomes. Toggle them per role; everything off = zero LLM cost per turn.',
                style: AppTheme.vt323(16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            color: PixelColors.accentRed.withValues(alpha: 0.2),
            child: Text(_error!,
                style: AppTheme.vt323(14, color: PixelColors.accentRed)),
          ),
          const SizedBox(height: 16),
        ],
        _RoleTile(
          name: 'FLAVOR RESKINNER',
          subtitle: 'Role A',
          description:
              'Rewrites the prose of pivotal scenes in your avatar\u2019s voice. Facts and named entities stay exact; only the wording changes.',
          cost: '~150 in / ~80 out per pivotal node',
          enabled: t.reskinner,
          onChanged: _saving ? null : (v) => _save(t.copyWith(reskinner: v)),
        ),
        const SizedBox(height: 12),
        _RoleTile(
          name: 'NPC VOICE',
          subtitle: 'Role C',
          description:
              'Rewrites NPC dialog so each character actually sounds like themselves \u2014 gruff, cracked-open, tender, calculating, etc. Information content is preserved exactly.',
          cost: '~100 in / ~50 out per dialog node',
          enabled: t.npcVoice,
          onChanged: _saving ? null : (v) => _save(t.copyWith(npcVoice: v)),
        ),
        const SizedBox(height: 12),
        _RoleTile(
          name: 'INTENT MAPPER',
          subtitle: 'Role B',
          description:
              'Lets you type free-text actions ("I bribe the guard with a coin"). The model maps your sentence to the closest scripted option, capped at 5 free-text uses per campaign.',
          cost: '~200 in / ~30 out per call, 5/campaign max',
          enabled: t.intentMapper,
          onChanged: _saving ? null : (v) => _save(t.copyWith(intentMapper: v)),
        ),
        const SizedBox(height: 12),
        _RoleTile(
          name: 'ROLL NARRATOR',
          subtitle: 'Role D',
          description:
              'Narrates dice rolls vividly when they crit, fumble, or land far from the DC. Otherwise stays out of the way. Outcomes (success/fail) are unchanged \u2014 only the prose around them is.',
          cost: '~100 in / ~80 out, only on crits and big margins',
          enabled: t.rollNarrator,
          onChanged: _saving ? null : (v) => _save(t.copyWith(rollNarrator: v)),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'ALL OFF \u2192 deterministic state-machine play, zero tokens.',
            textAlign: TextAlign.center,
            style: AppTheme.vt323(14, color: PixelColors.textMuted),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.name,
    required this.subtitle,
    required this.description,
    required this.cost,
    required this.enabled,
    required this.onChanged,
  });

  final String name;
  final String subtitle;
  final String description;
  final String cost;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

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
                child: Text(name, style: AppTheme.pressStart(10, color: PixelColors.accentGold)),
              ),
              const SizedBox(width: 10),
              Switch(
                value: enabled,
                onChanged: onChanged,
                activeThumbColor: PixelColors.accentGold,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style: AppTheme.vt323(13, color: PixelColors.textMuted)),
          const SizedBox(height: 8),
          Text(description, style: AppTheme.vt323(16)),
          const SizedBox(height: 6),
          Text(cost, style: AppTheme.vt323(13, color: PixelColors.textMuted)),
        ],
      ),
    );
  }
}
