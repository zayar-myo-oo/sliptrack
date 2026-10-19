import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'state.dart';
import '../shared/screens.dart';
import '../features/transactions/income_screen.dart';
import '../features/companion/companion_screen.dart';

class SlipTrackApp extends ConsumerStatefulWidget {
  const SlipTrackApp({super.key});
  @override
  ConsumerState<SlipTrackApp> createState() => _AppState();
}

class _AppState extends ConsumerState<SlipTrackApp>
    with WidgetsBindingObserver {
  late final GoRouter router;
  bool locked = false, authenticating = false, scannerStarted = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final prefs = ref.read(preferencesProvider);
    locked = prefs.values['lock'] == true;
    router = GoRouter(
      initialLocation: prefs.values['onboarded'] == true ? '/' : '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        ShellRoute(
          builder: (_, state, child) =>
              AppShell(path: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            GoRoute(
              path: '/transactions',
              builder: (_, state) => TransactionsScreen(
                reviewOnly: state.uri.queryParameters['review'] == 'true',
                initialMonth: DateTime.tryParse(
                  '${state.uri.queryParameters['month'] ?? ''}-01',
                ),
              ),
            ),
            GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
            GoRoute(
              path: '/analytics',
              builder: (_, _) => const AnalyticsScreen(),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
            ),
          ],
        ),
        GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
        GoRoute(path: '/companion', builder: (_, _) => const CompanionScreen()),
        GoRoute(
          path: '/income',
          builder: (_, state) => IncomeScreen(
            initialMonth: DateTime.tryParse(
              '${state.uri.queryParameters['month'] ?? ''}-01',
            ),
          ),
        ),
        GoRoute(
          path: '/income/:id',
          builder: (_, state) => IncomeScreen(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/review/:id',
          builder: (_, state) => ReviewScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
    if (!locked) scheduleMicrotask(_initializeScanner);
  }

  Future<void> _initializeScanner() async {
    if (scannerStarted) return;
    scannerStarted = true;
    await ref.read(coachProvider).initialize();
    try {
      await ref.read(scannerProvider).initialize();
    } catch (_) {
      /* Picker remains available. */
    }
  }

  Future<void> unlock() async {
    if (authenticating) return;
    authenticating = true;
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock your private SlipTrack records',
      );
      if (ok && mounted) {
        setState(() => locked = false);
        await _initializeScanner();
        await ref.read(scannerProvider).lifecycle(true);
      }
    } catch (_) {
      /* Authentication errors leave the app locked. */
    } finally {
      authenticating = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (authenticating) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (ref.read(preferencesProvider).values['lock'] == true) {
        setState(() => locked = true);
      }
      unawaited(ref.read(scannerProvider).lifecycle(false));
    } else if (state == AppLifecycleState.resumed && !locked) {
      unawaited(ref.read(coachProvider).evaluate());
      unawaited(ref.read(scannerProvider).lifecycle(true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, _) => MaterialApp.router(
        title: 'SlipTrack',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        locale: prefs.locale,
        supportedLocales: const [Locale('en'), Locale('my'), Locale('th')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeMode: prefs.theme,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        builder: (_, child) => locked
            ? Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 64),
                      const SizedBox(height: 24),
                      const Text('SlipTrack is locked'),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: unlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Unlock'),
                      ),
                    ],
                  ),
                ),
              )
            : child!,
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff087f72),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff101c1c)
          : const Color(0xfff3f6f5),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xff1b2c2b) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({required this.path, required this.child, super.key});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const paths = ['/', '/transactions', '/scan', '/analytics', '/settings'];
    const labels = [
      'Overview',
      'Transactions',
      'Scan',
      'Analytics',
      'Settings',
    ];
    const icons = [
      Icons.grid_view_rounded,
      Icons.swap_horiz_rounded,
      Icons.document_scanner_outlined,
      Icons.bar_chart_rounded,
      Icons.tune_rounded,
    ];
    final prefs = ref.watch(preferencesProvider);
    final index = paths.indexOf(path).clamp(0, 4);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (MediaQuery.sizeOf(context).width >= 800)
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (i) => context.go(paths[i]),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Icon(Icons.receipt_long, size: 32),
                ),
                destinations: List.generate(
                  5,
                  (i) => NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(prefs.text(labels[i])),
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 800
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(paths[i]),
              destinations: List.generate(
                5,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: prefs.text(labels[i]),
                ),
              ),
            ),
    );
  }
}
