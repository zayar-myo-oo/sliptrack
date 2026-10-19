import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/data_groups.dart';
import 'package:sliptrack/core/income_cycle.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/database/database.dart';
import 'package:sliptrack/features/gallery_scanner/scan_controller.dart';
import 'coach_test.dart' show memoryRepo, income, expense, savings;
import 'pipeline_test.dart' show FakeGallery, FakeOcr;

Slip manualExpense(DateTime date, int minor) => Slip(
  id: newId(),
  isManualExpense: true,
  date: date,
  amountMinor: minor,
  direction: Direction.expense,
  review: ReviewStatus.confirmed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Repository repo;
  setUp(() {
    repo = memoryRepo();
  });
  tearDown(() => repo.close());
  test(
    'Sep 25 income remains available through Oct 24, manual expenses affect that cycle',
    () async {
      final cycle = IncomeCycle.at(DateTime(2026, 10, 24));
      await repo.saveSlip(income(DateTime(2026, 9, 25), 1000000));
      await repo.saveSlip(manualExpense(DateTime(2026, 10, 1), 25000));
      await repo.saveSlip(manualExpense(DateTime(2026, 10, 24, 23, 59), 10000));
      await repo.saveSlip(manualExpense(DateTime(2026, 10, 25), 99999));
      final records = await repo.slips();
      final totals = totalsFor(records.where((s) => cycle.contains(s.date)));
      expect(totals['THB']!.income, 1000000);
      expect(totals['THB']!.expense, 35000);
      expect(totals['THB']!.net, 965000);
      expect(cycle.hasIncome(records), true);
      expect(IncomeCycle.at(DateTime(2026, 10, 25)).hasIncome(records), false);
      expect(records.where((s) => s.isManualExpense), hasLength(3));
      final oldJson = records.first.toJson()..remove('isManualExpense');
      expect(Slip.fromJson(oldJson).isManualExpense, false);
    },
  );
  test(
    'selected expense deletion preserves salary, receipts and other cycles',
    () async {
      final cycle = IncomeCycle.at(DateTime(2026, 10, 19));
      await repo.saveSlip(income(cycle.start, 100000));
      await repo.saveSlip(manualExpense(DateTime(2026, 10, 1), 1000));
      await repo.saveSlip(manualExpense(cycle.end, 2000));
      await repo.saveSlip(expense(DateTime(2026, 10, 2), 3000));
      final counts = await repo.dataCounts(start: cycle.start, end: cycle.end);
      expect(counts[DataGroup.expenses], 1);
      expect(counts[DataGroup.income], 1);
      expect(
        await repo.deleteData(
          {DataGroup.expenses},
          start: cycle.start,
          end: cycle.end,
        ),
        1,
      );
      final records = await repo.slips();
      expect(records, hasLength(3));
      expect(cycle.hasIncome(records), true);
      expect(records.singleWhere((s) => s.isManualExpense).date, cycle.end);
      await expectLater(
        repo.deleteData({DataGroup.income}, start: cycle.start),
        throwsArgumentError,
      );
    },
  );
  test(
    'deleting imported records also clears their duplicate indexes and queue for re-import',
    () async {
      final scanner = ScanController(
        repo,
        FakeGallery(),
        FakeOcr(),
        requireIncome: false,
      );
      addTearDown(scanner.dispose);
      await scanner.pick();
      expect((await repo.slips()).length, 1);
      expect(await repo.deleteData({DataGroup.receipts}), 1);
      expect(await repo.records('queue'), isEmpty);
      expect(await repo.existingSlipId(source: 'asset-a'), isNull);
      await scanner.pick();
      expect((await repo.slips()).length, 1);
    },
  );
  test(
    'deleting savings separately retains earned cat rewards and financial records',
    () async {
      await repo.saveSavings(savings(500000 * 10));
      await repo.saveSlip(income(DateTime(2026, 9, 25), 100000));
      await repo.patchSettings({'language': 'my', 'budgetAlertsEnabled': true});
      expect(await repo.deleteData({DataGroup.savings}), 1);
      expect(await repo.savings(), isEmpty);
      expect((await repo.petProgress()).level, 10);
      expect((await repo.petProgress()).outfitsUnlocked, 1);
      expect((await repo.slips()).single.isManualIncome, true);
      expect((await repo.settings())['language'], 'my');
      expect((await repo.settings())['budgetAlertsEnabled'], true);
    },
  );
}
