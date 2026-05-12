import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_button.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignUp) {
        await auth.signUp(
            email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
      } else {
        await auth.signInWithPassword(
            email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
      }
      if (!mounted) return;
      context.go('/characters');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PixelColors.inkBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dimmed ambient backdrop using the loading-screen art.
          Image.asset(
            'assets/images/splash/loading_screen.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: PixelColors.inkBackground),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Color(0xEE000000)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: PixelPanel(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo crest replaces the plain wordmark.
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 110),
                            child: Image.asset(
                              'assets/images/logo/dungeonku_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Text(
                                'DUNGEONKU',
                                textAlign: TextAlign.center,
                                style: AppTheme.pressStart(20,
                                    color: PixelColors.accentGold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isSignUp
                                ? '\u2756  RAISE A NEW HERO  \u2756'
                                : '\u2756  RETURN, ADVENTURER  \u2756',
                            textAlign: TextAlign.center,
                            style: AppTheme.pressStart(9,
                                color: PixelColors.textMuted),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            style: AppTheme.vt323(20),
                            decoration: _decoration('Email'),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            style: AppTheme.vt323(20),
                            decoration: _decoration('Password'),
                            validator: (v) => (v == null || v.length < 6)
                                ? '6+ chars please'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: AppTheme.vt323(16,
                                    color: PixelColors.accentRed)),
                          ],
                          const SizedBox(height: 24),
                          PixelButton(
                            label: _isSignUp ? 'Create account' : 'Sign in',
                            fullWidth: true,
                            onPressed: _busy ? null : _submit,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _isSignUp = !_isSignUp),
                            child: Text(
                              _isSignUp
                                  ? 'Already have an account? Sign in'
                                  : "Don't have an account? Create one",
                              style: AppTheme.vt323(16,
                                  color: PixelColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: AppTheme.pressStart(8, color: PixelColors.textMuted),
        filled: true,
        fillColor: PixelColors.panelInner,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelColors.borderSoft),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelColors.borderSoft),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelColors.accentGold, width: 2),
        ),
      );
}
