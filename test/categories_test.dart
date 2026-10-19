import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/budgets.dart';
import 'package:sliptrack/core/categories.dart';
import 'package:sliptrack/core/models.dart';

Slip expense(String receiver, {int amount = 10000, String? category}) => Slip(
  id: receiver,
  receiver: receiver,
  amountMinor: amount,
  date: DateTime(2026, 10, 5),
  direction: Direction.expense,
  review: ReviewStatus.confirmed,
  category: category ?? uncategorized,
);

void main() {
  test('keyword rules sort common merchants', () {
    expect(guessCategory(expense('7-Eleven Silom'), {}), 'Food');
    expect(guessCategory(expense('GRAB TAXI'), {}), 'Transport');
    expect(guessCategory(expense('Shopee Pay'), {}), 'Shopping');
    expect(guessCategory(expense('Somchai K.'), {}), isNull);
  });

  test('remembered receiver wins over keywords', () {
    final memory = {merchantKey('Grab Taxi'): 'Bills'};
    expect(guessCategory(expense('grab  taxi'), memory), 'Bills');
  });

  test('income is never auto-categorized', () {
    final s = expense('7-Eleven')..direction = Direction.income;
    expect(guessCategory(s, {}), isNull);
  });

  test('budget tiers at 80% and 100%', () {
    final slips = [
      expense('a', amount: 8500, category: 'Food'),
      expense('b', amount: 12000, category: 'Transport'),
    ];
    final status = {
      for (final b in budgetStatus(
        slips,
        {'Food': 10000, 'Transport': 10000, 'Bills': 10000},
        DateTime(2026, 10),
        133000000,
      ))
        b.category: b.tier,
    };
    expect(status, {'Transport': 2, 'Food': 1, 'Bills': 0});
  });
}
