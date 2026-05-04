/// Chat-bubble messages, options, dice prompts, and turn-result types returned by the
/// Edge Functions.

class GameMessage {
  GameMessage({
    required this.id,
    required this.campaignId,
    required this.role,
    required this.content,
    required this.situationType,
    required this.options,
    required this.requiresRoll,
    required this.wasCheapResolve,
    required this.pivotalMoment,
    required this.createdAt,
  });

  final String id;
  final String campaignId;
  final String role; // 'player' | 'dm' | 'system'
  final String content;
  final String? situationType;
  final List<ChatOption> options;
  final RequiresRoll? requiresRoll;
  final bool wasCheapResolve;
  final bool pivotalMoment;
  final DateTime createdAt;

  factory GameMessage.fromJson(Map<String, dynamic> json) {
    final opts = (json['options'] as List<dynamic>? ?? const [])
        .map((e) => ChatOption.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final rr = json['requires_roll'] as Map<String, dynamic>?;
    return GameMessage(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      situationType: json['situation_type'] as String?,
      options: opts,
      requiresRoll: rr == null ? null : RequiresRoll.fromJson(rr),
      wasCheapResolve: json['was_cheap_resolve'] as bool? ?? false,
      pivotalMoment: json['pivotal_moment'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ChatOption {
  ChatOption({
    required this.id,
    required this.label,
    required this.kind,
    required this.icon,
  });

  final String id;
  final String label;
  final String kind;   // 'template_common' | 'situational' | 'pivotal'
  final String icon;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind,
        'icon': icon,
      };

  factory ChatOption.fromJson(Map<String, dynamic> json) => ChatOption(
        id: json['id'] as String,
        label: json['label'] as String,
        kind: json['kind'] as String,
        icon: json['icon'] as String? ?? 'sparkle',
      );
}

class RequiresRoll {
  RequiresRoll({
    required this.dice,
    required this.purpose,
    required this.dc,
    required this.modifierStat,
  });

  final String dice; // 'd20' | 'd6' | 'd100'
  final String purpose;
  final int dc;
  final String? modifierStat;

  factory RequiresRoll.fromJson(Map<String, dynamic> json) => RequiresRoll(
        dice: json['dice'] as String,
        purpose: json['purpose'] as String,
        dc: (json['dc'] as num).toInt(),
        modifierStat: json['modifier_stat'] as String?,
      );
}

/// Result of a `dmTurn` request — either narration or a roll request.
class DmTurnResult {
  DmTurnResult({
    required this.kind,
    required this.narration,
    required this.options,
    required this.requiresRoll,
    required this.pendingRollId,
    required this.pivotalMoment,
    required this.newPhase,
    required this.sideMissionStarted,
    required this.leveledUpTo,
    required this.characterDied,
    required this.campaignStatus,
  });

  final String kind; // 'narration' | 'requires_roll'
  final String narration;
  final List<ChatOption> options;
  final RequiresRoll? requiresRoll;
  final String? pendingRollId;
  final bool pivotalMoment;
  final String? newPhase;
  final SideMissionToast? sideMissionStarted;
  final int? leveledUpTo;
  final bool characterDied;
  final String? campaignStatus;

  factory DmTurnResult.fromJson(Map<String, dynamic> json) {
    final opts = (json['options'] as List<dynamic>? ?? const [])
        .map((e) => ChatOption.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final rr = json['requires_roll'] as Map<String, dynamic>?;
    final sq = json['side_mission_started'] as Map<String, dynamic>?;
    return DmTurnResult(
      kind: json['kind'] as String? ?? 'narration',
      narration: json['narration'] as String,
      options: opts,
      requiresRoll: rr == null ? null : RequiresRoll.fromJson(rr),
      pendingRollId: json['pending_roll_id'] as String?,
      pivotalMoment: json['pivotal_moment'] as bool? ?? false,
      newPhase: json['new_phase'] as String?,
      sideMissionStarted: sq == null ? null : SideMissionToast.fromJson(sq),
      leveledUpTo: (json['leveled_up_to'] as num?)?.toInt(),
      characterDied: json['character_died'] as bool? ?? false,
      campaignStatus: json['campaign_status'] as String?,
    );
  }
}

class SideMissionToast {
  SideMissionToast({required this.id, required this.title});
  final String id;
  final String title;
  factory SideMissionToast.fromJson(Map<String, dynamic> j) =>
      SideMissionToast(id: j['id'] as String, title: j['title'] as String);
}

/// Result of a resolve-roll request.
class ResolveRollResult {
  ResolveRollResult({
    required this.dice,
    required this.raw,
    required this.modifier,
    required this.total,
    required this.dc,
    required this.outcome,
    required this.modifierStat,
    required this.narration,
    required this.options,
    required this.characterDied,
    required this.leveledUpTo,
    required this.newPhase,
    required this.campaignStatus,
  });

  final String dice;
  final int raw;
  final int modifier;
  final int total;
  final int dc;
  final String outcome; // 'critical_success' | 'success' | 'fail' | 'critical_fail'
  final String? modifierStat;
  final String narration;
  final List<ChatOption> options;
  final bool characterDied;
  final int? leveledUpTo;
  final String? newPhase;
  final String? campaignStatus;

  factory ResolveRollResult.fromJson(Map<String, dynamic> json) {
    final roll = json['roll'] as Map<String, dynamic>;
    final opts = (json['options'] as List<dynamic>? ?? const [])
        .map((e) => ChatOption.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return ResolveRollResult(
      dice: roll['dice'] as String,
      raw: (roll['raw'] as num).toInt(),
      modifier: (roll['modifier'] as num? ?? 0).toInt(),
      total: (roll['total'] as num).toInt(),
      dc: (roll['dc'] as num).toInt(),
      outcome: roll['outcome'] as String,
      modifierStat: roll['modifier_stat'] as String?,
      narration: json['narration'] as String,
      options: opts,
      characterDied: json['character_died'] as bool? ?? false,
      leveledUpTo: (json['leveled_up_to'] as num?)?.toInt(),
      newPhase: json['new_phase'] as String?,
      campaignStatus: json['campaign_status'] as String?,
    );
  }
}

/// Result of a cheap-resolve.
class CheapResolveResult {
  CheapResolveResult({required this.narration, required this.situationType});
  final String narration;
  final String situationType;

  factory CheapResolveResult.fromJson(Map<String, dynamic> j) => CheapResolveResult(
        narration: j['narration'] as String,
        situationType: j['situation_type'] as String? ?? 'exploration',
      );
}

/// Combat events returned by combat-action.
class CombatTurnResult {
  CombatTurnResult({
    required this.kind,
    required this.events,
    required this.encounterId,
    required this.roundNumber,
    required this.enemies,
    required this.character,
  });

  final String kind; // 'ongoing' | 'victory' | 'player_defeated' | 'fled'
  final List<CombatEvent> events;
  final String encounterId;
  final int? roundNumber;
  final List<EnemySummary> enemies;
  final CharSummary? character;

  factory CombatTurnResult.fromJson(Map<String, dynamic> json) {
    return CombatTurnResult(
      kind: json['kind'] as String,
      events: ((json['events'] as List<dynamic>?) ?? const [])
          .map((e) => CombatEvent.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      encounterId: json['encounter_id'] as String? ?? '',
      roundNumber: (json['round_number'] as num?)?.toInt(),
      enemies: ((json['enemies'] as List<dynamic>?) ?? const [])
          .map((e) => EnemySummary.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      character: json['character'] == null
          ? null
          : CharSummary.fromJson(json['character'] as Map<String, dynamic>),
    );
  }
}

class CombatEvent {
  CombatEvent({
    required this.kind,
    required this.narration,
    this.actor,
    this.damage,
    this.hit,
    this.critical,
    this.elementEffect,
    this.enemyId,
    this.hpAfter,
    this.playerHpAfter,
    this.resourceAfter,
    this.xpAwarded,
  });

  final String kind;
  final String narration;
  final String? actor;
  final int? damage;
  final bool? hit;
  final bool? critical;
  final String? elementEffect;
  final String? enemyId;
  final int? hpAfter;
  final int? playerHpAfter;
  final int? resourceAfter;
  final int? xpAwarded;

  factory CombatEvent.fromJson(Map<String, dynamic> j) => CombatEvent(
        kind: j['kind'] as String,
        narration: j['narration'] as String? ?? '',
        actor: j['actor'] as String?,
        damage: (j['damage'] as num?)?.toInt(),
        hit: j['hit'] as bool?,
        critical: j['critical'] as bool?,
        elementEffect: j['element_effect'] as String?,
        enemyId: j['enemy_id'] as String?,
        hpAfter: (j['hp_after'] as num?)?.toInt(),
        playerHpAfter: (j['player_hp_after'] as num?)?.toInt(),
        resourceAfter: (j['resource_after'] as num?)?.toInt(),
        xpAwarded: (j['xp_awarded'] as num?)?.toInt(),
      );
}

class EnemySummary {
  EnemySummary({
    required this.id,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.isBoss,
    required this.element,
  });

  final String id;
  final String name;
  final int hp;
  final int maxHp;
  final bool isBoss;
  final String element;

  factory EnemySummary.fromJson(Map<String, dynamic> j) => EnemySummary(
        id: j['id'] as String,
        name: j['name'] as String,
        hp: (j['hp'] as num).toInt(),
        maxHp: (j['max_hp'] as num).toInt(),
        isBoss: j['is_boss'] as bool? ?? false,
        element: j['element'] as String? ?? 'neutral',
      );
}

class CharSummary {
  CharSummary({
    required this.hp,
    required this.maxHp,
    required this.resourceCurrent,
    required this.resourceMax,
    required this.ac,
  });

  final int hp;
  final int maxHp;
  final int resourceCurrent;
  final int resourceMax;
  final int ac;

  factory CharSummary.fromJson(Map<String, dynamic> j) => CharSummary(
        hp: (j['hp'] as num).toInt(),
        maxHp: (j['max_hp'] as num).toInt(),
        resourceCurrent: (j['resource_current'] as num).toInt(),
        resourceMax: (j['resource_max'] as num).toInt(),
        ac: (j['ac'] as num).toInt(),
      );
}
