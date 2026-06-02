import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/routes.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/key_gate.dart';
import 'screens/splash_screen.dart';

class AerisExpenseApp extends ConsumerWidget {
  const AerisExpenseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'AERIS Expense',
      debugShowCheckedModeBanner: false,
      theme: buildAerisTheme(Brightness.light),
      darkTheme: buildAerisTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: authState.when(
        data: (user) =>
            user == null ? const LoginScreen() : KeyGate(uid: user.uid),
        loading: () => const SplashScreen(),
        error: (_, __) => const LoginScreen(),
      ),
    );
  }
}
