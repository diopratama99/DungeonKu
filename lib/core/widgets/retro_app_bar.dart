import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Branded AppBar shared by every top-level screen.
///
/// Always shows the DungeonKu crest at the leading slot (or after the
/// platform back button), the title in Press Start 2P, and a 2px gold
/// border at the bottom so screens feel like distinct chapters in the
/// same tome.
///
/// Use via `Scaffold(appBar: RetroAppBar(title: 'PARTY'))`.
class RetroAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RetroAppBar({
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.showCrest = true,
    super.key,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool showCrest;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      titleSpacing: leading == null ? 16 : 4,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCrest) ...[
            SizedBox(
              width: 24,
              height: 24,
              child: Image.asset(
                'assets/images/logo/dungeonku_app-icon.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.pressStart(11, color: PixelColors.accentGold),
            ),
          ),
        ],
      ),
      actions: actions,
      bottom: bottom,
      flexibleSpace: const _AppBarBackdrop(),
      shape: const Border(
        bottom: BorderSide(color: PixelColors.borderHighlight, width: 2),
      ),
    );
  }
}

class _AppBarBackdrop extends StatelessWidget {
  const _AppBarBackdrop();
  @override
  Widget build(BuildContext context) {
    // A subtle vertical gradient so the bar reads as bevelled metal.
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2A2418),
            Color(0xFF1E1A14),
          ],
        ),
      ),
    );
  }
}
