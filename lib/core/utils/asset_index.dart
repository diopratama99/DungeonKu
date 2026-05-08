import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight cache around `AssetManifest.json` so widgets can ask
/// "is this asset bundled?" synchronously after the manifest is loaded once.
class AssetIndex {
  AssetIndex._(this._paths);

  final Set<String> _paths;

  static Future<AssetIndex> load() async {
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      return AssetIndex._(map.keys.toSet());
    } catch (_) {
      return AssetIndex._(<String>{});
    }
  }

  bool exists(String path) => _paths.contains(path);

  /// Returns the first existing asset path in [candidates] or `null`.
  String? firstExisting(Iterable<String> candidates) {
    for (final p in candidates) {
      if (p.isEmpty) continue;
      if (_paths.contains(p)) return p;
    }
    return null;
  }

  /// Returns the alphabetically first asset whose path begins with [prefix],
  /// or `null` if none match. Useful when an artist has dropped a scene-specific
  /// PNG (e.g. `assets/images/backgrounds/ashfall_hollow_inn_road.png`) and we
  /// just want "any background for this template".
  String? firstWithPrefix(String prefix) {
    if (prefix.isEmpty) return null;
    String? best;
    for (final p in _paths) {
      if (!p.startsWith(prefix)) continue;
      if (best == null || p.compareTo(best) < 0) best = p;
    }
    return best;
  }

  /// All assets whose path starts with [prefix], sorted alphabetically.
  List<String> listWithPrefix(String prefix) {
    final out = <String>[];
    for (final p in _paths) {
      if (p.startsWith(prefix)) out.add(p);
    }
    out.sort();
    return out;
  }
}

/// Provider so widgets can `ref.watch(assetIndexProvider)` and get the manifest.
final assetIndexProvider =
    FutureProvider<AssetIndex>((ref) => AssetIndex.load());
