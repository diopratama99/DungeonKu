import 'dart:async';

import 'package:flutter/material.dart';

/// Reveals [text] character-by-character in a typewriter animation.
///
/// The reveal speed adapts to content length so short messages feel snappy
/// and long narration still finishes in a reasonable time. Tapping the widget
/// instantly completes the animation (skip-ahead).
///
/// After the full text is visible, [onDone] fires once.
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    required this.text,
    required this.style,
    this.onDone,
    this.minCharDelay = const Duration(milliseconds: 18),
    this.maxCharDelay = const Duration(milliseconds: 45),
    super.key,
  });

  final String text;
  final TextStyle style;
  final VoidCallback? onDone;

  /// Fastest per-character interval (used for long text).
  final Duration minCharDelay;

  /// Slowest per-character interval (used for short text).
  final Duration maxCharDelay;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  int _charCount = 0;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _timer?.cancel();
      _charCount = 0;
      _done = false;
      _startTyping();
    }
  }

  void _startTyping() {
    if (widget.text.isEmpty) {
      _done = true;
      widget.onDone?.call();
      return;
    }
    // Adaptive speed: short text → slower reveal, long text → faster.
    // Lerp between max and min delay based on length (20..300 chars).
    final len = widget.text.length;
    final t = ((len - 20) / 280).clamp(0.0, 1.0);
    final ms = widget.maxCharDelay.inMilliseconds +
        (widget.minCharDelay.inMilliseconds -
                widget.maxCharDelay.inMilliseconds) *
            t;
    final delay = Duration(milliseconds: ms.round());

    _timer = Timer.periodic(delay, (_) {
      if (_charCount >= widget.text.length) {
        _finish();
        return;
      }
      setState(() => _charCount++);
    });
  }

  void _finish() {
    _timer?.cancel();
    if (!_done) {
      _done = true;
      setState(() => _charCount = widget.text.length);
      widget.onDone?.call();
    }
  }

  /// Tap to skip — instantly reveal all text.
  void skip() => _finish();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _done ? null : skip,
      child: Text(
        widget.text.substring(0, _charCount),
        style: widget.style,
      ),
    );
  }
}
