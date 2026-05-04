/// Profile-level character (lives across campaigns) and the per-campaign snapshot
/// (HP/MP/level/XP/stats — these mutate during a campaign and don't bleed across runs).

class Character {
  Character({
    required this.id,
    required this.userId,
    required this.name,
    required this.classId,
    required this.baseElement,
    required this.avatarId,
    required this.stats,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String name;
  final String classId;
  final String baseElement;
  final String avatarId;
  final Map<String, int> stats;
  final DateTime createdAt;

  factory Character.fromJson(Map<String, dynamic> json) {
    final raw = (json['stats'] as Map<String, dynamic>? ?? const {});
    return Character(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      classId: json['class'] as String,
      baseElement: json['base_element'] as String,
      avatarId: json['avatar_id'] as String,
      stats: raw.map((k, v) => MapEntry(k, (v as num).toInt())),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class StatusEffect {
  StatusEffect({
    required this.key,
    required this.label,
    required this.expiresInTurns,
    required this.magnitude,
  });

  final String key;
  final String label;
  final int expiresInTurns;
  final int magnitude;

  factory StatusEffect.fromJson(Map<String, dynamic> json) => StatusEffect(
        key: json['key'] as String,
        label: json['label'] as String,
        expiresInTurns: (json['expires_in_turns'] as num?)?.toInt() ?? 0,
        magnitude: (json['magnitude'] as num?)?.toInt() ?? 0,
      );
}

class CampaignCharacter {
  CampaignCharacter({
    required this.id,
    required this.campaignId,
    required this.characterId,
    required this.level,
    required this.xp,
    required this.hp,
    required this.maxHp,
    required this.resourceType,
    required this.resourceCurrent,
    required this.resourceMax,
    required this.ac,
    required this.currentStats,
    required this.statusEffects,
    required this.baseElement,
  });

  final String id;
  final String campaignId;
  final String characterId;
  final int level;
  final int xp;
  final int hp;
  final int maxHp;
  final String resourceType; // 'mp' | 'stamina'
  final int resourceCurrent;
  final int resourceMax;
  final int ac;
  final Map<String, int> currentStats;
  final List<StatusEffect> statusEffects;
  final String baseElement;

  factory CampaignCharacter.fromJson(Map<String, dynamic> json) {
    final stats = (json['current_stats'] as Map<String, dynamic>? ?? const {});
    final effects = (json['status_effects'] as List<dynamic>? ?? const [])
        .map((e) => StatusEffect.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return CampaignCharacter(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      characterId: json['character_id'] as String,
      level: (json['level'] as num).toInt(),
      xp: (json['xp'] as num).toInt(),
      hp: (json['hp'] as num).toInt(),
      maxHp: (json['max_hp'] as num).toInt(),
      resourceType: json['resource_type'] as String,
      resourceCurrent: (json['resource_current'] as num).toInt(),
      resourceMax: (json['resource_max'] as num).toInt(),
      ac: (json['ac'] as num).toInt(),
      currentStats: stats.map((k, v) => MapEntry(k, (v as num).toInt())),
      statusEffects: effects,
      baseElement: json['base_element'] as String,
    );
  }
}
