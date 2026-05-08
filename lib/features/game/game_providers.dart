import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/data/models/reference.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';
import 'package:dungeonku/data/repositories/game_repository.dart';
import 'package:dungeonku/data/repositories/reference_repository.dart';

/// Coarse state machine. The Game UI only needs to know which mode it's in to decide
/// which controls to enable.
enum GameUiMode {
  loading,
  idle,
  submitting,
  awaitingRoll,
  resolvingRoll,
  inCombat,
  combatSubmitting,
  gameOver,
}

class GameState {
  GameState({
    required this.uiMode,
    required this.campaign,
    required this.character,
    required this.messages,
    required this.bosses,
    required this.sideMissions,
    required this.inventory,
    required this.skillIds,
    required this.allSkills,
    this.error,
    this.pendingRollId,
    this.requiresRoll,
    this.lastRollResult,
    this.combat,
  });

  final GameUiMode uiMode;
  final Campaign campaign;
  final CampaignCharacter character;
  final List<GameMessage> messages;
  final List<CampaignBoss> bosses;
  final List<CampaignSideMission> sideMissions;
  final List<InventoryItem> inventory;
  final List<String> skillIds;
  final List<Skill> allSkills;
  final String? error;
  final String? pendingRollId;
  final RequiresRoll? requiresRoll;
  final ResolveRollResult? lastRollResult;
  final CombatTurnResult? combat;

  GameState copyWith({
    GameUiMode? uiMode,
    Campaign? campaign,
    CampaignCharacter? character,
    List<GameMessage>? messages,
    List<CampaignBoss>? bosses,
    List<CampaignSideMission>? sideMissions,
    List<InventoryItem>? inventory,
    List<String>? skillIds,
    List<Skill>? allSkills,
    String? error,
    bool clearError = false,
    String? pendingRollId,
    bool clearPendingRoll = false,
    RequiresRoll? requiresRoll,
    bool clearRequiresRoll = false,
    ResolveRollResult? lastRollResult,
    bool clearLastRollResult = false,
    CombatTurnResult? combat,
    bool clearCombat = false,
  }) {
    return GameState(
      uiMode: uiMode ?? this.uiMode,
      campaign: campaign ?? this.campaign,
      character: character ?? this.character,
      messages: messages ?? this.messages,
      bosses: bosses ?? this.bosses,
      sideMissions: sideMissions ?? this.sideMissions,
      inventory: inventory ?? this.inventory,
      skillIds: skillIds ?? this.skillIds,
      allSkills: allSkills ?? this.allSkills,
      error: clearError ? null : (error ?? this.error),
      pendingRollId:
          clearPendingRoll ? null : (pendingRollId ?? this.pendingRollId),
      requiresRoll:
          clearRequiresRoll ? null : (requiresRoll ?? this.requiresRoll),
      lastRollResult:
          clearLastRollResult ? null : (lastRollResult ?? this.lastRollResult),
      combat: clearCombat ? null : (combat ?? this.combat),
    );
  }

  /// The 3-5 options shown in the action panel: from the **latest** DM
  /// message only. We deliberately do NOT walk further back — older options
  /// refer to a stale scene and would mislead the player. If the latest DM
  /// turn carries no options the panel collapses, and the player falls back
  /// to free-text via the pencil button.
  List<ChatOption> get currentOptions {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == 'dm') return m.options;
    }
    return const [];
  }

  /// How many consecutive cheap-resolve player turns just happened.
  /// Used to decide whether to escalate the next template_common tap to a
  /// full dm-turn (so the story can actually advance).
  int get recentCheapResolveStreak {
    var n = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role != 'player') continue;
      if (m.wasCheapResolve) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }
}

class GameNotifier extends AsyncNotifier<GameState> {
  late String _campaignId;
  Future<void> Function()? _lastRetry;

