/// Models for the story-graph engine introduced by migration
/// `20260511000000_story_node_graph.sql`. The shape mirrors the
/// `RenderedNodePayload` returned by the Edge functions
/// `/story-turn` and `/player-action`.
///
/// These are NOT loaded directly from the `story_nodes` / `story_edges`
/// tables — the client only ever sees what the server has rendered for
/// the current campaign cursor (already gated by requires, optionally
/// reskinned by AI roles in later phases).

class StoryOption {
  StoryOption({
    required this.id,
    required this.label,
    required this.locked,
    this.lockReason,
  });

  /// `story_edges.option_id`. Pass back to `/player-action` to take
  /// this option.
  final String id;

  /// Visible button text.
  final String label;

  /// True when the gating predicate on the underlying edge failed.
  /// Locked options are only shown when the current node carries the
  /// `show_locked` tag — otherwise the server filters them out and the
  /// client never sees them.
  final bool locked;

  /// Compact one-line hint about why this option is locked
  /// (e.g. `"class: warrior or blacksmith"`, `"STR >=14"`,
  /// `"needs: orphan_friend"`). Server-generated.
  final String? lockReason;

  factory StoryOption.fromJson(Map<String, dynamic> json) => StoryOption(
        id: json['id'] as String,
        label: json['label'] as String,
        locked: (json['locked'] as bool?) ?? false,
        lockReason: json['lock_reason'] as String?,
      );
}

/// One render of the campaign's current node.
///
/// Re-fetching `/story-turn` for the same cursor is idempotent — the
/// server only fires `on_enter_actions` once per node visit (unless
/// the node carries the `replayable_actions` tag).
class StoryNodePayload {
  StoryNodePayload({
    required this.nodeId,
    required this.nodeType,
    required this.body,
    required this.tags,
    required this.options,
    this.speaker,
    this.wasFirstVisit = false,
    this.pendingCombatId,
    this.endedCampaign,
    this.aiRoleUsed,
  });

  /// `story_nodes.id`, e.g. `"ember_outpost__intro"`.
  final String nodeId;

  /// One of: `scene`, `dialog`, `choice`, `combat`, `outcome`, `transition`.
  /// UI uses this to decide presentation (dialog renders speaker, combat
  /// routes to the existing CombatScreen, outcome shows an end-of-run
  /// celebration, etc.).
  final String nodeType;

  /// Body prose. In Phase 1 this is the dry text from the DB. In Phase 2
  /// the server will optionally rewrite this via AI Role A (Reskinner)
  /// for nodes tagged `pivotal` (depending on the user's
  /// `profiles.ai_role_reskinner_enabled` toggle).
  final String body;

  /// For dialog nodes: the NPC who is speaking. Null otherwise.
  final String? speaker;

  /// Author tags. UI may special-case e.g. `["pivotal"]` → highlight,
  /// `["ending"]` → epilogue card style, `["combat"]` → red border.
  final List<String> tags;

  /// Outgoing options the player can take.
  final List<StoryOption> options;

  /// True iff this was the first time the campaign reached this node.
  /// `on_enter_actions` only fired this turn if either this is true or
  /// the node has the `replayable_actions` tag.
  final bool wasFirstVisit;

  /// Set when an `on_enter_actions` `start_combat` fired. The client
  /// should route to the existing CombatScreen using the existing
  /// combat-action endpoint, then come back here when combat resolves.
  final String? pendingCombatId;

  /// Set when an `on_enter_actions` `end_campaign` fired. Client should
  /// navigate to a Game Over / Game Won screen instead of accepting
  /// further options.
  final EndedCampaign? endedCampaign;

  /// Phase 2: which AI role rewrote `body`, if any.
  /// One of `'reskinner'`, `'npc_voice'`, or null. The UI may render a
  /// tiny badge so the player knows this paragraph wasn't authored verbatim.
  final String? aiRoleUsed;

  factory StoryNodePayload.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>? ?? const [])
        .map((e) => StoryOption.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final ended = json['ended_campaign'] as Map<String, dynamic>?;
    return StoryNodePayload(
      nodeId: json['node_id'] as String,
      nodeType: json['node_type'] as String,
      body: (json['body'] as String?) ?? '',
      speaker: json['speaker'] as String?,
      tags: ((json['tags'] as List<dynamic>?) ?? const [])
          .map((e) => e as String)
          .toList(growable: false),
      options: options,
      wasFirstVisit: (json['was_first_visit'] as bool?) ?? false,
      pendingCombatId: json['pending_combat_id'] as String?,
      endedCampaign: ended == null ? null : EndedCampaign.fromJson(ended),
      aiRoleUsed: json['ai_role_used'] as String?,
    );
  }

  bool get isPivotal => tags.contains('pivotal');
  bool get isEnding => tags.contains('ending');
  bool get isCombat => nodeType == 'combat';
  bool get isDialog => nodeType == 'dialog';
}

class EndedCampaign {
  EndedCampaign({required this.outcome, required this.summarySeed});

  /// `'success'` or `'failure'`. Maps onto the existing campaigns.status
  /// (`completed` / `failed`) but kept narrative-friendly here.
  final String outcome;

  /// Short authored sentence that the optional Role-E session
  /// summarizer (later phase) can use as a seed.
  final String summarySeed;

  factory EndedCampaign.fromJson(Map<String, dynamic> json) => EndedCampaign(
        outcome: json['outcome'] as String,
        summarySeed: (json['summary_seed'] as String?) ?? '',
      );
}
