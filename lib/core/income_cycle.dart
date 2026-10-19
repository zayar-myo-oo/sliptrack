import 'models.dart';
import 'exchange_rate.dart';

/// Salary periods follow recorded salary dates. The legacy fixed-date
/// constructor remains for older callers; app screens use fromIncome.
class IncomeCycle {
  IncomeCycle.at(DateTime date)
    : start = DateTime(date.year, date.month - (date.day < 25 ? 1 : 0), 25),
      end = DateTime(date.year, date.month + (date.day < 25 ? 0 : 1), 25);
  IncomeCycle._(this.start, this.end);

  /// Salary entries open periods; extra income belongs to the existing period.
  factory IncomeCycle.fromIncome(DateTime date, Iterable<Slip> slips) {
    final starts =
        slips
            .where(
              (s) =>
                  s.isManualIncome &&
                  s.review == ReviewStatus.confirmed &&
                  (s.category == 'Salary' || s.category == 'Uncategorized') &&
                  s.date != null &&
                  (s.amountMinor ?? 0) > 0,
            )
            .map((s) => DateTime(s.date!.year, s.date!.month, s.date!.day))
            .toSet()
            .toList()
          ..sort();
    final today = DateTime(date.year, date.month, date.day);
    final earlier = starts.where((d) => !d.isAfter(today));
    final start = earlier.isEmpty
        ? DateTime(date.year, date.month)
        : earlier.last;
    final later = starts.where((d) => d.isAfter(today));
    var end = later.isEmpty ? DateTime(9999) : later.first;
    if (earlier.isEmpty) {
      final monthEnd = DateTime(date.year, date.month + 1);
      if (monthEnd.isBefore(end)) end = monthEnd;
    }
    return IncomeCycle._(start, end);
  }
  bool get isOpen => end.year == 9999;
  final DateTime start, end;
  int reserveThb(Iterable<Slip> slips, int rate) => slips
      .where(
        (s) =>
            s.isManualIncome &&
            s.review == ReviewStatus.confirmed &&
            contains(s.date),
      )
      .fold(
        0,
        (sum, s) =>
            sum +
            (s.currency == 'MMK'
                ? mmkToThbMinor(s.savingsReserveMinor, rate)
                : s.savingsReserveMinor),
      );
  bool contains(DateTime? date) =>
      date != null && !date.isBefore(start) && date.isBefore(end);
  String get key =>
      '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  int get notificationId => start.year * 10000 + start.month * 100 + start.day;
  bool hasIncome(Iterable<Slip> slips) => slips.any(
    (s) =>
        s.isManualIncome &&
        s.review == ReviewStatus.confirmed &&
        s.direction == Direction.income &&
        (s.amountMinor ?? 0) > 0 &&
        contains(s.date),
  );
}
