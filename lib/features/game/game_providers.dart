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
      pendingRollId: clearPendingRoll ? null : (pendingRollId ?? this.pendingRollId),
      requiresRoll: clearRequiresRoll ? null : (requiresRoll ?? this.requiresRoll),
      lastRollResult: clearLastRollResult ? null : (lastRollResult ?? this.lastRollResult),
      combat: clearCombat ? null : (combat ?? this.combat),
    );
  }

  /// The 3-5 options shown in the action panel: from the latest DM message that has any.
  List<ChatOption> get currentOptions {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == 'dm' && m.options.isNotEmpty) return m.options;
    }
    return const [];
  }
}

class GameNotifier extends AsyncNotifier<GameState> {
  late String _campaignId;

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
      uiMode: campaign.status == 'active' ? GameUiMode.idle : GameUiMode.gameOver,
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
    throw StateError('GameNotifier not initialised — call ref.read(gameNotifierProvider.notifier).init(id) first');
  }

  Future<void> submitPlayerMessage(String text, {String? selectedOptionId}) async {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncValue.data(cur.copyWith(uiMode: GameUiMode.submitting, clearError: true));
    try {
      final res = await ref.read(gameRepositoryProvider).dmTurn(
            campaignId: _campaignId,
            playerMessage: text,
            selectedOptionId: selectedOptionId,
          );
      await _refreshAfterTurn();
      _applyDmTurnResult(res);
    } catch (e) {
      state = AsyncValue.data((state.value ?? cur).copyWith(uiMode: GameUiMode.idle, error: e.toString()));
    }
  }

  Future<void> tapOption(ChatOption option) async {
    if (option.kind == 'template_common') {
      await _cheapResolve(option);
    } else {
      await submitPlayerMessage(option.label, selectedOptionId: option.id);
    }
  }

  Future<void> _cheapResolve(ChatOption option) async {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncValue.data(cur.copyWith(uiMode: GameUiMode.submitting, clearError: true));
    try {
      await ref.read(gameRepositoryProvider).cheapResolve(
            campaignId: _campaignId,
            optionId: option.id,
          );
      await _refreshAfterTurn();
    } catch (e) {
      state = AsyncValue.data((state.value ?? cur).copyWith(uiMode: GameUiMode.idle, error: e.toString()));
    }
  }

  Future<void> resolvePendingRoll() async {
    final cur = state.value;
    if (cur == null || cur.pendingRollId == null) return;
    state = AsyncValue.data(cur.copyWith(uiMode: GameUiMode.resolvingRoll));
    try {
      final res = await ref.read(gameRepositoryProvider).resolveRoll(pendingRollId: cur.pendingRollId!);
      await _refreshAfterTurn();
      state = AsyncValue.data((state.value ?? cur).copyWith(
        uiMode: res.characterDied ? GameUiMode.gameOver : GameUiMode.idle,
        clearPendingRoll: true,
        clearRequiresRoll: true,
        lastRollResult: res,
      ));
    } catch (e) {
      state = AsyncValue.data((state.value ?? cur).copyWith(uiMode: GameUiMode.idle, error: e.toString()));
    }
  }

  Future<void> submitCombatAction(Map<String, dynamic> action) async {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncValue.data(cur.copyWith(uiMode: GameUiMode.combatSubmitting, clearError: true));
    try {
      final res = await ref.read(gameRepositoryProvider).combatAction(
            campaignId: _campaignId,
            action: action,
          );
      await _refreshAfterTurn();
      final next = state.value ?? cur;
      if (res.kind == 'player_defeated') {
        state = AsyncValue.data(next.copyWith(uiMode: GameUiMode.gameOver, combat: res));
      } else if (res.kind == 'victory' || res.kind == 'fled') {
        state = AsyncValue.data(next.copyWith(uiMode: GameUiMode.idle, clearCombat: true));
      } else {
        state = AsyncValue.data(next.copyWith(uiMode: GameUiMode.inCombat, combat: res));
      }
    } catch (e) {
      state = AsyncValue.data((state.value ?? cur).copyWith(uiMode: GameUiMode.inCombat, error: e.toString()));
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
    final campaign = allCampaigns.firstWhere((c) => c.id == _campaignId, orElse: () => cur.campaign);

    state = AsyncValue.data(cur.copyWith(
      campaign: campaign,
      character: results[0] as CampaignCharacter,
      inventory: results[1] as List<InventoryItem>,
      bosses: results[2] as List<CampaignBoss>,
      sideMissions: results[3] as List<CampaignSideMission>,
      messages: results[4] as List<GameMessage>,
      skillIds: results[5] as List<String>,
      uiMode: campaign.status == 'active' ? GameUiMode.idle : GameUiMode.gameOver,
    ));
  }

  void _applyDmTurnResult(DmTurnResult res) {
    final cur = state.value;
    if (cur == null) return;
    if (res.kind == 'requires_roll' && res.requiresRoll != null && res.pendingRollId != null) {
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
}

final gameNotifierProvider = AsyncNotifierProvider<GameNotifier, GameState>(GameNotifier.new);
