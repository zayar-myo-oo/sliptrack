import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/exchange_rate.dart';
import 'package:sliptrack/core/models.dart';

void main() {
  test('manual MMK per THB rate is exact and rejects invalid values', () {
    expect(parseManualRate('133'), 133000000);
    expect(parseManualRate('133.5'), 133500000);
    expect(formatManualRate(133000000), '133');
    expect(formatManualRate(133500000), '133.5');
    for (final bad in ['0', '-133', 'abc', '133.1234567', '133,5']) {
      expect(parseManualRate(bad), isNull);
    }
  });
  test(
    '133 MMK per THB converts original minor units with explicit rounding',
    () {
      expect(mmkToThbMinor(14400000, defaultMmkPerThbMicros), 108271);
      expect(mmkToThbMinor(13300, defaultMmkPerThbMicros), 100);
      expect(mmkToThbMinor(-14400000, defaultMmkPerThbMicros), -108271);
      expect(() => mmkToThbMinor(100, 0), throwsArgumentError);
      expect(() => mmkToThbMinor(9000000000000000, 1), throwsRangeError);
    },
  );
  test('combined estimate preserves original THB and MMK totals', () {
    final original = {
      'THB': Totals()..expense = 63900,
      'MMK': Totals()..expense = 14400000,
    };
    final converted = estimateInThb(original, defaultMmkPerThbMicros);
    expect(converted.expense, 172171);
    expect(converted.net, -172171);
    expect(original['MMK']!.expense, 14400000);
    expect(original['THB']!.expense, 63900);
  });
  test('monthly conversion excludes other months and unconfirmed records', () {
    final thisMonth = Slip(
      id: 'a',
      bank: Bank.kbz,
      currency: 'MMK',
      amountMinor: 14400000,
      date: DateTime(2026, 10, 17),
      review: ReviewStatus.confirmed,
      direction: Direction.expense,
    );
    final prior = Slip(
      id: 'b',
      bank: Bank.trueMoney,
      currency: 'THB',
      amountMinor: 50000,
      date: DateTime(2026, 9, 17),
      review: ReviewStatus.confirmed,
      direction: Direction.income,
    );
    final pending = Slip(
      id: 'c',
      bank: Bank.kbz,
      currency: 'MMK',
      amountMinor: 99900,
      date: DateTime(2026, 10, 18),
      direction: Direction.expense,
    );
    final selected = estimateInThb(
      totalsFor([thisMonth, prior, pending], month: DateTime(2026, 10)),
      defaultMmkPerThbMicros,
    );
    expect(selected.income, 0);
    expect(selected.expense, 108271);
    final allMonths = estimateInThb(
      totalsFor([thisMonth, prior, pending]),
      defaultMmkPerThbMicros,
    );
    expect(allMonths.income, 50000);
    expect(allMonths.expense, 108271);
  });
}
