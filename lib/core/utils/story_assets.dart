import 'package:dungeonku/core/utils/asset_index.dart';

/// Resolves which PNG (if any) should be shown for a given story moment.
///
/// All folders under `assets/images/` are optional — if the artist hasn't
/// dropped a file in yet, every method returns `null` and the UI falls back to
/// a procedural pixel-panel.
///
/// Lookup order is "specific → generic" so adding more art over time only ever
/// improves the look without breaking existing screens.
class StoryAssetResolver {
  StoryAssetResolver(this._index);

  final AssetIndex _index;

  static String _slug(String? raw) {
    if (raw == null) return '';
    final s = raw.toLowerCase().trim();
    final buf = StringBuffer();
    for (final ch in s.codeUnits) {
      final c = String.fromCharCode(ch);
      if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        buf.write(c);
      } else if (c == "'" || c == '`' || c == '’') {
        // Drop apostrophes entirely so "Lord Brundir's Shade" → "lord_brundirs_shade"
        // (matching how the artist named the PNG).
      } else if (c == ' ' || c == '-' || c == '_') {
        buf.write('_');
      }
    }
    return buf
        .toString()
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Background scene for the current story beat.
  String? backgroundFor({
    String? templateId,
    String? phase,
    String? situationType,
    bool inCombat = false,
    String? bossName,
    String? element,
  }) {
    final t = _slug(templateId);
    final p = _slug(phase);
    final s = _slug(situationType);
    final b = _slug(bossName);
    final e = _slug(element);

    final exact = <String>[
      if (inCombat && b.isNotEmpty) 'assets/images/backgrounds/boss_$b.png',
      if (inCombat && e.isNotEmpty) 'assets/images/backgrounds/combat_$e.png',
      if (inCombat) 'assets/images/backgrounds/combat.png',
      if (t.isNotEmpty && p.isNotEmpty) 'assets/images/backgrounds/${t}_$p.png',
      if (t.isNotEmpty && s.isNotEmpty) 'assets/images/backgrounds/${t}_$s.png',
      if (s.isNotEmpty) 'assets/images/backgrounds/$s.png',
      if (p.isNotEmpty) 'assets/images/backgrounds/$p.png',
      if (t.isNotEmpty) 'assets/images/backgrounds/$t.png',
      'assets/images/backgrounds/default.png',
    ];
    final hit = _index.firstExisting(exact);
    if (hit != null) return hit;
    // Fuzzy fallback: any backdrop the artist dropped under this template.
    if (t.isNotEmpty) {
      return _index.firstWithPrefix('assets/images/backgrounds/${t}_');
    }
    return null;
  }

  /// Pool of backgrounds available for this campaign template — useful when
  /// you want to vary the scene as the story progresses.
  List<String> backgroundPoolFor({String? templateId}) {
    final t = _slug(templateId);
    if (t.isEmpty) return const [];
    return _index.listWithPrefix('assets/images/backgrounds/${t}_');
  }

  /// Player portrait, keyed off the avatar template id.
  String? playerPortrait({String? avatarId, String? classId}) {
    final a = _slug(avatarId);
    final c = _slug(classId);
    return _index.firstExisting([
      if (a.isNotEmpty) 'assets/images/avatars/$a.png',
      if (c.isNotEmpty) 'assets/images/avatars/${c}_default.png',
      if (c.isNotEmpty) 'assets/images/avatars/$c.png',
      'assets/images/avatars/default.png',
    ]);
  }

  /// Enemy/boss portrait shown opposite the player during combat.
  String? enemyPortrait(
      {String? bossId,
      String? bossName,
      String? element,
      bool isBoss = false}) {
    final id = _slug(bossId);
    final name = _slug(bossName);
    final el = _slug(element);
    final hit = _index.firstExisting([
      if (isBoss && id.isNotEmpty) 'assets/images/bosses/$id.png',
      if (isBoss && name.isNotEmpty) 'assets/images/bosses/$name.png',
      if (name.isNotEmpty) 'assets/images/bosses/$name.png',
      if (name.isNotEmpty) 'assets/images/monsters/$name.png',
      if (el.isNotEmpty) 'assets/images/monsters/${el}_minion.png',
      'assets/images/monsters/default.png',
    ]);
    if (hit != null) return hit;
    // Substring search: artists may name files with extra qualifiers.
    if (name.isNotEmpty) {
      for (final base in const [
        'assets/images/bosses/',
        'assets/images/monsters/'
      ]) {
        final candidates = _index.listWithPrefix(base);
        for (final c in candidates) {
          if (c.contains(name)) return c;
        }
      }
    }
    return null;
  }

  /// Optional one-off "story art" panel (CG illustration) for pivotal beats.
  /// `intro` phase aliases to `_opening` to match how the artist named files.
  String? storyArt({String? templateId, String? phase, bool pivotal = false}) {
    if (!pivotal) return null;
    final t = _slug(templateId);
    final p = _slug(phase);
    // The intro CG is conventionally named `<template>_opening.png`.
    final phaseAlias = p == 'intro' ? 'opening' : p;
    return _index.firstExisting([
      if (t.isNotEmpty && phaseAlias.isNotEmpty)
        'assets/images/story-art/${t}_$phaseAlias.png',
      if (t.isNotEmpty && p.isNotEmpty) 'assets/images/story-art/${t}_$p.png',
      if (p.isNotEmpty) 'assets/images/story-art/$p.png',
      if (t.isNotEmpty) 'assets/images/story-art/$t.png',
    ]);
  }
}
