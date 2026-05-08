import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/core/env.dart';
import 'package:dungeonku/core/router/app_router.dart';
import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/utils/ngrok_skip_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use only the .ttf files bundled in `google_fonts/` — never hit
  // fonts.gstatic.com. This makes the app work offline and on networks
  // that block Google's CDN.
  GoogleFonts.config.allowRuntimeFetching = false;
  await Env.load();
  // When the Supabase URL is an ngrok-free.dev tunnel, route every request
  // through a client that adds `ngrok-skip-browser-warning`. Without that
  // header ngrok serves an HTML interstitial which Supabase tries to decode
  // as JSON and reports as "failed to decode error response".
  final usesNgrok = Env.supabaseUrl.contains('ngrok-free.dev') ||
      Env.supabaseUrl.contains('ngrok.io');
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    httpClient: usesNgrok ? NgrokSkipClient() : null,
  );
  runApp(const ProviderScope(child: DungeonKuApp()));
}

class DungeonKuApp extends ConsumerWidget {
  const DungeonKuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'DungeonKu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: router,
    );
  }
}
