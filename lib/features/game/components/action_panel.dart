import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/data/models/messages.dart';

class ActionPanel extends StatelessWidget {
  const ActionPanel({
    required this.options,
    required this.disabled,
    required this.onTapOption,
    super.key,
  });

  final List<ChatOption> options;
  final bool disabled;
  final void Function(ChatOption option) onTapOption;

  IconData _iconFor(String key) {
    switch (key) {
      case 'sword':
        return Icons.handyman;
      case 'sparkle':
        return Icons.auto_awesome;
      case 'shield':
        return Icons.shield;
      case 'running':
        return Icons.directions_run;
      case 'speech':
        return Icons.chat_bubble_outline;
      case 'check':
        return Icons.check;
      case 'cross':
        return Icons.close;
      case 'eye':
        return Icons.visibility;
      case 'magnify':
        return Icons.search;
      case 'footstep':
        return Icons.directions_walk;
      case 'fire':
        return Icons.local_fire_department;
      case 'arrow':
        return Icons.arrow_forward;
      default:
        return Icons.auto_awesome;
    }
  }

  PixelButtonTone _toneFor(String kind) {
    switch (kind) {
      case 'pivotal':
        return PixelButtonTone.danger;
      case 'situational':
        return PixelButtonTone.gold;
      case 'template_common':
        return PixelButtonTone.neutral;
      default:
        return PixelButtonTone.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(top: BorderSide(color: PixelColors.borderSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (options.any((o) => o.kind == 'pivotal'))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'PIVOTAL MOMENT',
                style: AppTheme.pressStart(8, color: PixelColors.accentRed),
                textAlign: TextAlign.center,
              ),
            ),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: PixelButton(
                label: o.label,
                icon: _iconFor(o.icon),
                tone: _toneFor(o.kind),
                fullWidth: true,
                onPressed: disabled ? null : () => onTapOption(o),
              ),
            ),
        ],
      ),
    );
  }
}
