import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/data/supabase_providers.dart';

/// User profile + AI role preferences (added in migration
/// 20260511000000). Used by the SettingsScreen → AI Roles screen so
/// players can opt in / out of paid LLM features per role.
class AiRoleToggles {
  const AiRoleToggles({
    required this.reskinner,
    required this.intentMapper,
    required this.npcVoice,
    required this.rollNarrator,
  });

  final bool reskinner;
  final bool intentMapper;
  final bool npcVoice;
  final bool rollNarrator;

  /// All-off default — matches the server's behavior when the row is
  /// missing entirely.
  static const allOff = AiRoleToggles(
    reskinner: false,
    intentMapper: false,
    npcVoice: false,
    rollNarrator: false,
  );

  AiRoleToggles copyWith({
    bool? reskinner,
    bool? intentMapper,
    bool? npcVoice,
    bool? rollNarrator,
  }) =>
      AiRoleToggles(
        reskinner: reskinner ?? this.reskinner,
        intentMapper: intentMapper ?? this.intentMapper,
        npcVoice: npcVoice ?? this.npcVoice,
        rollNarrator: rollNarrator ?? this.rollNarrator,
      );

  factory AiRoleToggles.fromJson(Map<String, dynamic> json) => AiRoleToggles(
        reskinner: (json['ai_role_reskinner_enabled'] as bool?) ?? false,
        intentMapper: (json['ai_role_intent_mapper_enabled'] as bool?) ?? false,
        npcVoice: (json['ai_role_npc_voice_enabled'] as bool?) ?? false,
        rollNarrator: (json['ai_role_roll_narrator_enabled'] as bool?) ?? false,
      );
}

class ProfilesRepository {
  ProfilesRepository(this._db);
  final SupabaseQuerySchema _db;

  /// Reads the four AI role toggles for the current user. Returns
  /// `AiRoleToggles.allOff` if the row doesn't exist yet (e.g.
  /// freshly-signed-up account).
  Future<AiRoleToggles> loadAiToggles(String userId) async {
    final row = await _db
        .from('profiles')
        .select(
          'ai_role_reskinner_enabled, ai_role_intent_mapper_enabled, ai_role_npc_voice_enabled, ai_role_roll_narrator_enabled',
        )
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return AiRoleToggles.allOff;
    return AiRoleToggles.fromJson(row);
  }

  /// Persists the four toggles in one upsert. Server schema enforces the
  /// row's id matches an auth.users row via FK + RLS.
  Future<void> saveAiToggles(String userId, AiRoleToggles toggles) async {
    await _db.from('profiles').upsert({
      'id': userId,
      'ai_role_reskinner_enabled': toggles.reskinner,
      'ai_role_intent_mapper_enabled': toggles.intentMapper,
      'ai_role_npc_voice_enabled': toggles.npcVoice,
      'ai_role_roll_narrator_enabled': toggles.rollNarrator,
    });
  }
}

final profilesRepositoryProvider = Provider<ProfilesRepository>((ref) {
  return ProfilesRepository(ref.watch(dbProvider));
});

/// Reactive: re-fetches when invalidated after toggle save.
final aiTogglesProvider =
    FutureProvider.autoDispose<AiRoleToggles>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return AiRoleToggles.allOff;
  return ref.watch(profilesRepositoryProvider).loadAiToggles(user.id);
});
