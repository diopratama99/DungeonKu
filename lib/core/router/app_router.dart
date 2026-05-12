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
import 'package:dungeonku/features/codex/codex_screen.dart';
import 'package:dungeonku/features/game/game_screen.dart';
import 'package:dungeonku/features/game_over/game_over_screen.dart';
import 'package:dungeonku/features/home/home_screen.dart';
import 'package:dungeonku/features/settings/ai_roles_screen.dart';
import 'package:dungeonku/features/settings/settings_screen.dart';
import 'package:dungeonku/features/story/story_combat_screen.dart';
import 'package:dungeonku/features/story/story_screen.dart';
import 'package:dungeonku/data/repositories/campaigns_repository.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:flutter/material.dart';

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
      // Logged in but at splash or sign-in → land on the title screen
      if (loc == '/' || loc == '/sign-in') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),

      // JRPG-style title screen + main menu. All other in-game routes
      // are pushed on top of this so the device back button returns the
      // player here naturally.
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),

      // Sub-screens, formerly bottom-tab destinations. They no longer
      // share a shell — each is its own full-screen page with a back
      // button in the RetroAppBar.
      GoRoute(
        path: '/characters',
        builder: (_, __) => const CharactersScreen(),
      ),
      GoRoute(
        path: '/campaigns',
        builder: (_, __) => const CampaignsScreen(),
      ),
      GoRoute(
        path: '/codex',
        builder: (_, __) => const CodexScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/ai-roles',
        builder: (_, __) => const AiRolesScreen(),
      ),

      // Full-screen flows: hero forge + template picker + active play.
      GoRoute(
        path: '/characters/new',
        builder: (_, __) => const CharacterCreationScreen(),
      ),
      GoRoute(
        path: '/campaigns/new',
        builder: (_, state) {
          final characterId = state.uri.queryParameters['character_id'] ?? '';
          return TemplatePickerScreen(characterId: characterId);
        },
      ),
      GoRoute(
        path: '/game/:campaignId',
        builder: (_, state) => _GameRouteDispatcher(
            campaignId: state.pathParameters['campaignId']!),
      ),
      GoRoute(
        path: '/game-over/:campaignId',
        builder: (_, state) =>
            GameOverScreen(campaignId: state.pathParameters['campaignId']!),
      ),
      GoRoute(
        path: '/story-combat/:campaignId',
        builder: (_, state) =>
            StoryCombatScreen(campaignId: state.pathParameters['campaignId']!),
      ),
    ],
  );
});

/// Dispatcher between the legacy LLM-driven [GameScreen] and the new
/// scripted-graph [StoryScreen]. Reads `campaigns.is_legacy` to decide.
///
/// Pre-redesign campaigns (created before migration 20260511000000) have
/// `is_legacy=true` and still use the original DM endpoint. Newer
/// campaigns hit the story-graph engine via /story-turn + /player-action.
class _GameRouteDispatcher extends ConsumerWidget {
  const _GameRouteDispatcher({required this.campaignId});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(campaignsListProvider);
    return asyncList.when(
      loading: () => const Scaffold(
        backgroundColor: PixelColors.inkBackground,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: PixelColors.inkBackground,
        body: Center(child: Text('Error: $e')),
      ),
      data: (campaigns) {
        final match = campaigns.where((c) => c.id == campaignId);
        if (match.isEmpty) {
          // Fallback: treat as legacy so we never strand the user.
          return GameScreen(campaignId: campaignId);
        }
        final c = match.first;
        return c.isLegacy
            ? GameScreen(campaignId: campaignId)
            : StoryScreen(campaignId: campaignId);
      },
    );
  }
}
