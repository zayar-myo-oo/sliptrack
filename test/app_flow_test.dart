import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sliptrack/app/app.dart';
import 'package:sliptrack/app/state.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/core/vault.dart';
import 'package:sliptrack/database/database.dart';
import 'package:sliptrack/features/gallery_scanner/scan_controller.dart';
import 'pipeline_test.dart' show FakeGallery, FakeOcr, synthetic;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // The companion intentionally animates continuously. Exercise its
    // reduced-motion mode so navigation can settle in these flow tests.
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });
  testWidgets(
    'mobile dashboard, transaction review and confirm update actual totals',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.sliptrack/media'),
            (call) async => null,
          );
      final repo = Repository(
        SlipDatabase(NativeDatabase.memory()),
        Vault(List.generate(32, (i) => i)),
      );
      final scanner = ScanController(
        repo,
        FakeGallery(),
        FakeOcr(),
        requireIncome: false,
      );
      addTearDown(repo.close);
      final prefs = Preferences(repo, {'onboarded': true});
      final slip = synthetic()
        ..date = DateTime.now()
        ..receiver = 'Sample training class'
        ..source = '';
      await repo.importSlip(slip);
      // Use the real bundled font for an inspectable UI capture when present locally.
      final fontFile = File(
        '.tooling/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      );
      if (fontFile.existsSync()) {
        final loader = FontLoader('Roboto')
          ..addFont(
            Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
          );
        await loader.load();
      }
      final capture = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            preferencesProvider.overrideWithValue(prefs),
            scannerProvider.overrideWithValue(scanner),
          ],
          child: RepaintBoundary(key: capture, child: const SlipTrackApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SlipTrack'), findsOneWidget);
      expect(find.textContaining('0.00 THB'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample training class'));
      await tester.pumpAndSettle();
      expect(find.text('Review receipt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Direction'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose direction').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Money out').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Confirm transaction'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Confirm transaction'));
      await tester.pumpAndSettle();
      expect((await repo.slips()).single.review, ReviewStatus.confirmed);
      expect(
        totalsFor(await repo.slips(), month: DateTime.now())['MMK']!.expense,
        14400000,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      scanner.dispose();
    },
  );
  testWidgets(
    'main isolates each month while transaction history combines months',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = Repository(
        SlipDatabase(NativeDatabase.memory()),
        Vault(List.generate(32, (i) => i)),
      );
      addTearDown(repo.close);
      final scanner = ScanController(
        repo,
        FakeGallery(),
        FakeOcr(),
        requireIncome: false,
      );
      final prefs = Preferences(repo, {'onboarded': true});
      final now = DateTime.now();
      final current = synthetic(source: 'current', reference: 'CURRENT123')
        ..date = DateTime(now.year, now.month, 5)
        ..amountMinor = 10000
        ..receiver = 'Current-month receipt';
      final previous = synthetic(source: 'previous', reference: 'PREVIOUS123')
        ..date = DateTime(now.year, now.month - 1, 5)
        ..amountMinor = 20000
        ..receiver = 'Previous-month receipt';
      for (final slip in [current, previous]) {
        await repo.importSlip(slip);
        slip.direction = Direction.expense;
        slip.review = ReviewStatus.confirmed;
        await repo.saveSlip(slip);
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            preferencesProvider.overrideWithValue(prefs),
            scannerProvider.overrideWithValue(scanner),
          ],
          child: const SlipTrackApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('-100.00 MMK'), findsOneWidget);
      expect(find.text('-200.00 MMK'), findsNothing);
      expect(find.text('Current-month receipt'), findsOneWidget);
      expect(find.text('Previous-month receipt'), findsNothing);
      await tester.tap(find.text('Calendar month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('monthPrevious')));
      await tester.pumpAndSettle();
      expect(find.text('-200.00 MMK'), findsOneWidget);
      expect(find.text('-100.00 MMK'), findsNothing);
      expect(find.text('Previous-month receipt'), findsOneWidget);
      expect(find.text('Current-month receipt'), findsNothing);
      await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Current-month receipt'), findsOneWidget);
      expect(find.text('Previous-month receipt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      scanner.dispose();
    },
  );
}
