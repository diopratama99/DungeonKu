import 'dart:convert';

import 'package:flutter/services.dart';

/// Thin wrapper around a bundled JSON config. Call [Env.load] once at startup
/// before reading any value.
class Env {
  Env._();

  static late final Map<String, dynamic> _config;

  static Future<void> load() async {
    final raw = await rootBundle.loadString('supabase.json');
    _config = json.decode(raw) as Map<String, dynamic>;
  }

  static String _required(String key) {
    final value = _config[key] as String?;
    if (value == null || value.isEmpty) {
      throw StateError('Missing required config key: $key in supabase.json');
    }
    return value;
  }

  static String get supabaseUrl => _required('SUPABASE_URL');
  static String get supabaseAnonKey => _required('SUPABASE_ANON_KEY');
}
