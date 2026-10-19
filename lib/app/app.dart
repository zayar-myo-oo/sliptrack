import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'state.dart';
import '../shared/screens.dart';
import '../features/transactions/income_screen.dart';
import '../features/companion/companion_screen.dart';
import '../features/companion/companion_card.dart';
import '../features/settings/manage_data_screen.dart';
import '../features/companion/coach_models.dart';
import '../core/income_cycle.dart';
import '../core/models.dart';
import '../core/exchange_rate.dart';
import '../shared/design.dart';
import '../shared/motion.dart';
import '../core/widget_sync.dart';
import '../core/plans.dart';
import '../shared/privacy.dart';
import '../features/plans/plans_screen.dart';

class SlipTrackApp extends ConsumerStatefulWidget {
  const SlipTrackApp({super.key});
  @override
  ConsumerState<SlipTrackApp> createState() => _AppState();
}

class _AppState extends ConsumerState<SlipTrackApp>
    with WidgetsBindingObserver {
  late final GoRouter router;
  late final Preferences _prefs;
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
          pageBuilder: (_, state, child) => NoTransitionPage<void>(
            key: const ValueKey('app-shell'),
            child: AppShell(path: state.uri.path, child: child),
          ),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, state) =>
                  _tabPage(state, child: const DashboardScreen()),
            ),
            GoRoute(
              path: '/transactions',
              pageBuilder: (_, state) => _tabPage(
                state,
                child: TransactionsScreen(
                  reviewOnly: state.uri.queryParameters['review'] == 'true',
                  initialMonth: DateTime.tryParse(
                    '${state.uri.queryParameters['month'] ?? ''}-01',
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/scan',
              pageBuilder: (_, state) =>
                  _tabPage(state, child: const ScanScreen()),
            ),
            GoRoute(
              path: '/analytics',
              pageBuilder: (_, state) =>
                  _tabPage(state, child: const AnalyticsScreen()),
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (_, state) =>
                  _tabPage(state, child: const SettingsScreen()),
            ),
            GoRoute(
              path: '/accounts',
              pageBuilder: (_, state) =>
                  _detailPage(state, child: const AccountsScreen()),
            ),
            GoRoute(
              path: '/companion',
              pageBuilder: (_, state) =>
                  _detailPage(state, child: const CompanionScreen()),
            ),
            GoRoute(
              path: '/plans',
              pageBuilder: (_, state) => _detailPage(
                state,
                child: PlansScreen(
                  tab:
                      int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
                ),
              ),
            ),
            GoRoute(
              path: '/manage-data',
              pageBuilder: (_, state) =>
                  _detailPage(state, child: const ManageDataScreen()),
            ),
            GoRoute(
              path: '/income',
              pageBuilder: (_, state) => _detailPage(
                state,
                child: IncomeScreen(
                  initialMonth: DateTime.tryParse(
                    '${state.uri.queryParameters['month'] ?? ''}-01',
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/income/:id',
              pageBuilder: (_, state) => _detailPage(
                state,
                child: IncomeScreen(id: state.pathParameters['id']!),
              ),
            ),
            GoRoute(
              path: '/expense',
              pageBuilder: (_, state) => _detailPage(
                state,
                child: IncomeScreen(
                  expense: true,
                  initialMonth: DateTime.tryParse(
                    '${state.uri.queryParameters['month'] ?? ''}-01',
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/expense/:id',
              pageBuilder: (_, state) => _detailPage(
                state,
                child: IncomeScreen(
                  expense: true,
                  id: state.pathParameters['id']!,
                ),
              ),
            ),
            GoRoute(
              path: '/review/:id',
              pageBuilder: (_, state) => _detailPage(
                state,
                child: ReviewScreen(id: state.pathParameters['id']!),
              ),
            ),
          ],
        ),
      ],
    );
    _prefs = prefs..addListener(_syncWidget);
    hideAmounts.value = prefs.values['hideAmounts'] == true;
    if (!locked) scheduleMicrotask(_initializeScanner);
  }

  Future<void> _initializeScanner() async {
    if (scannerStarted) return;
    scannerStarted = true;
    await ref.read(coachProvider).initialize();
    try {
      await _postRecurringBills();
    } catch (_) {
      /* A failed bill post is retried on the next launch. */
    }
    try {
      await ref.read(repositoryProvider).recategorize();
    } catch (_) {
      /* Categories are a convenience; records stay intact. */
    }
    try {
      await ref.read(scannerProvider).initialize();
    } catch (_) {
      /* Picker remains available. */
    }
  }

  /// Adds this month's due recurring bills as manual expenses, once each.
  Future<void> _postRecurringBills() async {
    final prefs = ref.read(preferencesProvider);
    final bills = readList(prefs.values, 'recurring', RecurringBill.fromJson);
    final now = DateTime.now();
    final due = billsToPost(bills, now);
    if (due.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    for (final b in due) {
      await repo.saveSlip(slipForBill(b, now));
      b.lastPosted = monthKey(now);
    }
    await prefs.update('recurring', [for (final b in bills) b.toJson()]);
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
        await ref.read(coachProvider).evaluate();
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
      _syncWidget();
      unawaited(ref.read(scannerProvider).lifecycle(false));
    } else if (state == AppLifecycleState.resumed && !locked) {
      unawaited(ref.read(coachProvider).evaluate());
      unawaited(ref.read(scannerProvider).lifecycle(true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prefs.removeListener(_syncWidget);
    router.dispose();
    super.dispose();
  }

  void _syncWidget() {
    final slips = ref.read(slipsProvider).asData?.value;
    if (slips != null) {
      unawaited(syncHomeWidget(slips, ref.read(preferencesProvider).values));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    ref.listen(slipsProvider, (_, _) => _syncWidget());
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
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Palette.brand,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xff8fd1ac) : Palette.brand,
          onPrimary: dark ? Palette.brandDeep : Colors.white,
          primaryContainer: dark ? const Color(0xff24402f) : Palette.mint,
          onPrimaryContainer: dark ? Palette.mint : Palette.brandDeep,
          surface: dark ? const Color(0xff1a221e) : Colors.white,
          error: Palette.expense,
        );
    final ink = dark ? const Color(0xffeef2ee) : const Color(0xff15211b);
    final fill = dark ? const Color(0xff243029) : const Color(0xffeef1ec);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.35),
        bodyLarge: TextStyle(fontSize: 15, color: ink),
        bodySmall: TextStyle(fontSize: 12, color: ink.withValues(alpha: .6)),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.3,
        ),
        headlineSmall: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.5,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        iconColor: ink.withValues(alpha: .7),
        shape: shape,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? const Color(0xff2c3832) : const Color(0xffe7e9e3),
        space: 1,
        thickness: 1,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xff0f1512)
          : const Color(0xfff4f4ef),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 56,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: dark ? const Color(0xff1a221e) : Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: fill,
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          side: BorderSide(
            color: dark ? const Color(0xff2c3832) : const Color(0xffdfe3dc),
          ),
          shape: shape,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: fill,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({required this.path, required this.child, super.key});
  final String path;
  final Widget child;
  static const paths = [
    '/',
    '/transactions',
    '/scan',
    '/analytics',
    '/settings',
  ];
  static const labels = [
    'Overview',
    'History',
    'Scan',
    'Analytics',
    'Settings',
  ];
  static const icons = [
    Icons.home_rounded,
    Icons.swap_horiz_rounded,
    Icons.document_scanner_outlined,
    Icons.bar_chart_rounded,
    Icons.tune_rounded,
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final tab = path.startsWith('/review')
        ? '/scan'
        : ['/accounts', '/manage-data'].contains(path)
        ? '/settings'
        : path.startsWith('/income') ||
              path.startsWith('/expense') ||
              path == '/companion' ||
              path == '/plans'
        ? '/'
        : path;
    final index = paths.indexOf(tab).clamp(0, 4);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      extendBody: false,
      body: SafeArea(
        bottom: wide,
        child: Row(
          children: [
            if (wide)
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
                    icon: i == 0 ? const NavigationBuddy() : Icon(icons[i]),
                    label: Text(prefs.text(labels[i])),
                  ),
                ),
              ),
            Expanded(
              child: ClipRect(
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : _BottomBar(
              index: index,
              labels: [for (final l in labels) prefs.text(l)],
            ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.labels});
  final int index;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(int i) {
      final selected = i == index;
      final color = selected ? scheme.primary : Palette.muted(context);
      return Expanded(
        child: GestureDetector(
          key: ValueKey('nav:${AppShell.paths[i]}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            context.go(AppShell.paths[i]);
          },
          child: AnimatedScale(
            scale: selected ? 1.08 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                i == 0
                    ? const SizedBox(
                        height: 28,
                        child: FittedBox(child: NavigationBuddy()),
                      )
                    : Icon(AppShell.icons[i], color: color, size: 24),
                const SizedBox(height: 3),
                Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Palette.surface(context),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            item(0),
            item(1),
            Expanded(
              child: Center(
                child: Material(
                  key: const ValueKey('nav:/scan'),
                  color: index == 2 ? Palette.brandDeep : scheme.primary,
                  shape: const CircleBorder(),
                  elevation: 0,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    splashFactory: NoSplash.splashFactory,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.go('/scan');
                    },
                    child: Tooltip(
                      message: labels[2],
                      child: SizedBox(
                        width: 50,
                        height: 50,
                        child: Icon(
                          Icons.document_scanner_outlined,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            item(3),
            item(4),
          ],
        ),
      ),
    );
  }
}

class NavigationBuddy extends ConsumerWidget {
  const NavigationBuddy({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coach = ref.watch(coachProvider),
        prefs = ref.watch(preferencesProvider);
    final slips = ref.watch(slipsProvider).asData?.value ?? <Slip>[];
    final cycle = IncomeCycle.fromIncome(DateTime.now(), slips);
    return ListenableBuilder(
      listenable: Listenable.merge([coach, prefs]),
      builder: (_, _) {
        final life = BudgetLife.fromTotals(
          totalsFor(slips.where((s) => cycle.contains(s.date))),
          prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros,
          reserve: cycle.reserveThb(
            slips,
            prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros,
          ),
        );
        return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).scaffoldBackgroundColor,
              width: 2,
            ),
          ),
          child: ClipOval(
            child: Buddy(
              mood: life.mood,
              progress: coach.progress,
              outfit: coach.outfit,
              compact: true,
            ),
          ),
        );
      },
    );
  }
}

/// Tabs switch instantly, like the iOS tab bar; detail screens slide in.
Page<void> _tabPage(GoRouterState state, {required Widget child}) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

Page<void> _detailPage(GoRouterState state, {required Widget child}) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: Motion.fast,
      transitionsBuilder: (context, animation, secondary, child) {
        if (Motion.reduced(context)) return child;
        final t = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween(
            begin: const Offset(.18, 0),
            end: Offset.zero,
          ).animate(t),
          child: FadeTransition(opacity: t, child: child),
        );
      },
    );
