import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/data/models/story_node.dart';
import 'package:dungeonku/data/repositories/game_repository.dart'
    show GameException;
import 'package:dungeonku/data/supabase_providers.dart';

/// Result of a Phase 3 free-text intent mapping call.
class IntentMapResult {
  IntentMapResult({
    required this.optionId,
    required this.reason,
    required this.remaining,
  });

  /// The matched scripted option id, or null if no option fit.
  final String? optionId;

  /// Server-supplied human-readable explanation. Always non-empty.
  final String reason;

  /// Remaining free-text uses for this campaign (cap is 5).
  final int remaining;

  factory IntentMapResult.fromJson(Map<String, dynamic> json) =>
      IntentMapResult(
        optionId: json['option_id'] as String?,
        reason: (json['reason'] as String?) ?? '',
        remaining: (json['remaining'] as num? ?? 0).toInt(),
      );
}

/// Wraps the three story-graph endpoints:
///
///   • `/story-turn`    — render the current node + offered options
///   • `/player-action` — take an option, transition, render the new node
///   • `/intent-map`    — Phase 3 Role B; map free text to an option id
///
/// All return typed results. Errors come back as [GameException]
/// (re-using the same exception type as the legacy GameRepository so the
/// UI error handling can be shared).
class StoryEngineRepository {
  StoryEngineRepository(this._sb);
  final SupabaseClient _sb;

  /// Render the campaign's current node. The first call after campaign
  /// creation will server-side initialize `campaign_node_state` from
  /// the template's `root_node_id`.
  Future<StoryNodePayload> currentTurn({required String campaignId}) async {
    final res = await _sb.functions.invoke(
      'story-turn',
      body: {'campaign_id': campaignId},
    );
    _throwIfError(res);
    return StoryNodePayload.fromJson(res.data as Map<String, dynamic>);
  }

  /// Take an option from the current node. Server validates ownership,
  /// re-checks gating, applies edge consumes, transitions cursor, then
  /// returns the new node payload.
  Future<StoryNodePayload> takeOption({
    required String campaignId,
    required String optionId,
  }) async {
    final res = await _sb.functions.invoke(
      'player-action',
      body: {'campaign_id': campaignId, 'option_id': optionId},
    );
    _throwIfError(res);
    return StoryNodePayload.fromJson(res.data as Map<String, dynamic>);
  }

  /// Phase 3 Role B — map a free-text action to one of the currently
  /// available scripted options. Server-side rate-limited to 5 calls
  /// per campaign session. The client is expected to follow up with
  /// [takeOption] using the returned option id (when non-null) so the
  /// player still sees an explicit "you chose X" beat in the UI.
  Future<IntentMapResult> mapIntent({
    required String campaignId,
    required String freeText,
  }) async {
    final res = await _sb.functions.invoke(
      'intent-map',
      body: {'campaign_id': campaignId, 'free_text': freeText},
    );
    _throwIfError(res);
    return IntentMapResult.fromJson(res.data as Map<String, dynamic>);
  }

  void _throwIfError(FunctionResponse res) {
    if (res.status >= 400 ||
        (res.data is Map && (res.data as Map).containsKey('error'))) {
      final err = (res.data is Map) ? (res.data as Map)['error'] : null;
      throw GameException(
        code: (err is Map ? err['code'] as String? : null) ?? 'unknown',
        message: (err is Map ? err['message'] as String? : null) ??
            'Story engine call failed',
        status: res.status,
      );
    }
  }
}

final storyEngineRepositoryProvider = Provider<StoryEngineRepository>((ref) {
  return StoryEngineRepository(ref.watch(supabaseClientProvider));
});
