import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/supabase_providers.dart';

/// Reference data is public-read and fairly small (a few dozen rows total). We fetch each
/// list once per app session and cache via Riverpod.

final classDefinitionsProvider =
    FutureProvider<List<ClassDefinition>>((ref) async {
  final db = ref.watch(dbProvider);
  final rows = await db
      .from('class_definitions')
      .select()
      .order('sort_order', ascending: true);
  return (rows as List<dynamic>)
      .map((r) => ClassDefinition.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});

final avatarTemplatesProvider =
    FutureProvider<List<AvatarTemplate>>((ref) async {
  final db = ref.watch(dbProvider);
  final rows = await db
      .from('avatar_templates')
      .select()
      .order('sort_order', ascending: true);
  return (rows as List<dynamic>)
      .map((r) => AvatarTemplate.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});

final skillsCatalogProvider = FutureProvider<List<Skill>>((ref) async {
  final db = ref.watch(dbProvider);
  final rows =
      await db.from('skills').select().order('sort_order', ascending: true);
  return (rows as List<dynamic>)
      .map((r) => Skill.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});

final storyTemplatesProvider = FutureProvider<List<StoryTemplate>>((ref) async {
  final db = ref.watch(dbProvider);
  final rows = await db
      .from('story_templates')
      .select()
      .eq('is_active', true)
      .order('sort_order', ascending: true);
  return (rows as List<dynamic>)
      .map((r) => StoryTemplate.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});
