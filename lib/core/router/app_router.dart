import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/data/supabase_providers.dart';
import 'package:dungeonku/features/auth/sign_in_screen.dart';
import 'package:dungeonku/features/auth/splash_screen.dart';
import 'package:dungeonku/features/campaigns/campaigns_screen.dart';
import 'package:dungeonku/features/campaigns/template_picker_screen.dart';
import 'package:dungeonku/features/characters/character_creation_screen.dart';
import 'package:dungeonku/features/characters/characters_screen.dart';
import 'package:dungeonku/features/game/game_screen.dart';
import 'package:dungeonku/features/game_over/game_over_screen.dart';
import 'package:dungeonku/features/settings/settings_screen.dart';

/// go_router with an auth-aware redirect. We re-build the router whenever the auth stream
/// emits so unauthenticated users get punted back to /sign-in even if they were inside a
/// game when their session expired.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever auth state changes.
  ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (ctx, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final loggedIn = session != null;
      final loc = state.matchedLocation;

      // Not logged in → always go to /sign-in
      if (!loggedIn) return loc == '/sign-in' ? null : '/sign-in';
      // Logged in but at splash or sign-in → go to /characters
      if (loc == '/' || loc == '/sign-in') return '/characters';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(
          path: '/characters', builder: (_, __) => const CharactersScreen()),
      GoRoute(
        path: '/characters/new',
        builder: (_, __) => const CharacterCreationScreen(),
      ),
      GoRoute(path: '/campaigns', builder: (_, __) => const CampaignsScreen()),
      GoRoute(
        path: '/campaigns/new',
        builder: (_, state) {
          final characterId = state.uri.queryParameters['character_id'] ?? '';
          return TemplatePickerScreen(characterId: characterId);
        },
      ),
      GoRoute(
        path: '/game/:campaignId',
        builder: (_, state) =>
            GameScreen(campaignId: state.pathParameters['campaignId']!),
      ),
      GoRoute(
        path: '/game-over/:campaignId',
        builder: (_, state) =>
            GameOverScreen(campaignId: state.pathParameters['campaignId']!),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
});
