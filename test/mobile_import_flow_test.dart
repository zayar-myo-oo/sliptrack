import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sliptrack/app/app.dart';
import 'package:sliptrack/app/state.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/core/vault.dart';
import 'package:sliptrack/database/database.dart';
import 'package:sliptrack/features/gallery_scanner/scan_controller.dart';
import 'package:sliptrack/features/analytics/analytics_screen.dart';
import 'package:sliptrack/features/settings/settings_screen.dart';
import 'package:sliptrack/features/dashboard/dashboard_screen.dart';
import 'pipeline_test.dart' show FakeGallery, FakeOcr;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iPhone: manual income, picker, visible review queue, confirmation and monthly totals',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('app.sliptrack/media'),
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('app.sliptrack/media'),
          null,
        ),
      );
      final repo = Repository(
        SlipDatabase(NativeDatabase.memory()),
        Vault(List.generate(32, (i) => i)),
      );
      addTearDown(repo.close);
      final gallery = FakeGallery(), ocr = FakeOcr()..confidence = .5;
      final now = DateTime.now();
      ocr.text = ocr.text.replaceFirst(
        '17/10/2026',
        DateFormat('dd/MM/yyyy').format(now),
      );
      final scanner = ScanController(repo, gallery, ocr);
      addTearDown(scanner.dispose);
      final prefs = Preferences(repo, {'onboarded': true});
      final boundary = GlobalKey();
      // Load the SDK's bundled font when capturing review artifacts locally.
      final sdkRoot = Platform.environment['FLUTTER_ROOT'];
      if (sdkRoot != null) {
        final font = File(
          '$sdkRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        );
        if (font.existsSync()) {
          await (FontLoader('Roboto')..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              ))
              .load();
        }
        final icons = File(
          '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (icons.existsSync()) {
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(ByteData.sublistView(icons.readAsBytesSync())),
              ))
              .load();
        }
      }
      Future<void> capture(String name) async {
        if (Platform.environment['SLIPTRACK_CAPTURE_UI'] != '1') return;
        await tester.pump();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File('build/ui-review/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        });
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            preferencesProvider.overrideWithValue(prefs),
            scannerProvider.overrideWithValue(scanner),
          ],
          child: RepaintBoundary(key: boundary, child: const SlipTrackApp()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add income'));
      await tester.tap(find.text('Add income'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('incomeAmount')), '10000');
      await tester.enterText(find.byKey(const Key('savingsReserve')), '2500');
      await tester.ensureVisible(find.text('Save income'));
      await tester.tap(find.text('Save income'));
      await tester.pumpAndSettle();
      expect((await repo.slips()).single.isManualIncome, true);
      await tester.ensureVisible(find.text('Add expense'));
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('expenseAmount')), '250');
      await tester.pumpAndSettle();
      await capture('manual-expense');
      await tester.ensureVisible(find.text('Save expense'));
      await tester.tap(find.text('Save expense'));
      await tester.pumpAndSettle();
      expect(
        (await repo.slips()).singleWhere((s) => s.isManualExpense).amountMinor,
        25000,
      );
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(find.text('≈ 7,250.00 THB'), findsOneWidget);
      await capture('overview');
      await prefs.update('theme', 'dark');
      await tester.pumpAndSettle();
      await capture('overview-dark');
      await prefs.update('theme', 'light');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.document_scanner_outlined).last);
      await tester.pumpAndSettle();
      // Manual picker must also resume a previously paused scanner.
      scanner.paused = true;
      await tester.tap(find.byKey(const Key('pickReceipts')));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      // Re-import is idempotent and requires no per-slip confirmation.
      await tester.tap(find.byKey(const ValueKey('nav:/scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pickReceipts')));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(ocr.calls, 1);
      expect(
        (await repo.slips())
            .where((s) => !s.isManualIncome && !s.isManualExpense)
            .single
            .review,
        ReviewStatus.confirmed,
      );
      expect(
        totalsFor(await repo.slips(), month: now)['MMK']!.expense,
        14400000,
      );
      expect(totalsFor(await repo.slips(), month: now)['THB']!.income, 1000000);
      expect(
        (await repo.slips()).where((s) => s.review == ReviewStatus.pending),
        isEmpty,
      );
      expect(find.byType(NavigationBuddy), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav:/analytics')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(AnalyticsScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
      await capture('analytics');
      await tester.tap(find.byKey(const ValueKey('nav:/settings')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(AnalyticsScreen), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBuddy), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav:/')));
      await tester.pumpAndSettle();
      expect(find.text('SlipTrack'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav:/settings')));
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.byType(SettingsScreen)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Manage data'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage data'));
      await tester.pumpAndSettle();
      await capture('manage-data');
      await tester.tap(find.text('Manual expenses'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('deleteSelectedData')));
      await tester.tap(find.byKey(const Key('deleteSelectedData')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await repo.slips(), hasLength(3));
      await tester.tap(find.byKey(const Key('deleteSelectedData')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect((await repo.slips()).where((s) => s.isManualExpense), isEmpty);
      expect(await repo.slips(), hasLength(2));
      // A complete explicit expense scan returns to Overview with updated totals.
      gallery.ids = ['quick-expense'];
      ocr.confidence = .99;
      ocr.text = ocr.text
          .replaceAll('144,000.00', '100,000.00')
          .replaceAll('90000000000000000001', '90000000000000000002');
      await tester.tap(find.byKey(const ValueKey('nav:/scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pickReceipts')));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(totalsFor(await repo.slips())['MMK']!.expense, 24400000);
      expect(
        (await repo.slips())
            .where((s) => s.source == 'quick-expense')
            .single
            .review,
        ReviewStatus.confirmed,
      );

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
