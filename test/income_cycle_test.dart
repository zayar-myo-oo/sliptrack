import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/income_cycle.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/features/gallery_scanner/scan_controller.dart';
import 'coach_test.dart' show memoryRepo, income, expense;
import 'pipeline_test.dart' show FakeGallery, FakeOcr;

class CountingGallery extends FakeGallery {
  int picks = 0;
  @override
  Future<List<String>> pick() async {
    picks++;
    return super.pick();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '25th is inclusive, next 25th exclusive, including year and leap boundaries',
    () {
      final cycle = IncomeCycle.at(DateTime(2026, 10, 24));
      expect(cycle.start, DateTime(2026, 9, 25));
      expect(cycle.end, DateTime(2026, 10, 25));
      expect(cycle.contains(DateTime(2026, 9, 24, 23, 59)), false);
      expect(cycle.contains(DateTime(2026, 9, 25)), true);
      expect(cycle.contains(DateTime(2026, 10, 24, 23, 59, 59)), true);
      expect(cycle.contains(DateTime(2026, 10, 25)), false);
      expect(cycle.contains(null), false);
      expect(
        IncomeCycle.at(DateTime(2026, 10, 25)).start,
        DateTime(2026, 10, 25),
      );
      expect(
        IncomeCycle.at(DateTime(2027, 1, 1)).start,
        DateTime(2026, 12, 25),
      );
      expect(IncomeCycle.at(DateTime(2028, 2, 29)).end, DateTime(2028, 3, 25));
    },
  );

  test(
    'picker and queued/shared OCR require confirmed manual income in active cycle',
    () async {
      final repo = memoryRepo();
      addTearDown(repo.close);
      final gallery = CountingGallery(), ocr = FakeOcr();
      var now = DateTime(2026, 10, 24, 23, 59);
      final scanner = ScanController(repo, gallery, ocr, now: () => now);
      addTearDown(scanner.dispose);
      await scanner.pick();
      expect(scanner.needsIncome, true);
      expect(gallery.picks, 0);
      expect(ocr.calls, 0);
      await scanner.enqueue(['shared-photo'], manual: true);
      final pendingIncome = income(DateTime(2026, 9, 25), 100000)
        ..review = ReviewStatus.pending;
      await repo.saveSlip(pendingIncome);
      await scanner.pick();
      expect(gallery.picks, 0);
      pendingIncome.review = ReviewStatus.confirmed;
      await repo.saveSlip(pendingIncome);
      await scanner.process();
      expect(ocr.calls, 1);
      expect(scanner.needsIncome, false);
      now = DateTime(2026, 10, 25);
      await scanner.pick();
      expect(gallery.picks, 1);
      expect(scanner.needsIncome, false);
      await repo.saveSlip(income(now, 200000));
      await scanner.pick();
      expect(gallery.picks, 2);
      expect(ocr.calls, 2);
      expect(scanner.lastPickedReviewIds, hasLength(1));
    },
  );

  test('spending and extra income stay inside the same fixed cycle', () {
    final cycle = IncomeCycle.at(DateTime(2026, 10, 10));
    final records = [
      income(DateTime(2026, 9, 25), 100000),
      income(DateTime(2026, 10, 5), 20000)..category = 'Extra income',
      expense(DateTime(2026, 10, 24, 23, 59), 30000),
      expense(DateTime(2026, 10, 25), 99999),
      income(DateTime(2026, 10, 25), 500000),
    ];
    final totals = totalsFor(records.where((s) => cycle.contains(s.date)));
    expect(totals['THB']!.income, 120000);
    expect(totals['THB']!.expense, 30000);
    expect(totals['THB']!.net, 90000);
    expect(cycle.hasIncome(records), true);
  });
}
