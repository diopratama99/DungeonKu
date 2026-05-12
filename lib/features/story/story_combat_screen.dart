// StoryCombatScreen — resolves an active combat_encounters row started by the
// story engine (on_enter_actions start_combat).
//
// Dice mechanism: every player action shows a d20 tumbling overlay while the
// server rolls server-side.  When the result arrives the face lands and the
// outcome label shows.  1.4 s later the overlay dismisses.
//
// Visual design: dark-dungeon backdrop, color-coded combat log (green = hit,
// gold = crit, red = enemy hit / defeat, grey = miss / info), element badges
// on enemies, round counter in the header.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/pixel_progress_bar.dart';
import 'package:dungeonku/core/widgets/pixel_spinner.dart';
import 'package:dungeonku/core/widgets/skill_icon.dart';
import 'package:dungeonku/data/models/messages.dart';
import 'package:dungeonku/data/repositories/game_repository.dart';
import 'package:dungeonku/data/supabase_providers.dart';

// ---------------------------------------------------------------------------
// Internal value types
// ---------------------------------------------------------------------------

class _EnemyState {
  _EnemyState({
    required this.id,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.isBoss,
    required this.element,
  });

  final String id;
  final String name;
  int hp;
  final int maxHp;
  final bool isBoss;
  final String element;
}

// Typed log line for color-coding the combat log.
enum _LogKind {
  info,
  playerHit,
  playerCrit,
  playerMiss,
  enemyHit,
  enemyCrit,
  enemyMiss,
  heal,
  outcome
}

class _LogLine {
  const _LogLine(this.text, [this.kind = _LogKind.info]);
  final String text;
  final _LogKind kind;

  Color get color => switch (kind) {
        _LogKind.playerHit => PixelColors.accentGreen,
        _LogKind.playerCrit => PixelColors.accentGold,
        _LogKind.playerMiss => PixelColors.textMuted,
        _LogKind.enemyHit => const Color(0xFFE88080),
        _LogKind.enemyCrit => PixelColors.accentRed,
        _LogKind.enemyMiss => PixelColors.textMuted,
        _LogKind.heal => const Color(0xFF80EEB0),
        _LogKind.outcome => PixelColors.accentGold,
        _LogKind.info => PixelColors.textMuted,
      };
}

// Dice overlay result data.
class _ActionResult {
  const _ActionResult({
    this.hit,
    this.critical,
    this.damage,
    this.isDefend = false,
    this.isFlee = false,
    this.fled = false,
    this.isHeal = false,
    this.healAmount,
  });

  final bool? hit;
  final bool? critical;
  final int? damage;
  final bool isDefend;
  final bool isFlee;
  final bool fled;
  final bool isHeal;
  final int? healAmount;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class StoryCombatScreen extends ConsumerStatefulWidget {
  const StoryCombatScreen({required this.campaignId, super.key});

  final String campaignId;

  @override
  ConsumerState<StoryCombatScreen> createState() => _StoryCombatScreenState();
}

class _StoryCombatScreenState extends ConsumerState<StoryCombatScreen> {
  List<_EnemyState> _enemies = [];
  int _playerHp = 0;
  int _playerMaxHp = 1;
  int _resourceCurrent = 0;
  int _resourceMax = 1;
  String _resourceType = 'mp';
  List<_LogLine> _log = [];
  List<Map<String, String>> _skills = [];

  bool _initialLoading = true;
  bool _actionBusy = false;
  String? _pendingActionLabel;
  _ActionResult? _actionResult;
  String? _outcome;
  String? _pendingOutcome;
  int _round = 0;

