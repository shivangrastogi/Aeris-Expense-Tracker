import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/gamification_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/key_gate.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_lock_gate.dart';

class AerisExpenseApp extends ConsumerWidget {
  const AerisExpenseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final accent = ref.watch(gamificationProvider.select((s) => s.accent));
    final seed = accent != null ? Color(accent) : null;

    return MaterialApp(
      title: 'AERIS Expense',
      debugShowCheckedModeBanner: false,
      theme: buildAerisTheme(Brightness.light, seed: seed),
      darkTheme: buildAerisTheme(Brightness.dark, seed: seed),
      themeMode: ThemeMode.system,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      // Apply a transparent, theme-aware status-bar style to EVERY screen
      // (including the AppBar-less Home), so the bar never renders black.
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
          child: child!,
        );
      },
      home: authState.when(
        data: (user) => user == null
            ? const LoginScreen()
            : AppLockGate(child: KeyGate(uid: user.uid)),
        loading: () => const SplashScreen(),
        error: (_, __) => const LoginScreen(),
      ),
    );
  }
}
