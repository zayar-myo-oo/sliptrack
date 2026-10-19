import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/csv_export.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/core/plans.dart';

RecurringBill bill(int day, {String last = ''}) => RecurringBill(
  id: 'b$day',
  name: 'Rent',
  amountMinor: 500000,
  currency: 'THB',
  category: 'Bills',
  day: day,
  lastPosted: last,
);

void main() {
  test('bills post once after their due day', () {
    final now = DateTime(2026, 10, 15);
    expect(billsToPost([bill(10), bill(20)], now).map((b) => b.day), [10]);
    expect(billsToPost([bill(10, last: '2026-10')], now), isEmpty);
    // Day 31 clamps to the last day of short months.
    expect(bill(31).dueIn(DateTime(2026, 2)), DateTime(2026, 2, 28));
    final slip = slipForBill(bill(10), now);
    expect(slip.isManualExpense && slip.valid, isTrue);
    expect(slip.date, DateTime(2026, 10, 10));
  });

  test('spending streak counts days within the daily share', () {
    Slip spend(int day, int amount) => Slip(
      id: '$day-$amount',
      amountMinor: amount,
      date: DateTime(2026, 10, day, 12),
      direction: Direction.expense,
      review: ReviewStatus.confirmed,
    );
    final slips = [spend(10, 50000), spend(12, 10000), spend(13, 20000)];
    final streak = spendingStreak(
      slips,
      30000,
      DateTime(2026, 10, 14),
      (s) => s.amountMinor!,
    );
    expect(streak, 3); // 13, 12, 11 are within; 10 is over.
  });

  test('CSV escapes commas and blocks formula injection', () {
    final csv = transactionsCsv([
      Slip(
        id: 'a',
        amountMinor: 12345,
        date: DateTime(2026, 10, 1, 9, 30),
        direction: Direction.expense,
        review: ReviewStatus.confirmed,
        receiver: 'Shop, Silom',
        description: '=HYPERLINK("x")',
      ),
    ]);
    expect(csv.startsWith('﻿Date,Type,Amount'), isTrue);
    expect(csv, contains('"Shop, Silom"'));
    expect(csv, contains('123.45'));
    expect(csv, isNot(contains(',=HYPERLINK')));
  });
}
