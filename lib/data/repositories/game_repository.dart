import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/data/supabase_providers.dart';

/// Wraps the four player-action Edge Function endpoints. Every method swallows the network
/// detail and returns a typed result. The client never touches OpenAI directly.
class GameRepository {
  GameRepository(this._sb);
  final SupabaseClient _sb;

  Future<DmTurnResult> dmTurn({
    required String campaignId,
    required String playerMessage,
    String? selectedOptionId,
  }) async {
    final res = await _sb.functions.invoke(
      'dm-turn',
      body: {
        'campaign_id': campaignId,
        'player_message': playerMessage,
        if (selectedOptionId != null) 'selected_option_id': selectedOptionId,
      },
    );
    _throwIfError(res);
    return DmTurnResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CheapResolveResult> cheapResolve({
    required String campaignId,
    required String optionId,
  }) async {
    final res = await _sb.functions.invoke(
      'cheap-resolve',
      body: {'campaign_id': campaignId, 'option_id': optionId},
    );
    _throwIfError(res);
    return CheapResolveResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ResolveRollResult> resolveRoll({required String pendingRollId}) async {
    final res = await _sb.functions.invoke(
      'resolve-roll',
      body: {'pending_roll_id': pendingRollId},
    );
    _throwIfError(res);
    return ResolveRollResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CombatTurnResult> combatAction({
    required String campaignId,
    required Map<String, dynamic> action,
  }) async {
    final res = await _sb.functions.invoke(
      'combat-action',
      body: {'campaign_id': campaignId, 'action': action},
    );
    _throwIfError(res);
    return CombatTurnResult.fromJson(res.data as Map<String, dynamic>);
  }

  void _throwIfError(FunctionResponse res) {
    if (res.status >= 400 || (res.data is Map && (res.data as Map).containsKey('error'))) {
      final err = (res.data is Map) ? (res.data as Map)['error'] : null;
      throw GameException(
        code: (err is Map ? err['code'] as String? : null) ?? 'unknown',
        message: (err is Map ? err['message'] as String? : null) ?? 'Edge function failed',
        status: res.status,
      );
    }
  }
}

class GameException implements Exception {
  GameException({required this.code, required this.message, required this.status});
  final String code;
  final String message;
  final int status;
  @override
  String toString() => 'GameException($status, $code): $message';
}

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository(ref.watch(supabaseClientProvider));
});
