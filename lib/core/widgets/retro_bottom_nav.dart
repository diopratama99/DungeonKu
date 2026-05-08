import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';

/// Persistent retro bottom navigation. Each [RetroNavItem] is a square
/// pixel-bordered cell with a tiny Press Start label so it reads like an
/// arcade menu rather than a default Material `BottomNavigationBar`.
///
/// Keep this widget pure & cheap — it lives at the root of every primary
/// shell page, so a heavy rebuild here would feel sluggish.
class RetroBottomNav extends StatelessWidget {
  const RetroBottomNav({
    required this.currentIndex,
    required this.items,
    super.key,
  });

  final int currentIndex;
  final List<RetroNavItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panelBackground,
        border: Border(
          top: BorderSide(color: PixelColors.borderHighlight, width: 2),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavCell(
                  item: items[i],
                  selected: i == currentIndex,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RetroNavItem {
  const RetroNavItem({
    required this.label,
    required this.icon,
    required this.location,
  });

  final String label;
  final IconData icon;
  final String location;
}

class _NavCell extends StatelessWidget {
  const _NavCell({required this.item, required this.selected});
  final RetroNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent =
        selected ? PixelColors.accentGold : PixelColors.borderSoft;
    final fg = selected ? PixelColors.accentGold : PixelColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : () => context.go(item.location),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? PixelColors.panelInner
                : PixelColors.inkBackground,
            border: Border.all(color: accent, width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, color: fg, size: 18),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTheme.pressStart(7, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