  Future<void> init(String campaignId) async {
    _campaignId = campaignId;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<GameState> _load() async {
    final campaignsRepo = ref.read(campaignsRepositoryProvider);
    final allCampaigns = await ref.read(campaignsListProvider.future);
    final campaign = allCampaigns.firstWhere(
      (c) => c.id == _campaignId,
      orElse: () => throw StateError('campaign not found'),
    );
    final results = await Future.wait([
      campaignsRepo.loadCampaignCharacter(_campaignId),
      campaignsRepo.loadInventory(_campaignId),
      campaignsRepo.loadBosses(_campaignId),
      campaignsRepo.loadSideMissions(_campaignId),
      campaignsRepo.loadMessages(_campaignId),
      campaignsRepo.loadLearnedSkillIds(_campaignId),
      ref.read(skillsCatalogProvider.future),
    ]);
    return GameState(
      uiMode:
          campaign.status == 'active' ? GameUiMode.idle : GameUiMode.gameOver,
      campaign: campaign,
      character: results[0] as CampaignCharacter,
      inventory: results[1] as List<InventoryItem>,
      bosses: results[2] as List<CampaignBoss>,
      sideMissions: results[3] as List<CampaignSideMission>,
      messages: results[4] as List<GameMessage>,
      skillIds: results[5] as List<String>,
      allSkills: results[6] as List<Skill>,
    );
  }

  @override
  Future<GameState> build() async {
    // Real init happens via init(). Until then we throw.
    throw StateError(
        'GameNotifier not initialised — call ref.read(gameNotifierProvider.notifier).init(id) first');
  }

  /// Builds a placeholder player [GameMessage] for optimistic insertion.
  /// We use a recognisable id prefix so we can spot it in logs; the next
  /// `_refreshAfterTurn` replaces the whole list with the server-side rows
  /// (which will include a real uuid for the same content), so the temp
  /// row simply disappears from view.
  GameMessage _optimisticPlayerMessage(String text) {
    return GameMessage(
      id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
      campaignId: _campaignId,
      role: 'player',
      content: text,
      situationType: null,
      options: const [],
      requiresRoll: null,
      wasCheapResolve: false,
      pivotalMoment: false,
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<void> submitPlayerMessage(String text,
      {String? selectedOptionId}) async {
    final cur = state.value;
    if (cur == null) return;
    // Optimistically append the player's bubble so the chat reads
    //   1. user picks action  → their bubble lands instantly
    //   2. "DM weaves the tale..." typing indicator appears below
    //   3. server returns  → refresh swaps the temp bubble for the saved
    //      row + the real DM bubble.
    // Without this, both bubbles popped in together when the API resolved.
    final optimistic = _optimisticPlayerMessage(text);
    state = AsyncValue.data(cur.copyWith(
      uiMode: GameUiMode.submitting,
      clearError: true,
      messages: [...cur.messages, optimistic],
    ));
    try {
      final res = await ref.read(gameRepositoryProvider).dmTurn(
            campaignId: _campaignId,
            playerMessage: text,
            selectedOptionId: selectedOptionId,
          );
      await _refreshAfterTurn();
      _applyDmTurnResult(res);
    } catch (e) {
      _lastRetry =
          () => submitPlayerMessage(text, selectedOptionId: selectedOptionId);
      state = AsyncValue.data((state.value ?? cur)
          .copyWith(uiMode: GameUiMode.idle, error: _humanError(e)));
    }
  }

  /// Max consecutive cheap-resolve turns before we force the next
  /// template_common tap through the LLM dm-turn pipeline.
  /// Two cheap-resolves in a row is fine ("look around", "search") —
  /// a third would be the player getting stuck in a static-narration loop,
  /// so we escalate to keep the story moving.
  static const int _maxConsecutiveCheapResolves = 2;

  Future<void> tapOption(ChatOption option) async {
    final cur = state.value;
    final shouldEscalate = cur != null &&
        option.kind == 'template_common' &&
        cur.recentCheapResolveStreak >= _maxConsecutiveCheapResolves;

    if (option.kind == 'template_common' && !shouldEscalate) {
      await _cheapResolve(option);
    } else {
      // Escalated cheap-resolve OR a situational/pivotal option —
      // route through dm-turn so the LLM produces fresh narration
      // and scene-specific options.
      await submitPlayerMessage(option.label, selectedOptionId: option.id);
    }
  }

  Future<void> _cheapResolve(ChatOption option) async {
    final cur = state.value;
    if (cur == null) return;
    // Optimistic player bubble — same reasoning as in submitPlayerMessage:
    // the player should see their action land before the typing indicator
    // shows up, not in the same paint as the DM's response.
    final optimistic = _optimisticPlayerMessage(option.label);
    state = AsyncValue.data(cur.copyWith(
      uiMode: GameUiMode.submitting,
      clearError: true,
      messages: [...cur.messages, optimistic],
    ));
    try {
      await ref.read(gameRepositoryProvider).cheapResolve(
            campaignId: _campaignId,
            optionId: option.id,
          );
      await _refreshAfterTurn();
    } catch (e) {
      _lastRetry = () => _cheapResolve(option);
      state = AsyncValue.data((state.value ?? cur)
          .copyWith(uiMode: GameUiMode.idle, error: _humanError(e)));
    }
  }

  Future<void> resolvePendingRoll() async {
    final cur = state.value;
    if (cur == null || cur.pendingRollId == null) return;
    // Stay in resolvingRoll mode for the WHOLE animation lifecycle:
    //   tap Roll → spin → result lands → hold → onDone
    // We deliberately do NOT refresh messages here — if we did, the new
    // DM bubble would render *while the dice overlay is still up* which
    // looks chaotic. Refresh + cleanup is done in `finishRollFlow` once the
    // overlay's onDone fires.
    state = AsyncValue.data(cur.copyWith(uiMode: GameUiMode.resolvingRoll));
    try {
      final res = await ref
          .read(gameRepositoryProvider)
          .resolveRoll(pendingRollId: cur.pendingRollId!);
      // Feed the result into state so DiceOverlay lands on the rolled face.
      // Keep uiMode at resolvingRoll so the overlay stays mounted.
      state = AsyncValue.data((state.value ?? cur).copyWith(
        uiMode: GameUiMode.resolvingRoll,
        lastRollResult: res,
      ));
    } catch (e) {
      _lastRetry = () => resolvePendingRoll();
      state = AsyncValue.data((state.value ?? cur).copyWith(
        uiMode: GameUiMode.idle,
        clearPendingRoll: true,
        clearRequiresRoll: true,
        error: _humanError(e),
      ));
    }
  }

  /// Called when the [DiceOverlay] finishes its land-and-hold animation.
  /// At this point we refresh the campaign state (which pulls in both the
  /// new player-side roll bubble and the DM's outcome narration) and
  /// transition out of the roll mode.
  Future<void> finishRollFlow() async {
    final cur = state.value;
    if (cur == null) return;
    final died = cur.lastRollResult?.characterDied ?? false;
    await _refreshAfterTurn();
    final after = state.value ?? cur;
    state = AsyncValue.data(after.copyWith(
      uiMode: died ? GameUiMode.gameOver : GameUiMode.idle,
      clearPendingRoll: true,
      clearRequiresRoll: true,
      clearLastRollResult: true,
    ));
  }

  Future<void> submitCombatAction(Map<String, dynamic> action) async {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncValue.data(
        cur.copyWith(uiMode: GameUiMode.combatSubmitting, clearError: true));
    try {
      final res = await ref.read(gameRepositoryProvider).combatAction(
            campaignId: _campaignId,
            action: action,
          );
      await _refreshAfterTurn();
      final next = state.value ?? cur;
      if (res.kind == 'player_defeated') {
        state = AsyncValue.data(
            next.copyWith(uiMode: GameUiMode.gameOver, combat: res));
      } else if (res.kind == 'victory' || res.kind == 'fled') {
        state = AsyncValue.data(
            next.copyWith(uiMode: GameUiMode.idle, clearCombat: true));
      } else {
        state = AsyncValue.data(
            next.copyWith(uiMode: GameUiMode.inCombat, combat: res));
      }
    } catch (e) {
      _lastRetry = () => submitCombatAction(action);
      state = AsyncValue.data((state.value ?? cur)
          .copyWith(uiMode: GameUiMode.inCombat, error: _humanError(e)));
    }
  }

  /// After any turn that mutated state, re-pull messages + character + bosses + side missions.
  Future<void> _refreshAfterTurn() async {
    final cur = state.value;
    if (cur == null) return;
    final repo = ref.read(campaignsRepositoryProvider);
    final results = await Future.wait([
      repo.loadCampaignCharacter(_campaignId),
      repo.loadInventory(_campaignId),
      repo.loadBosses(_campaignId),
      repo.loadSideMissions(_campaignId),
      repo.loadMessages(_campaignId),
      repo.loadLearnedSkillIds(_campaignId),
    ]);
    // Re-read campaigns list so phase changes are picked up.
    ref.invalidate(campaignsListProvider);
    final allCampaigns = await ref.read(campaignsListProvider.future);
    final campaign = allCampaigns.firstWhere((c) => c.id == _campaignId,
        orElse: () => cur.campaign);

    state = AsyncValue.data(cur.copyWith(
      campaign: campaign,
      character: results[0] as CampaignCharacter,
      inventory: results[1] as List<InventoryItem>,
      bosses: results[2] as List<CampaignBoss>,
      sideMissions: results[3] as List<CampaignSideMission>,
      messages: results[4] as List<GameMessage>,
      skillIds: results[5] as List<String>,
      uiMode:
          campaign.status == 'active' ? GameUiMode.idle : GameUiMode.gameOver,
    ));
  }

  void _applyDmTurnResult(DmTurnResult res) {
    final cur = state.value;
    if (cur == null) return;
    if (res.kind == 'requires_roll' &&
        res.requiresRoll != null &&
        res.pendingRollId != null) {
      state = AsyncValue.data(cur.copyWith(
        uiMode: GameUiMode.awaitingRoll,
        pendingRollId: res.pendingRollId,
        requiresRoll: res.requiresRoll,
      ));
    } else if (res.characterDied || res.campaignStatus == 'failed') {
      state = AsyncValue.data(cur.copyWith(uiMode: GameUiMode.gameOver));
    } else {
      // If a combat_start state_change happened, switch into combat mode (the combat
      // encounter row was created by the Edge Function; we'll need to fetch enemies on the
      // first combat action). We leave it at idle here; the GameScreen decides to show the
      // "Engage" button when there's an active encounter visible in messages.
      state = AsyncValue.data(cur.copyWith(uiMode: GameUiMode.idle));
    }
  }

  /// Start engaging with an active combat encounter (after combat_start was emitted).
  /// We send a noop action ('attack' on the first available target) — the combat-action
  /// endpoint handles initiative on first call.
  Future<void> engageCombat() async {
    await submitCombatAction({'kind': 'attack'});
  }

  void clearError() {
    final cur = state.value;
    if (cur != null) state = AsyncValue.data(cur.copyWith(clearError: true));
  }

  /// Re-run the last failed action, if any.
  Future<void> retry() async {
    final fn = _lastRetry;
    if (fn == null) return;
    _lastRetry = null;
    await fn();
  }

  /// Strip noisy exception wrappers into a short player-facing string.
  static String _humanError(Object e) {
    final raw = e.toString();
    // Provider rate limit / quota — most common when an LLM gateway throttles
    // us. Mention the cool-down so the player doesn't just spam retry.
    if (raw.contains('429') ||
        raw.toLowerCase().contains('rate limit') ||
        raw.toLowerCase().contains('quota') ||
        raw.toLowerCase().contains('insufficient_quota')) {
      return 'AI is rate-limited. Please wait a moment, then retry.';
    }
    // Supabase FunctionException often contains "status: 502" etc. These are
    // usually upstream LLM gateway / Cloudflare hiccups.
    if (raw.contains('502') || raw.contains('503') || raw.contains('504')) {
      return 'The AI service is temporarily unavailable. Try again shortly.';
    }
    if (raw.contains('401') || raw.contains('403')) {
      return 'Authentication error. Please log in again.';
    }
    if (raw.contains('SocketException') || raw.contains('ClientException')) {
      return 'Network error — check your connection and retry.';
    }
    if (raw.contains('TimeoutException') || raw.contains('timed out')) {
      return 'Request timed out. Tap retry to try again.';
    }
    // Generic fallback: truncate for readability.
    final clean = raw.replaceFirst(
        RegExp(r'^(Exception|FunctionException|Error):?\s*'), '');
    return clean.length > 120 ? '${clean.substring(0, 117)}...' : clean;
  }
}

final gameNotifierProvider =
    AsyncNotifierProvider<GameNotifier, GameState>(GameNotifier.new);
