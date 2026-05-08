import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Globally-cached Supabase client. Set after `Supabase.initialize` in main().
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Scoped ke schema `dungeonku`. Semua `.from()` / `.rpc()` otomatis resolve
/// ke `dungeonku.<table>` tanpa perlu rewrite tiap call-site.
///
/// Pakai `dbProvider` untuk data calls (tables/RPC). `supabaseClientProvider`
/// tetap dipakai untuk `client.auth`, `client.functions`, `client.storage`,
/// dan `client.channel` yang schema-independent.
final dbProvider = Provider<SupabaseQuerySchema>((ref) {
  return ref.watch(supabaseClientProvider).schema('dungeonku');
});

/// Reactive auth-state provider. Emits the current Session (or null) every time it changes.
/// Use this in the router redirect to gate authenticated routes.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  final state = ref.watch(authStateProvider);
  return state.when(
    data: (s) => s.session?.user,
    loading: () => Supabase.instance.client.auth.currentUser,
    error: (_, __) => null,
  );
});
