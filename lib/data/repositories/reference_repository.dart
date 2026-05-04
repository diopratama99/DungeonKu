import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/supabase_providers.dart';

/// Reference data is public-read and fairly small (a few dozen rows total). We fetch each
/// list once per app session and cache via Riverpod.

final classDefinitionsProvider = FutureProvider<List<ClassDefinition>>((ref) async {
  final sb = ref.watch(supabaseClientProvider);
  final rows = await sb.from('class_definitions').select().order('sort_order');
  return (rows as List<dynamic>)
      .map((r) => ClassDefinition.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});

final avatarTemplatesProvider = FutureProvider<List<AvatarTemplate>>((ref) async {
  final sb = ref.watch(supabaseClientProvider);
  final rows = await sb.from('avatar_templates').select().order('sort_order');
  return (rows as List<dynamic>)
      .map((r) => AvatarTemplate.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});

final skillsCatalogProvider = FutureProvider<List<Skill>>((ref) async {
  final sb = ref.watch(supabaseClientProvider);
  final rows = await sb.from('skills').select().order('sort_order');
  return (rows as List<dynamic>)
      .map((r) => Skill.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});

final storyTemplatesProvider = FutureProvider<List<StoryTemplate>>((ref) async {
  final sb = ref.watch(supabaseClientProvider);
  final rows = await sb
      .from('story_templates')
      .select()
      .eq('is_active', true)
      .order('sort_order');
  return (rows as List<dynamic>)
      .map((r) => StoryTemplate.fromJson(r as Map<String, dynamic>))
      .toList(growable: false);
});
