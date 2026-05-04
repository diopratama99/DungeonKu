import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/supabase_providers.dart';

class CharactersRepository {
  CharactersRepository(this._sb);
  final SupabaseClient _sb;

  Future<List<Character>> list(String userId) async {
    final rows = await _sb
        .from('characters')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return (rows as List<dynamic>)
        .map((r) => Character.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Character> create({
    required String userId,
    required String name,
    required String classId,
    required String baseElement,
    required String avatarId,
    required Map<String, int> stats,
  }) async {
    final inserted = await _sb
        .from('characters')
        .insert({
          'user_id': userId,
          'name': name,
          'class': classId,
          'base_element': baseElement,
          'avatar_id': avatarId,
          'stats': stats,
        })
        .select()
        .single();
    return Character.fromJson(inserted);
  }

  Future<void> rename(String characterId, String newName) async {
    await _sb.from('characters').update({'name': newName}).eq('id', characterId);
  }

  Future<void> delete(String characterId) async {
    await _sb.from('characters').delete().eq('id', characterId);
  }

  /// Returns the count of campaigns currently using this character (any status).
  /// We use this to warn the user before deleting.
  Future<int> activeCampaignCount(String characterId) async {
    final res = await _sb
        .from('campaigns')
        .select('id')
        .eq('character_id', characterId)
        .neq('status', 'failed')
        .neq('status', 'completed');
    return (res as List<dynamic>).length;
  }
}

final charactersRepositoryProvider = Provider<CharactersRepository>((ref) {
  return CharactersRepository(ref.watch(supabaseClientProvider));
});

/// Watches the current user's character roster. Refreshes on character mutations via
/// `ref.invalidate(charactersListProvider)`.
final charactersListProvider = FutureProvider<List<Character>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(charactersRepositoryProvider).list(user.id);
});
