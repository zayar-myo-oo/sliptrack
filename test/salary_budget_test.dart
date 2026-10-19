import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/income_cycle.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/core/exchange_rate.dart';
import 'package:sliptrack/features/companion/coach_models.dart';
import 'package:sliptrack/features/slip_recognition/parsers.dart';
import 'coach_test.dart' show memoryRepo, income, expense;

void main() {
  test(
    'salary stays open past the 25th until actual next salary; extra income does not reset',
    () {
      final salary = income(DateTime(2026, 9, 25), 2000000)
        ..savingsReserveMinor = 500000;
      final extra = income(DateTime(2026, 10, 5), 100000)
        ..category = 'Extra income';
      final records = [salary, extra, expense(DateTime(2026, 10, 26), 300000)];
      final open = IncomeCycle.fromIncome(DateTime(2026, 10, 26), records);
      expect(open.start, DateTime(2026, 9, 25));
      expect(open.isOpen, true);
      expect(open.reserveThb(records, defaultMmkPerThbMicros), 500000);
      final available = BudgetLife.fromTotals(
        totalsFor(records),
        defaultMmkPerThbMicros,
        reserve: 500000,
      );
      expect(available.remaining, 1300000);
      records.add(income(DateTime(2026, 10, 27), 2200000));
      final old = IncomeCycle.fromIncome(DateTime(2026, 10, 26), records);
      expect(old.end, DateTime(2026, 10, 27));
      expect(old.contains(DateTime(2026, 10, 27)), false);
      final current = IncomeCycle.fromIncome(DateTime(2026, 10, 27), records);
      expect(current.start, DateTime(2026, 10, 27));
      expect(
        totalsFor(
          records.where((s) => current.contains(s.date)),
        )['THB']!.expense,
        0,
      );
    },
  );
  test(
    'reserved goal persists encrypted and does not become actual savings',
    () async {
      final repo = memoryRepo();
      addTearDown(repo.close);
      final salary = income(DateTime(2026, 9, 25), 2000000)
        ..savingsReserveMinor = 500000;
      await repo.saveSlip(salary);
      final restored = (await repo.slips()).single;
      expect(restored.savingsReserveMinor, 500000);
      expect(await repo.savings(), isEmpty);
      salary.savingsReserveMinor = 2000001;
      await expectLater(repo.saveSlip(salary), throwsArgumentError);
    },
  );
  test('OCR column ordering does not prevent timestamp binding', () {
    final slip = SlipRecognizer().parse('''KBZ BANK
Transaction Time
Transaction No
Transfer To
17/10/2026 10:27:01
90000000000000000001
SAMPLE RECEIVER
-144,000.00 Ks''')!;
    expect(slip.date, DateTime(2026, 10, 17, 10, 27, 1));
    expect(slip.reference, '90000000000000000001');
    expect(slip.amountMinor, 14400000);
  });
  test('Thai Buddhist year and split date/time are preserved', () {
    expect(
      parseSlipDate('18 Oct 2569\n13 : 30 : 15'),
      DateTime(2026, 10, 18, 13, 30, 15),
    );
    expect(parseSlipDate('31/02/2026 10:00:00'), isNull);
  });
}
