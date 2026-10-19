import 'exchange_rate.dart';
import 'models.dart';

/// Spending against a monthly category budget, in THB hundredths.
class BudgetStatus {
  const BudgetStatus(this.category, this.limit, this.spent);
  final String category;
  final int limit, spent;
  double get ratio => limit <= 0 ? 0 : spent / limit;
  int get remaining => limit - spent;

  /// 0 = fine, 1 = 80% used, 2 = over budget.
  int get tier => ratio >= 1
      ? 2
      : ratio >= .8
      ? 1
      : 0;
}

Map<String, int> budgetLimits(Map<String, dynamic> settings) => {
  for (final e in Map<String, dynamic>.from(
    settings['categoryBudgets'] ?? const {},
  ).entries)
    if (e.value is int && e.value > 0) e.key: e.value as int,
};

/// Budget progress for the calendar month containing [month].
List<BudgetStatus> budgetStatus(
  Iterable<Slip> slips,
  Map<String, int> limits,
  DateTime month,
  int rateMicros,
) {
  final spent = <String, int>{};
  for (final s in slips) {
    if (s.direction != Direction.expense ||
        s.review != ReviewStatus.confirmed ||
        s.amountMinor == null ||
        s.date == null ||
        s.date!.year != month.year ||
        s.date!.month != month.month) {
      continue;
    }
    final thb = s.currency == 'MMK'
        ? mmkToThbMinor(s.amountMinor!, rateMicros)
        : s.amountMinor!;
    spent.update(s.category, (n) => n + thb, ifAbsent: () => thb);
  }
  return [
    for (final e in limits.entries)
      BudgetStatus(e.key, e.value, spent[e.key] ?? 0),
  ]..sort((a, b) => b.ratio.compareTo(a.ratio));
}
