/// Server-seeded reference data, public-read for any authenticated user.

class ClassDefinition {
  ClassDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.baseElementDefault,
    required this.resourceType,
    required this.startingHp,
    required this.startingResource,
    required this.startingAc,
    required this.baseStats,
    required this.notes,
  });

  final String id;
  final String name;
  final String description;
  final String baseElementDefault;
  final String resourceType;
  final int startingHp;
  final int startingResource;
  final int startingAc;
  final Map<String, int> baseStats;
  final String notes;

  factory ClassDefinition.fromJson(Map<String, dynamic> json) {
    final stats = (json['base_stats'] as Map<String, dynamic>? ?? const {});
    return ClassDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      baseElementDefault: json['base_element_default'] as String,
      resourceType: json['resource_type'] as String,
      startingHp: (json['starting_hp'] as num).toInt(),
      startingResource: (json['starting_resource'] as num).toInt(),
      startingAc: (json['starting_ac'] as num? ?? 12).toInt(),
      baseStats: stats.map((k, v) => MapEntry(k, (v as num).toInt())),
      notes: json['notes'] as String? ?? '',
    );
  }
}

class AvatarTemplate {
  AvatarTemplate({
    required this.id,
    required this.displayName,
    required this.imageUrl,
    required this.classFilter,
    required this.sortOrder,
  });

  final String id;
  final String displayName;
  final String imageUrl;
  final List<String> classFilter;
  final int sortOrder;

  bool fitsClass(String classId) =>
      classFilter.isEmpty || classFilter.contains(classId);

  factory AvatarTemplate.fromJson(Map<String, dynamic> json) => AvatarTemplate(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        imageUrl: _resolveAvatarImageUrl(
          id: json['id'] as String,
          imageUrl: json['image_url'] as String,
        ),
        classFilter: ((json['class_filter'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
        sortOrder: (json['sort_order'] as num? ?? 0).toInt(),
      );
}

String _resolveAvatarImageUrl({required String id, required String imageUrl}) {
  if (imageUrl.startsWith('https://placehold.co/')) {
    return 'assets/images/avatars/$id.png';
  }
  return imageUrl;
}

class Skill {
  Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.element,
    required this.kind,
    required this.costType,
    required this.costAmount,
    required this.dice,
    required this.modifierStat,
    required this.availableToClasses,
    required this.requiredLevel,
    required this.isBasicAttack,
  });

  final String id;
  final String name;
  final String description;
  final String element;
  final String kind;
  final String costType;
  final int costAmount;
  final String? dice;
  final String? modifierStat;
  final List<String> availableToClasses;
  final int requiredLevel;
  final bool isBasicAttack;

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        element: json['element'] as String,
        kind: json['kind'] as String,
        costType: json['cost_type'] as String,
        costAmount: (json['cost_amount'] as num? ?? 0).toInt(),
        dice: json['dice'] as String?,
        modifierStat: json['modifier_stat'] as String?,
        availableToClasses:
            ((json['available_to_classes'] as List<dynamic>?) ?? const [])
                .map((e) => e as String)
                .toList(growable: false),
        requiredLevel: (json['required_level'] as num? ?? 1).toInt(),
        isBasicAttack: json['is_basic_attack'] as bool? ?? false,
      );
}

class StoryTemplate {
  StoryTemplate({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.genre,
    required this.worldSetting,
    required this.openingScene,
    required this.dmGuidance,
    required this.coverImageUrl,
  });

  final String id;
  final String title;
  final String shortDescription;
  final String genre;
  final String worldSetting;
  final String openingScene;
  final String dmGuidance;
  final String? coverImageUrl;

  factory StoryTemplate.fromJson(Map<String, dynamic> json) => StoryTemplate(
        id: json['id'] as String,
        title: json['title'] as String,
        shortDescription: json['short_description'] as String,
        genre: json['genre'] as String,
        worldSetting: json['world_setting'] as String,
        openingScene: json['opening_scene'] as String,
        dmGuidance: json['dm_guidance'] as String,
        coverImageUrl: json['cover_image_url'] as String?,
      );
}
