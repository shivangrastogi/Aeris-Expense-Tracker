import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/gamification_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/transactions_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/key_gate.dart';
import 'screens/splash_screen.dart';
import 'services/sync_outbox.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/sync_status.dart';

class AerisExpenseApp extends ConsumerStatefulWidget {
  const AerisExpenseApp({super.key});

  @override
  ConsumerState<AerisExpenseApp> createState() => _AerisExpenseAppState();
}

class _AerisExpenseAppState extends ConsumerState<AerisExpenseApp>
    with WidgetsBindingObserver {
  // Guards daily-usage writes to at most one per local day (per process).
  String? _lastUsageDay;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyHighRefreshRate();
    // Record usage as soon as a user is available (cold start / login).
    ref.listenManual(currentUserIdProvider, (_, uid) {
      if (uid != null) {
        _recordUsage();
        // Re-send anything left unsynced from a previous run, then keep
        // draining the offline outbox.
        SyncOutbox.instance.startFor(uid);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Many OEMs (Realme/OPPO/Xiaomi) silently drop the surface back to 60Hz
    // after the app is backgrounded — re-assert the high mode on resume.
    if (state == AppLifecycleState.resumed) {
      _applyHighRefreshRate();
      _recordUsage();
      // Back in the foreground — often after reconnecting. Pick up anything
      // the background SMS isolate queued and try to flush.
      SyncOutbox.instance.refresh().then((_) => SyncOutbox.instance.syncNow());
    }
  }

  /// Logs one app-open to Firestore (users/{uid}/usage/{yyyy-MM-dd}), at most
  /// once per local day per process so we don't spam writes.
  void _recordUsage() {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final now = DateTime.now();
    final day = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (day == _lastUsageDay) return;
    _lastUsageDay = day;
    // Fire-and-forget; offline writes queue and sync automatically.
    ref.read(firestoreServiceProvider).recordDailyUsage(uid, day).catchError(
        (_) {/* offline / transient — Firestore will retry on its own */});
  }

  // The setHighRefreshRate() call in main() often runs before the platform
  // view is attached, so on those devices it doesn't take. Re-applying after
  // the first frame is what actually pins the display to 120Hz.
  void _applyHighRefreshRate() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await FlutterDisplayMode.setHighRefreshRate();
      } catch (_) {/* unsupported platform — ignore */}
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final accent = ref.watch(gamificationProvider.select((s) => s.accent));
    final seed = accent != null ? Color(accent) : null;
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'AERIS Expense',
      debugShowCheckedModeBanner: false,
      theme: buildAerisTheme(Brightness.light, seed: seed),
      darkTheme: buildAerisTheme(Brightness.dark, seed: seed),
      themeMode: themeMode,
      // Smoothly cross-fade colours when the theme flips instead of a harsh
      // instant swap.
      themeAnimationDuration: const Duration(milliseconds: 600),
      themeAnimationCurve: Curves.easeInOut,
      navigatorKey: _navigatorKey,
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
          child: SyncShell(
            navigatorKey: _navigatorKey,
            signedIn: authState.valueOrNull != null,
            child: child!,
          ),
        );
      },
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        child: authState.when(
          data: (user) => user == null
              ? const LoginScreen(key: ValueKey('login'))
              : AppLockGate(
                  key: const ValueKey('app'), child: KeyGate(uid: user.uid)),
          loading: () => const SplashScreen(key: ValueKey('splash')),
          error: (_, __) => const LoginScreen(key: ValueKey('login')),
        ),
      ),
    );
  }
}
