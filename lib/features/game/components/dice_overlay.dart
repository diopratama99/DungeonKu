import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/data/models/messages.dart';

/// Modal dice overlay. Player taps the prompt → calls [onTapDice] which kicks off
/// `resolve-roll`. We tumble locally for a fixed minimum dramatic time. When [result] is
/// non-null we land on its raw face and show the outcome briefly before [onDone].
class DiceOverlay extends StatefulWidget {
  const DiceOverlay({
    required this.requiresRoll,
    required this.result,
    required this.onDone,
    this.onTapDice,
    this.autoStart = false,
    super.key,
  });

  final RequiresRoll requiresRoll;
  final ResolveRollResult? result;

  /// Called when the user manually taps the in-overlay roll button.
  /// Optional because in the current UX the player triggers the roll from the
  /// action panel before the overlay even appears — [autoStart] is then
  /// used so the overlay tumbles immediately on mount.
  final VoidCallback? onTapDice;

  /// Called once the result has landed and the celebratory hold finishes.
  /// Owner is expected to dismiss the overlay (clear roll state, refresh
  /// messages, etc) here.
  final VoidCallback onDone;

  /// If true, start tumbling the dice the moment the widget mounts. The
  /// in-overlay “Tap to roll” button is suppressed in this mode.
  final bool autoStart;

  @override
  State<DiceOverlay> createState() => _DiceOverlayState();
}

class _DiceOverlayState extends State<DiceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _rolling = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && widget.result != null) {
          // Hold on the face for a moment, then call onDone.
          Future.delayed(const Duration(milliseconds: 800), widget.onDone);
        }
      });
    if (widget.autoStart) {
      // Start tumbling immediately. The result will land once the parent
      // sets `widget.result` (didUpdateWidget keeps the controller running).
      _rolling = true;
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(DiceOverlay old) {
    super.didUpdateWidget(old);
    // When result arrives mid-animation, let the animation play out.
    if (widget.result != null && _ctrl.status != AnimationStatus.completed) {
      _ctrl.forward();
    }
    // If the result lands AFTER the controller already completed (rare but
    // possible if API is faster than the 1.5s tumble), the addStatusListener
    // never re-fires. Schedule the hand-off here so onDone still gets called.
    if (widget.result != null &&
        old.result == null &&
        _ctrl.status == AnimationStatus.completed) {
      Future.delayed(const Duration(milliseconds: 800), widget.onDone);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _startRoll() {
    if (_rolling) return;
    setState(() => _rolling = true);
    widget.onTapDice?.call();
    _ctrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.requiresRoll.purpose.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: AppTheme.pressStart(11, color: PixelColors.accentGold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.requiresRoll.dice.toUpperCase()} vs DC ${widget.requiresRoll.dc}'
                  '${widget.requiresRoll.modifierStat != null ? ' · ${widget.requiresRoll.modifierStat}' : ''}',
                  style: AppTheme.pressStart(8, color: PixelColors.textMuted),
                ),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final t = _ctrl.value;
                    final landed = widget.result != null &&
                        _ctrl.status == AnimationStatus.completed;
                    return _DieFace(
                      face: landed
                          ? widget.result!.raw
                          : _rolling
                              ? (1 + (t * 60).floor() % _maxFace())
                              : _maxFace(),
                      dice: widget.requiresRoll.dice,
                      tumbling: _rolling && !landed,
                      progress: t,
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (widget.result != null &&
                    _ctrl.status == AnimationStatus.completed) ...[
                  _ResultBlock(result: widget.result!),
                  const SizedBox(height: 12),
                  PixelButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward,
                    onPressed: widget.onDone,
                  ),
                ] else if (!_rolling &&
                    !widget.autoStart &&
                    widget.onTapDice != null)
                  PixelButton(
                    label: 'Tap to roll',
                    icon: Icons.casino,
                    onPressed: _startRoll,
                  )
                else
                  Text('Rolling...',
                      style: AppTheme.vt323(20, color: PixelColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _maxFace() {
    switch (widget.requiresRoll.dice) {
      case 'd20':
        return 20;
      case 'd6':
        return 6;
      case 'd100':
        return 100;
      default:
        return 20;
    }
  }
}

class _DieFace extends StatelessWidget {
  const _DieFace(
      {required this.face,
      required this.dice,
      required this.tumbling,
      required this.progress});
  final int face;
  final String dice;
  final bool tumbling;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final size = dice == 'd100' ? 100.0 : 96.0;
    final angle = tumbling ? progress * math.pi * 6 : 0.0;
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: PixelColors.parchment,
          border: Border.all(color: PixelColors.accentGold, width: 3),
          boxShadow: const [
            BoxShadow(color: PixelColors.borderOuter, offset: Offset(3, 3)),
          ],
        ),
        child: Center(
          child: Text(
            face.toString(),
            style: AppTheme.pressStart(28, color: PixelColors.textOnParchment),
          ),
        ),
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.result});
  final ResolveRollResult result;

  @override
  Widget build(BuildContext context) {
    final tone = switch (result.outcome) {
      'critical_success' => PixelColors.accentGold,
      'success' => PixelColors.accentGreen,
      'fail' => PixelColors.accentRed,
      'critical_fail' => PixelColors.accentRed,
      _ => PixelColors.textOnInk,
    };
    final label = switch (result.outcome) {
      'critical_success' => 'CRITICAL SUCCESS',
      'success' => 'SUCCESS',
      'fail' => 'FAILURE',
      'critical_fail' => 'CRITICAL FAILURE',
      _ => result.outcome.toUpperCase(),
    };
    return Column(
      children: [
        Text(label, style: AppTheme.pressStart(12, color: tone)),
        const SizedBox(height: 4),
        Text(
          'Rolled ${result.raw}'
          '${result.modifier != 0 ? ' ${result.modifier >= 0 ? '+' : ''}${result.modifier}' : ''}'
          ' = ${result.total} vs DC ${result.dc}',
          style: AppTheme.vt323(18, color: PixelColors.textMuted),
        ),
      ],
    );
  }
}
