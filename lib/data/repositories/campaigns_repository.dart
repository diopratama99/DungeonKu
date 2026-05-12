import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/data/models/campaign.dart';
import 'package:dungeonku/data/models/character.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/data/supabase_providers.dart';

class CampaignsRepository {
  CampaignsRepository(this._sb);
  final SupabaseQuerySchema _sb;

  Future<List<Campaign>> list(String userId) async {
    final rows = await _sb
        .from('campaigns')
        .select()
        .eq('user_id', userId)
        .order('last_played_at', ascending: false);
    return (rows as List<dynamic>)
        .map((r) => Campaign.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Create a new campaign + populate the per-campaign character snapshot, copy starting
  /// skills, and seed campaign_bosses from the chosen story template. We do this client-side
  /// to keep the flow simple; a stored procedure could replace this for atomicity.
  Future<Campaign> create({
    required String userId,
    required String characterId,
    required String templateId,
    required String name,
  }) async {
    // Look up the character so we know its class + chosen avatar for
    // the snapshot. avatar_id is needed so we can grant the avatar's
    // signature skill at campaign start (see below).
    final charRow = await _sb
        .from('characters')
        .select('id, class, base_element, stats, avatar_id')
        .eq('id', characterId)
        .single();
    final classId = charRow['class'] as String;
    final baseElement = charRow['base_element'] as String;
    final stats = (charRow['stats'] as Map<String, dynamic>);
    final avatarId = charRow['avatar_id'] as String?;

    // Look up the class definition for HP/resource defaults.
    final classRow = await _sb
        .from('class_definitions')
        .select(
            'starting_hp, resource_type, starting_resource, starting_ac, starting_skills')
        .eq('id', classId)
        .single();

    // Resolve the avatar's signature skill (one bonus skill, narratively
    // bound to the chosen portrait — see migration
    // 20260510000000_avatar_lore_and_signature_skills). Tolerate missing
    // wiring (legacy characters, partial DB state) by treating absence
    // as "no signature skill" instead of failing campaign creation.
    String? signatureSkillId;
    if (avatarId != null) {
      final avatarRow = await _sb
          .from('avatar_templates')
          .select('signature_skill_id')
          .eq('id', avatarId)
          .maybeSingle();
      signatureSkillId = avatarRow?['signature_skill_id'] as String?;
    }

    // Insert the campaign row.
    final campaignInserted = await _sb
        .from('campaigns')
        .insert({
          'user_id': userId,
          'character_id': characterId,
          'template_id': templateId,
          'name': name,
        })
        .select()
        .single();
    final campaign = Campaign.fromJson(campaignInserted);

    // Per-campaign character snapshot.
    await _sb.from('campaign_characters').insert({
      'campaign_id': campaign.id,
      'character_id': characterId,
      'level': 1,
      'xp': 0,
      'hp': classRow['starting_hp'],
      'max_hp': classRow['starting_hp'],
      'resource_type': classRow['resource_type'],
      'resource_current': classRow['starting_resource'],
      'resource_max': classRow['starting_resource'],
      'ac': classRow['starting_ac'],
      'current_stats': stats,
      'status_effects': <Map<String, dynamic>>[],
      'base_element': baseElement,
    });

    // Starting skills = class defaults + avatar signature.
    //
    // Class skills come from class_definitions.starting_skills (a json
    // array of skill ids). We then prepend the chosen avatar's signature
    // skill so the player has access to their portrait's unique ability
    // from turn 1. De-dupe in case both lists ever overlap.
    final classSkills =
        ((classRow['starting_skills'] as List<dynamic>?) ?? const [])
            .map((s) => s as String);
    final allSkillIds = <String>{
      if (signatureSkillId != null) signatureSkillId,
      ...classSkills,
    };
    if (allSkillIds.isNotEmpty) {
      await _sb.from('campaign_skills').insert([
        for (final skillId in allSkillIds)
          {
            'campaign_id': campaign.id,
            'skill_id': skillId,
            'learned_at_turn': 0,
          },
      ]);
    }

    // Seed boss progression.
    final bossRows = await _sb
        .from('template_bosses')
        .select('id')
        .eq('template_id', templateId);
    if ((bossRows as List<dynamic>).isNotEmpty) {
      await _sb.from('campaign_bosses').insert([
        for (final b in bossRows)
          {
            'campaign_id': campaign.id,
            'template_boss_id': b['id'] as String,
            'status': 'unencountered',
          },
      ]);
    }

    // Seed the opening DM message from the template.
    final tmpl = await _sb
        .from('story_templates')
        .select('opening_scene')
        .eq('id', templateId)
        .single();
    await _sb.from('messages').insert({
      'campaign_id': campaign.id,
      'role': 'dm',
      'content': tmpl['opening_scene'] as String,
      'situation_type': 'transition',
      'options': [
        {
          'id': 'tc_look',
          'label': 'Look around',
          'kind': 'template_common',
          'icon': 'eye'
        },
        {
          'id': 'tc_search',
          'label': 'Search for clues',
          'kind': 'template_common',
          'icon': 'magnify'
        },
        {
          'id': 'tc_move',
          'label': 'Move on',
          'kind': 'template_common',
          'icon': 'footstep'
        },
      ],
      'was_cheap_resolve': false,
    });

    return campaign;
  }

  Future<void> rename(String campaignId, String name) async {
    await _sb.from('campaigns').update({'name': name}).eq('id', campaignId);
  }

  Future<void> delete(String campaignId) async {
    await _sb.from('campaigns').delete().eq('id', campaignId);
  }

  // --------------------- Per-campaign reads ---------------------

  Future<CampaignCharacter> loadCampaignCharacter(String campaignId) async {
    final row = await _sb
        .from('campaign_characters')
        .select()
        .eq('campaign_id', campaignId)
        .single();
    return CampaignCharacter.fromJson(row);
  }

  Future<List<InventoryItem>> loadInventory(String campaignId) async {
    final rows = await _sb
        .from('campaign_inventory')
        .select()
        .eq('campaign_id', campaignId);
    return (rows as List<dynamic>)
        .map((r) => InventoryItem.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<CampaignBoss>> loadBosses(String campaignId) async {
    final rows = await _sb
        .from('campaign_bosses')
        .select('*, template_bosses(name, tier)')
        .eq('campaign_id', campaignId);
    return (rows as List<dynamic>)
        .map((r) => CampaignBoss.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<CampaignSideMission>> loadSideMissions(String campaignId) async {
    final rows = await _sb
        .from('campaign_side_missions')
        .select('*, template_side_missions(title)')
        .eq('campaign_id', campaignId);
    return (rows as List<dynamic>)
        .map((r) => CampaignSideMission.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<GameMessage>> loadMessages(String campaignId,
      {int limit = 50}) async {
    // We query DESC so `LIMIT n` keeps the NEWEST n messages (the relevant
    // tail of a long campaign), then reverse client-side so the chat UI
    // gets them in chronological order (oldest first, newest last).
    //
    // (postgrest-dart\u2019s `.order()` defaults `ascending: false`, opposite of
    // supabase-js. The previous code returned newest-first to the UI by
    // accident, which is what made the chat appear inverted.)
    final rows = await _sb
        .from('messages')
        .select()
        .eq('campaign_id', campaignId)
        .order('created_at', ascending: false)
        .limit(limit);
    final list = (rows as List<dynamic>)
        .map((r) => GameMessage.fromJson(r as Map<String, dynamic>))
        .toList();
    return list.reversed.toList(growable: false);
  }

  Future<List<String>> loadLearnedSkillIds(String campaignId) async {
    final rows = await _sb
        .from('campaign_skills')
        .select('skill_id')
        .eq('campaign_id', campaignId);
    return (rows as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['skill_id'] as String)
        .toList(growable: false);
  }
}

final campaignsRepositoryProvider = Provider<CampaignsRepository>((ref) {
  return CampaignsRepository(ref.watch(dbProvider));
});

final campaignsListProvider = FutureProvider<List<Campaign>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(campaignsRepositoryProvider).list(user.id);
});