  final _logScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    try {
      final db = ref.read(dbProvider);

      final encounterRes = await db
          .from('combat_encounters')
          .select('id')
          .eq('campaign_id', widget.campaignId)
          .eq('status', 'active')
          .maybeSingle();

      if (encounterRes == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final encounterId = encounterRes['id'] as String;

      final enemiesData = await db
          .from('combat_enemies')
          .select('id, name, hp, max_hp, is_boss, element')
          .eq('encounter_id', encounterId);

      final charData = await db
          .from('campaign_characters')
          .select('hp, max_hp, resource_current, resource_max, resource_type')
          .eq('campaign_id', widget.campaignId)
          .single();

      final skillIdsData = await db
          .from('campaign_skills')
          .select('skill_id')
          .eq('campaign_id', widget.campaignId);

      final skillIds = (skillIdsData as List<dynamic>)
          .map((r) => (r as Map<String, dynamic>)['skill_id'] as String)
          .toList();

      List<Map<String, String>> skills = [];
      if (skillIds.isNotEmpty) {
        final skillRows = await db
            .from('skills')
            .select('id, name, element')
            .inFilter('id', skillIds);
        skills = (skillRows as List<dynamic>)
            .map((s) => {
                  'id': (s as Map<String, dynamic>)['id'] as String,
                  'name': s['name'] as String,
                  'element': (s['element'] as String?) ?? 'neutral',
                })
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _enemies = (enemiesData as List<dynamic>).map((e) {
          final m = e as Map<String, dynamic>;
          return _EnemyState(
            id: m['id'] as String,
            name: m['name'] as String,
            hp: (m['hp'] as num).toInt(),
            maxHp: (m['max_hp'] as num).toInt(),
            isBoss: (m['is_boss'] as bool?) ?? false,
            element: (m['element'] as String?) ?? 'neutral',
          );
        }).toList();
        _playerHp = (charData['hp'] as num).toInt();
        _playerMaxHp = (charData['max_hp'] as num).toInt();
        _resourceCurrent = (charData['resource_current'] as num).toInt();
        _resourceMax = (charData['resource_max'] as num).toInt();
        _resourceType = (charData['resource_type'] as String?) ?? 'mp';
        _skills = skills;
        _initialLoading = false;
        _log = [const _LogLine('⚔  Combat begins!', _LogKind.info)];
      });
      _scrollLogToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _log = [_LogLine('Error loading combat: $e', _LogKind.enemyCrit)];
        _initialLoading = false;
      });
    }
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.jumpTo(_logScrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _doAction(Map<String, dynamic> action,
      {required String label}) async {
    if (_actionBusy || _outcome != null) return;
    setState(() {
      _actionBusy = true;
      _pendingActionLabel = label;
      _actionResult = null;
    });

    try {
      final repo = ref.read(gameRepositoryProvider);
      final result = await repo.combatAction(
        campaignId: widget.campaignId,
        action: action,
      );
      if (!mounted) return;

      // Map result events → typed log lines.
      final newLines = <_LogLine>[];
      for (final e in result.events) {
        final isPlayer = e.actor == 'player';
        final prefix = e.critical == true ? '💥 CRIT — ' : '';
        _LogKind kind;
        if (e.kind == 'initiative_rolled') {
          kind = _LogKind.info;
        } else if (e.kind == 'victory' || e.kind == 'enemy_defeated') {
          kind = _LogKind.outcome;
        } else if (e.kind == 'player_defeated') {
          kind = _LogKind.enemyCrit;
        } else if (isPlayer) {
          final dmg = e.damage;
          if (dmg != null && dmg < 0) {
            kind = _LogKind.heal;
          } else if (e.critical == true) {
            kind = _LogKind.playerCrit;
          } else if (e.hit == true) {
            kind = _LogKind.playerHit;
          } else if (e.hit == false) {
            kind = _LogKind.playerMiss;
          } else {
            kind = _LogKind.info;
          }
        } else {
          if (e.critical == true) {
            kind = _LogKind.enemyCrit;
          } else if (e.hit == true) {
            kind = _LogKind.enemyHit;
          } else if (e.hit == false) {
            kind = _LogKind.enemyMiss;
          } else {
            kind = _LogKind.info;
          }
        }
        newLines.add(_LogLine('$prefix${e.narration}', kind));
      }

      // Build dice overlay result.
      _ActionResult actionRes;
      final kind = action['kind'] as String;
      if (kind == 'flee') {
        actionRes = _ActionResult(isFlee: true, fled: result.kind == 'fled');
      } else if (kind == 'defend') {
        actionRes = const _ActionResult(isDefend: true);
      } else {
        CombatEvent? playerEvent;
        for (final e in result.events) {
          if (e.actor == 'player') {
            playerEvent = e;
            break;
          }
        }
        final dmg = playerEvent?.damage;
        if (dmg != null && dmg < 0) {
          actionRes = _ActionResult(isHeal: true, healAmount: -dmg);
        } else {
          actionRes = _ActionResult(
            hit: playerEvent?.hit,
            critical: playerEvent?.critical,
            damage: dmg,
          );
        }
      }

      // Update enemies HP.
      for (final es in result.enemies) {
        for (final local in _enemies) {
          if (local.id == es.id) local.hp = es.hp;
        }
      }
      final char = result.character;
      if (char != null) {
        _playerHp = char.hp;
        _resourceCurrent = char.resourceCurrent;
      }

      String? outcomeMsg;
      _LogKind outcomeKind = _LogKind.outcome;
      if (result.kind == 'victory') {
        final xp = result.events
            .where((e) => e.xpAwarded != null)
            .fold(0, (s, e) => s + (e.xpAwarded ?? 0));
        outcomeMsg = xp > 0 ? '🏆  Victory! +$xp XP' : '🏆  Victory!';
      } else if (result.kind == 'player_defeated') {
        outcomeMsg = '💀  Defeated.';
        outcomeKind = _LogKind.enemyCrit;
      } else if (result.kind == 'fled') {
        outcomeMsg = '🏃  Escaped.';
      }

      setState(() {
        _log = [
          ..._log,
          ...newLines,
          if (outcomeMsg != null) _LogLine(outcomeMsg, outcomeKind),
        ];
        _actionResult = actionRes;
        _pendingOutcome = result.kind != 'ongoing' ? result.kind : null;
        if (result.roundNumber != null) _round = result.roundNumber!;
      });
      _scrollLogToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _log = [..._log, _LogLine('Error: $e', _LogKind.enemyCrit)];
        _actionBusy = false;
        _pendingActionLabel = null;
        _actionResult = null;
      });
      _scrollLogToBottom();
    }
  }

  void _onOverlayDismiss() {
    if (!mounted) return;
    final po = _pendingOutcome;
    setState(() {
      _actionBusy = false;
      _pendingActionLabel = null;
      _actionResult = null;
      _pendingOutcome = null;
      if (po != null) _outcome = po;
    });
    if (po != null) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final roundLabel = _round > 0 ? 'ROUND $_round' : 'COMBAT';

    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: SafeArea(
        child: Column(
          children: [
            _CombatAppBar(
              roundLabel: roundLabel,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // Background.
        const Positioned.fill(child: _CombatBackdrop()),
        // Main content.
        Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                children: [
                  _EnemySection(enemies: _enemies),
                  const _VsDivider(),
                  _PlayerSection(
                    hp: _playerHp,
                    maxHp: _playerMaxHp,
                    resource: _resourceCurrent,
                    maxResource: _resourceMax,
                    resourceType: _resourceType,
                  ),
                  const SizedBox(height: 10),
                  _CombatLog(lines: _log, scrollCtrl: _logScrollCtrl),
                ],
              ),
            ),
            if (_outcome == null)
              _ActionBar(
                busy: _actionBusy,
                skills: _skills,
                onAttack: () => _doAction({'kind': 'attack'}, label: 'ATTACK'),
                onDefend: () => _doAction({'kind': 'defend'}, label: 'DEFEND'),
                onFlee: () => _doAction({'kind': 'flee'}, label: 'FLEE'),
                onSkill: (id, name) => _doAction(
                    {'kind': 'skill', 'skill_id': id},
                    label: name.toUpperCase()),
              )
            else
              _OutcomeStrip(outcome: _outcome!),
          ],
        ),
        // Dice overlay.
        if (_actionBusy && _pendingActionLabel != null)
          Positioned.fill(
            child: _CombatDiceOverlay(
              actionLabel: _pendingActionLabel!,
              result: _actionResult,
              onDismiss: _onOverlayDismiss,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _CombatAppBar extends StatelessWidget {
  const _CombatAppBar({required this.roundLabel, required this.onBack});
  final String roundLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border:
            Border(bottom: BorderSide(color: PixelColors.accentRed, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: PixelColors.accentGold),
            onPressed: onBack,
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: Image.asset(
              'assets/images/logo/dungeonku_app-icon.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              roundLabel,
              style: AppTheme.pressStart(10, color: PixelColors.accentRed),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text('⚔',
                style: AppTheme.vt323(24, color: PixelColors.accentRed)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background
// ---------------------------------------------------------------------------

class _CombatBackdrop extends StatelessWidget {
  const _CombatBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.4,
          colors: [Color(0xFF1A1208), Color(0xFF0A0806)],
        ),
      ),
      child: Opacity(
        opacity: 0.15,
        child: CustomPaint(painter: _GridPainter()),
      ),
    );
  }
}

// Subtle pixel-grid texture for the dungeon floor feel.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PixelColors.accentGold
      ..strokeWidth = 0.5;
    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

// ---------------------------------------------------------------------------
// VS divider
// ---------------------------------------------------------------------------

class _VsDivider extends StatelessWidget {
  const _VsDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
              child: Container(
                  height: 1,
                  color: PixelColors.accentRed.withValues(alpha: 0.6))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('⚔',
                style: AppTheme.vt323(20, color: PixelColors.accentRed)),
          ),
          Expanded(
              child: Container(
                  height: 1,
                  color: PixelColors.accentBlue.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Enemy section
// ---------------------------------------------------------------------------

class _EnemySection extends StatelessWidget {
  const _EnemySection({required this.enemies});
  final List<_EnemyState> enemies;

  @override
  Widget build(BuildContext context) {
    return PixelPanel(
      borderColor: PixelColors.accentRed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: PixelColors.accentRed),
              const SizedBox(width: 8),
              Text('ENEMIES',
                  style: AppTheme.pressStart(9, color: PixelColors.accentRed)),
            ],
          ),
          const SizedBox(height: 10),
          for (final e in enemies) ...[
            _EnemyCard(enemy: e),
            if (e != enemies.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// Element → color mapping (shared between enemy card and other places).
const _kElementColors = <String, Color>{
  'fire': Color(0xFFE05A2B),
  'ice': Color(0xFF66C2E0),
  'lightning': Color(0xFFFFD43B),
  'earth': Color(0xFF8B6914),
  'light': Color(0xFFFFF0A0),
  'dark': Color(0xFF9B59B6),
  'neutral': PixelColors.textMuted,
};

class _EnemyCard extends StatelessWidget {
  const _EnemyCard({required this.enemy});
  final _EnemyState enemy;

  @override
  Widget build(BuildContext context) {
    final dead = enemy.hp <= 0;
    final ratio = enemy.maxHp > 0 ? enemy.hp / enemy.maxHp : 0.0;
    final elemColor = _kElementColors[enemy.element] ?? PixelColors.textMuted;
    final hpColor = dead
        ? PixelColors.borderSoft
        : ratio > 0.5
            ? PixelColors.hpBar
            : ratio > 0.2
                ? PixelColors.accentGold
                : PixelColors.accentRed;

    return Opacity(
      opacity: dead ? 0.4 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: PixelColors.panelInner,
          border: Border.all(
            color: dead
                ? PixelColors.borderSoft
                : elemColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (enemy.isBoss)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('★',
                        style:
                            AppTheme.vt323(18, color: PixelColors.accentGold)),
                  ),
                Expanded(
                  child: Text(
                    dead ? '${enemy.name}  [DEFEATED]' : enemy.name,
                    style: AppTheme.vt323(18,
                        color: dead
                            ? PixelColors.textMuted
                            : PixelColors.textOnInk),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: elemColor.withValues(alpha: 0.15),
                    border: Border.all(color: elemColor, width: 1),
                  ),
                  child: Text(
                    enemy.element.toUpperCase(),
                    style: AppTheme.pressStart(6, color: elemColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            PixelProgressBar(
              label: 'HP',
              current: enemy.hp.clamp(0, enemy.maxHp),
              max: enemy.maxHp,
              fillColor: hpColor,
              height: 8,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player section
// ---------------------------------------------------------------------------

class _PlayerSection extends StatelessWidget {
  const _PlayerSection({
    required this.hp,
    required this.maxHp,
    required this.resource,
    required this.maxResource,
    required this.resourceType,
  });

  final int hp;
  final int maxHp;
  final int resource;
  final int maxResource;
  final String resourceType;

  @override
  Widget build(BuildContext context) {
    final hpRatio = maxHp > 0 ? hp / maxHp : 0.0;
    final hpColor = hpRatio > 0.5
        ? PixelColors.hpBar
        : hpRatio > 0.2
            ? PixelColors.accentGold
            : PixelColors.accentRed;
    final resColor =
        resourceType == 'mp' ? PixelColors.mpBar : PixelColors.staminaBar;

    return PixelPanel(
      borderColor: PixelColors.accentBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: PixelColors.accentBlue),
              const SizedBox(width: 8),
              Text('YOU',
                  style: AppTheme.pressStart(9, color: PixelColors.accentBlue)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PixelProgressBar(
                  label: 'HP',
                  current: hp,
                  max: maxHp,
                  fillColor: hpColor,
                  height: 10,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PixelProgressBar(
                  label: resourceType.toUpperCase(),
                  current: resource,
                  max: maxResource,
                  fillColor: resColor,
                  height: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Combat log (scrollable, color-coded)
// ---------------------------------------------------------------------------

class _CombatLog extends StatelessWidget {
  const _CombatLog({required this.lines, required this.scrollCtrl});
  final List<_LogLine> lines;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: PixelColors.textMuted),
              const SizedBox(width: 8),
              Text('LOG',
                  style: AppTheme.pressStart(8, color: PixelColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.builder(
              controller: scrollCtrl,
              padding: EdgeInsets.zero,
              itemCount: lines.length,
              itemBuilder: (_, i) {
                final line = lines[i];
                // Newest lines are slightly brighter.
                final isRecent = i >= lines.length - 3;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (line.kind == _LogKind.playerCrit ||
                          line.kind == _LogKind.enemyCrit)
                        Padding(
                          padding: const EdgeInsets.only(right: 4, top: 2),
                          child: Container(
                            width: 4,
                            height: 12,
                            color: line.color,
                          ),
                        )
                      else
                        const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          line.text,
                          style: AppTheme.vt323(
                            15,
                            color: isRecent
                                ? line.color
                                : line.color.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.skills,
    required this.onAttack,
    required this.onDefend,
    required this.onFlee,
    required this.onSkill,
  });

  final bool busy;
  final List<Map<String, String>> skills;
  final VoidCallback onAttack;
  final VoidCallback onDefend;
  final VoidCallback onFlee;
  final void Function(String id, String name) onSkill;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final skillButtonWidth = math.min(220.0, math.max(154.0, (width - 26) / 2));

    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(top: BorderSide(color: PixelColors.accentRed, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _CombatBtn(
                  label: 'ATTACK',
                  color: PixelColors.accentRed,
                  onTap: busy ? null : onAttack),
              const SizedBox(width: 8),
              _CombatBtn(
                  label: 'DEFEND',
                  color: PixelColors.accentBlue,
                  onTap: busy ? null : onDefend),
              const SizedBox(width: 8),
              _CombatBtn(
                  label: 'FLEE',
                  color: PixelColors.textMuted,
                  onTap: busy ? null : onFlee),
            ],
          ),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in skills)
                  SizedBox(
                    width: skillButtonWidth,
                    height: 48,
                    child: _CombatBtn(
                      label: s['name']!.toUpperCase(),
                      color: PixelColors.accentGold,
                      expand: false,
                      iconSkillId: s['id'],
                      onTap: busy ? null : () => onSkill(s['id']!, s['name']!),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CombatBtn extends StatelessWidget {
  const _CombatBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.expand = true,
    this.iconSkillId,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool expand;
  final String? iconSkillId;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final content = InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: iconSkillId == null ? 8 : 6,
          vertical: iconSkillId == null ? 10 : 6,
        ),
        decoration: BoxDecoration(
          color:
              active ? color.withValues(alpha: 0.08) : PixelColors.panelInner,
          border: Border.all(
            color: active ? color : PixelColors.borderSoft,
            width: active ? 2 : 1,
          ),
        ),
        child: iconSkillId == null
            ? Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.pressStart(8,
                      color: active ? color : PixelColors.textMuted),
                ),
              )
            : Row(
                children: [
                  SkillIcon(
                    skillId: iconSkillId!,
                    size: 32,
                    borderColor: active ? color : PixelColors.borderSoft,
                    disabled: !active,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.left,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.pressStart(7,
                          color: active ? color : PixelColors.textMuted),
                    ),
                  ),
                ],
              ),
      ),
    );

    if (!expand) return content;
    return Expanded(child: content);
  }
}

// ---------------------------------------------------------------------------
// Outcome strip (victory / defeat / fled)
// ---------------------------------------------------------------------------

class _OutcomeStrip extends StatelessWidget {
  const _OutcomeStrip({required this.outcome});
  final String outcome;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (outcome) {
      'victory' => ('VICTORY — returning to story…', PixelColors.accentGreen),
      'player_defeated' => (
          'DEFEATED — returning to story…',
          PixelColors.accentRed
        ),
      'fled' => ('FLED — returning to story…', PixelColors.accentGold),
      _ => ('RETURNING…', PixelColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(top: BorderSide(color: color, width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PixelSpinner(size: 12),
          const SizedBox(width: 10),
          Text(label,
              style: AppTheme.pressStart(9, color: color),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dice overlay
// ---------------------------------------------------------------------------

class _CombatDiceOverlay extends StatefulWidget {
  const _CombatDiceOverlay({
    required this.actionLabel,
    required this.result,
    required this.onDismiss,
  });

  final String actionLabel;
  final _ActionResult? result;
  final VoidCallback onDismiss;

  @override
  State<_CombatDiceOverlay> createState() => _CombatDiceOverlayState();
}

class _CombatDiceOverlayState extends State<_CombatDiceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;
  final _rng = math.Random();
  Timer? _faceTimer;
  int _face = 1;
  int? _landedFace;
  bool _resultShowing = false;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();

    _faceTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (_resultShowing || !mounted) return;
      setState(() => _face = _rng.nextInt(20) + 1);
    });
  }

  @override
  void didUpdateWidget(_CombatDiceOverlay old) {
    super.didUpdateWidget(old);
    if (widget.result != null && old.result == null && !_resultShowing) {
      _faceTimer?.cancel();
      _rotCtrl.stop();
      _landedFace = _computeFace(widget.result!);
      setState(() => _resultShowing = true);
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) widget.onDismiss();
      });
    }
  }

  @override
  void dispose() {
    _faceTimer?.cancel();
    _rotCtrl.dispose();
    super.dispose();
  }

  int _computeFace(_ActionResult r) {
    if (r.isFlee) return r.fled ? 16 : 5;
    if (r.isDefend) return 14;
    if (r.isHeal) return 18;
    if (r.critical == true) return 20;
    if (r.hit == true) return _rng.nextInt(9) + 10;
    return _rng.nextInt(7) + 2;
  }

  @override
  Widget build(BuildContext context) {
    final face = _landedFace ?? _face;

    return Container(
      color: Colors.black.withValues(alpha: 0.86),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Action label with decorative line.
                Row(
                  children: [
                    const Expanded(
                        child: Divider(color: PixelColors.accentRed)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        widget.actionLabel,
                        style: AppTheme.pressStart(12,
                            color: PixelColors.accentGold),
                      ),
                    ),
                    const Expanded(
                        child: Divider(color: PixelColors.accentRed)),
                  ],
                ),
                const SizedBox(height: 28),
                // D20 face.
                AnimatedBuilder(
                  animation: _rotCtrl,
                  builder: (_, __) => Transform.rotate(
                    angle: _resultShowing ? 0 : _rotCtrl.value * math.pi * 2,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: PixelColors.parchment,
                        border:
                            Border.all(color: PixelColors.accentGold, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color:
                                PixelColors.accentGold.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                          const BoxShadow(
                            color: PixelColors.borderOuter,
                            offset: Offset(5, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          face.toString(),
                          style: AppTheme.pressStart(30,
                              color: PixelColors.textOnParchment),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (_resultShowing && widget.result != null)
                  _OverlayResultText(result: widget.result!)
                else ...[
                  const PixelSpinner(size: 14),
                  const SizedBox(height: 8),
                  Text('rolling d20…',
                      style: AppTheme.vt323(20, color: PixelColors.textMuted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayResultText extends StatelessWidget {
  const _OverlayResultText({required this.result});
  final _ActionResult result;

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    String? sub;

    if (result.isFlee) {
      label = result.fled ? 'ESCAPED!' : 'BLOCKED!';
      color = result.fled ? PixelColors.accentGold : PixelColors.accentRed;
    } else if (result.isDefend) {
      label = 'STANCE SET';
      color = PixelColors.accentBlue;
      sub = '+2 AC this round';
    } else if (result.isHeal) {
      label = 'HEALED!';
      color = const Color(0xFF80EEB0);
      if (result.healAmount != null) sub = '+${result.healAmount} HP';
    } else if (result.critical == true) {
      label = 'CRITICAL HIT!';
      color = PixelColors.accentGold;
      if (result.damage != null) sub = '${result.damage} DMG';
    } else if (result.hit == true) {
      label = 'HIT!';
      color = PixelColors.accentGreen;
      if (result.damage != null) sub = '${result.damage} DMG';
    } else {
      label = 'MISS!';
      color = PixelColors.accentRed;
    }

    return Column(
      children: [
        Text(label, style: AppTheme.pressStart(17, color: color)),
        if (sub != null) ...[
          const SizedBox(height: 8),
          Text(sub, style: AppTheme.vt323(26, color: color)),
        ],
      ],
    );
  }
}
