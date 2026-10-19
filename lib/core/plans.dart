import 'income_cycle.dart';
import 'models.dart';

/// Savings goals, recurring bills and debts live in the encrypted settings
/// record as small JSON lists, so they travel with encrypted backups.
class SavingsGoal {
  SavingsGoal({
    required this.id,
    required this.name,
    required this.targetMinor,
    this.savedMinor = 0,
    this.emoji = '🎯',
  });
  final String id;
  String name, emoji;
  int targetMinor, savedMinor;
  double get ratio => targetMinor <= 0 ? 0 : savedMinor / targetMinor;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'targetMinor': targetMinor,
    'savedMinor': savedMinor,
    'emoji': emoji,
  };
  factory SavingsGoal.fromJson(Map j) => SavingsGoal(
    id: j['id'],
    name: j['name'] ?? '',
    targetMinor: j['targetMinor'] ?? 0,
    savedMinor: j['savedMinor'] ?? 0,
    emoji: j['emoji'] ?? '🎯',
  );
}

class RecurringBill {
  RecurringBill({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.currency,
    required this.category,
    required this.day,
    this.autoAdd = true,
    this.lastPosted = '',
  });
  final String id;
  String name, currency, category, lastPosted;
  int amountMinor, day;
  bool autoAdd;

  /// The due date in the month of [month], clamped to the month's length.
  DateTime dueIn(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, day.clamp(1, last));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amountMinor': amountMinor,
    'currency': currency,
    'category': category,
    'day': day,
    'autoAdd': autoAdd,
    'lastPosted': lastPosted,
  };
  factory RecurringBill.fromJson(Map j) => RecurringBill(
    id: j['id'],
    name: j['name'] ?? '',
    amountMinor: j['amountMinor'] ?? 0,
    currency: j['currency'] ?? 'THB',
    category: j['category'] ?? 'Bills',
    day: j['day'] ?? 1,
    autoAdd: j['autoAdd'] ?? true,
    lastPosted: j['lastPosted'] ?? '',
  );
}

class Debt {
  Debt({
    required this.id,
    required this.person,
    required this.amountMinor,
    required this.currency,
    required this.lent,
    this.due,
    this.note = '',
    this.settled = false,
  });
  final String id;
  String person, currency, note;
  int amountMinor;

  /// True when the user lent money out; false when they borrowed it.
  bool lent, settled;
  DateTime? due;
  bool get overdue => !settled && due != null && due!.isBefore(DateTime.now());
  Map<String, dynamic> toJson() => {
    'id': id,
    'person': person,
    'amountMinor': amountMinor,
    'currency': currency,
    'lent': lent,
    'due': due?.toIso8601String(),
    'note': note,
    'settled': settled,
  };
  factory Debt.fromJson(Map j) => Debt(
    id: j['id'],
    person: j['person'] ?? '',
    amountMinor: j['amountMinor'] ?? 0,
    currency: j['currency'] ?? 'THB',
    lent: j['lent'] ?? true,
    due: DateTime.tryParse(j['due'] ?? ''),
    note: j['note'] ?? '',
    settled: j['settled'] ?? false,
  );
}

List<T> readList<T>(
  Map<String, dynamic> settings,
  String key,
  T Function(Map) parse,
) => [for (final j in (settings[key] as List? ?? const [])) parse(j as Map)];

String monthKey(DateTime d) => '${d.year}-${d.month}';

/// Recurring bills that are due on or before [now] this month and have not
/// been added yet.
List<RecurringBill> billsToPost(List<RecurringBill> bills, DateTime now) => [
  for (final b in bills)
    if (b.autoAdd &&
        b.lastPosted != monthKey(now) &&
        !b.dueIn(now).isAfter(now))
      b,
];

Slip slipForBill(RecurringBill b, DateTime now) => Slip(
  id: newId(),
  isManualExpense: true,
  amountMinor: b.amountMinor,
  currency: b.currency,
  date: b.dueIn(now),
  zone: b.currency == 'MMK' ? 'Asia/Yangon' : 'Asia/Bangkok',
  direction: Direction.expense,
  review: ReviewStatus.confirmed,
  category: b.category,
  type: 'Manual expense',
  receiver: b.name,
  description: 'Recurring',
);

/// How much can be spent per day until the next salary, in THB hundredths.
class DailyAllowance {
  const DailyAllowance(this.perDay, this.daysLeft);
  final int perDay, daysLeft;
  static DailyAllowance? of(IncomeCycle cycle, int availableThb, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    var end = cycle.end;
    if (end.year == 9999 || cycle.isOpen) {
      end = DateTime(cycle.start.year, cycle.start.month + 1, cycle.start.day);
    }
    final days = end.difference(today).inDays;
    if (days <= 0) return null;
    return DailyAllowance(availableThb <= 0 ? 0 : availableThb ~/ days, days);
  }
}

/// Consecutive days, ending yesterday, on which spending stayed within the
/// even daily share of this cycle's income.
int spendingStreak(
  List<Slip> slips,
  int dailyLimitThb,
  DateTime now,
  int Function(Slip) toThb,
) {
  if (dailyLimitThb <= 0) return 0;
  final spent = <DateTime, int>{};
  for (final s in slips) {
    if (s.direction != Direction.expense ||
        s.review != ReviewStatus.confirmed ||
        s.date == null ||
        s.amountMinor == null) {
      continue;
    }
    final d = DateTime(s.date!.year, s.date!.month, s.date!.day);
    spent.update(d, (n) => n + toThb(s), ifAbsent: () => toThb(s));
  }
  var day = DateTime(now.year, now.month, now.day - 1);
  var streak = 0;
  while (streak < 366 && (spent[day] ?? 0) <= dailyLimitThb) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
    if (spent.keys.every((d) => d.isAfter(day))) break;
  }
  return streak;
}
