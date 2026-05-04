/// Campaign + sub-tables (boss progression, side missions, inventory).

class Campaign {
  Campaign({
    required this.id,
    required this.userId,
    required this.characterId,
    required this.templateId,
    required this.name,
    required this.status,
    required this.phase,
    required this.turnsInCurrentPhase,
    required this.turnsSinceLastProgress,
    required this.totalTurns,
    required this.lastPlayedAt,
  });

  final String id;
  final String userId;
  final String characterId;
  final String templateId;
  final String name;
  final String status; // 'active' | 'completed' | 'failed'
  final String phase;  // 'intro' | 'rising' | 'climax' | 'resolution'
  final int turnsInCurrentPhase;
  final int turnsSinceLastProgress;
  final int totalTurns;
  final DateTime lastPlayedAt;

  factory Campaign.fromJson(Map<String, dynamic> json) => Campaign(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        characterId: json['character_id'] as String,
        templateId: json['template_id'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
        phase: json['phase'] as String,
        turnsInCurrentPhase: (json['turns_in_current_phase'] as num? ?? 0).toInt(),
        turnsSinceLastProgress: (json['turns_since_last_progress'] as num? ?? 0).toInt(),
        totalTurns: (json['total_turns'] as num? ?? 0).toInt(),
        lastPlayedAt: DateTime.parse(json['last_played_at'] as String),
      );
}

class CampaignBoss {
  CampaignBoss({
    required this.id,
    required this.campaignId,
    required this.templateBossId,
    required this.name,
    required this.tier,
    required this.status,
  });

  final String id;
  final String campaignId;
  final String templateBossId;
  final String name;
  final String tier;
  final String status;

  factory CampaignBoss.fromJson(Map<String, dynamic> json) {
    final tpl = json['template_bosses'] as Map<String, dynamic>?;
    return CampaignBoss(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      templateBossId: json['template_boss_id'] as String,
      name: tpl?['name'] as String? ?? 'Unknown',
      tier: tpl?['tier'] as String? ?? 'small',
      status: json['status'] as String,
    );
  }
}

class CampaignSideMission {
  CampaignSideMission({
    required this.id,
    required this.campaignId,
    required this.templateSideMissionId,
    required this.title,
    required this.status,
    required this.currentStep,
  });

  final String id;
  final String campaignId;
  final String templateSideMissionId;
  final String title;
  final String status;
  final int currentStep;

  factory CampaignSideMission.fromJson(Map<String, dynamic> json) {
    final tpl = json['template_side_missions'] as Map<String, dynamic>?;
    return CampaignSideMission(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      templateSideMissionId: json['template_side_mission_id'] as String,
      title: tpl?['title'] as String? ?? 'Side mission',
      status: json['status'] as String,
      currentStep: (json['current_step'] as num? ?? 0).toInt(),
    );
  }
}

class InventoryItem {
  InventoryItem({
    required this.id,
    required this.name,
    required this.qty,
    required this.description,
    required this.element,
    required this.itemType,
  });

  final String id;
  final String name;
  final int qty;
  final String description;
  final String element;
  final String itemType;

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id: json['id'] as String,
        name: json['name'] as String,
        qty: (json['qty'] as num).toInt(),
        description: json['description'] as String? ?? '',
        element: json['element'] as String? ?? 'neutral',
        itemType: json['item_type'] as String,
      );
}
