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
    // If the caller didn't pass an explicit leading widget but the
    // current route has a stack to pop, swap in our pixel-art arrow so
    // the back button stops reading as Material default. `canPop`
    // matches Flutter's own implicit-back-button check.
    final effectiveLeading = leading ??
        (ModalRoute.of(context)?.canPop == true
            ? PixelBackButton(onTap: () => Navigator.of(context).maybePop())
            : null);
    return AppBar(
      leading: effectiveLeading,
      titleSpacing: effectiveLeading == null ? 16 : 4,
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

/// Pixel-art replacement for the default Material back arrow. Uses the
/// shared `support_arrow_left.png` so the back affordance matches the
/// rest of the app's UI icons. Tap target stays at 48×48 (the AppBar
/// leading slot) for accessibility even though the visible sprite is
/// 24×24.
class PixelBackButton extends StatelessWidget {
  const PixelBackButton({required this.onTap, super.key});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: Image.asset(
              'assets/images/icons/processed/support_arrow_left.png',
              filterQuality: FilterQuality.none,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.arrow_back,
                color: PixelColors.accentGold,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
