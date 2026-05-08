import 'package:flutter/material.dart';

import 'package:dungeonku/core/widgets/retro_bottom_nav.dart';

/// Persistent shell used by every top-level tab (Roster, Tome, Codex,
/// Settings). Hosts [child] above the [RetroBottomNav]; full-screen flows
/// like character creation, gameplay and game-over render outside this
/// shell so they get the whole viewport.
class MainShell extends StatelessWidget {
  const MainShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  static const _items = <RetroNavItem>[
    RetroNavItem(
        label: 'ROSTER', icon: Icons.groups, location: '/characters'),
    RetroNavItem(
        label: 'TOME', icon: Icons.menu_book, location: '/campaigns'),
    RetroNavItem(
        label: 'CODEX', icon: Icons.auto_stories, location: '/codex'),
    RetroNavItem(
        label: 'SETTINGS', icon: Icons.settings, location: '/settings'),
  ];

  int get _currentIndex {
    // Match longest prefix so nested paths still highlight the right tab.
    var idx = 0;
    var best = -1;
    for (var i = 0; i < _items.length; i++) {
      final loc = _items[i].location;
      if (location == loc || location.startsWith('$loc/')) {
        if (loc.length > best) {
          best = loc.length;
          idx = i;
        }
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar:
          RetroBottomNav(currentIndex: _currentIndex, items: _items),
    );
  }
}
