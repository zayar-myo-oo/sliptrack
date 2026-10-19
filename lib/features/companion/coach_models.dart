import '../../core/exchange_rate.dart';
import '../../core/models.dart';

const defaultSavingsGoalThbMinor = 500000;
const petXpScale = 1000000;

enum PetMood { happy, worried, crying }

class SavingsEntry {
  const SavingsEntry({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.date,
    required this.thbEquivalentMinor,
    required this.rateMicros,
    required this.goalThbMinor,
    required this.xpMicros,
    this.note = '',
  });
  final String id, currency, note;
  final int amountMinor, thbEquivalentMinor, rateMicros, goalThbMinor, xpMicros;
  final DateTime date;
  Map<String, dynamic> toJson() => {
    'id': id,
    'amountMinor': amountMinor,
    'currency': currency,
    'date': date.toIso8601String(),
    'thbEquivalentMinor': thbEquivalentMinor,
    'rateMicros': rateMicros,
    'goalThbMinor': goalThbMinor,
    'xpMicros': xpMicros,
    'note': note,
  };
  factory SavingsEntry.fromJson(Map<String, dynamic> j) => SavingsEntry(
    id: j['id'],
    amountMinor: j['amountMinor'],
    currency: j['currency'],
    date: DateTime.parse(j['date']),
    thbEquivalentMinor: j['thbEquivalentMinor'],
    rateMicros: j['rateMicros'],
    goalThbMinor: j['goalThbMinor'],
    xpMicros: j['xpMicros'],
    note: j['note'] ?? '',
  );
  factory SavingsEntry.create({
    required int amountMinor,
    required String currency,
    required DateTime date,
    required int rateMicros,
    required int goalThbMinor,
    String note = '',
  }) {
    if (amountMinor <= 0 ||
        rateMicros <= 0 ||
        goalThbMinor <= 0 ||
        !['THB', 'MMK'].contains(currency)) {
      throw ArgumentError('Invalid savings');
    }
    final thb = currency == 'MMK'
        ? mmkToThbMinor(amountMinor, rateMicros)
        : amountMinor;
    final xp =
        BigInt.from(thb) * BigInt.from(petXpScale) ~/ BigInt.from(goalThbMinor);
    if (xp > BigInt.parse('9223372036854775807')) {
      throw RangeError('Savings XP exceeds range');
    }
    return SavingsEntry(
      id: newId(),
      amountMinor: amountMinor,
      currency: currency,
      date: date,
      thbEquivalentMinor: thb,
      rateMicros: rateMicros,
      goalThbMinor: goalThbMinor,
      xpMicros: xp.toInt(),
      note: note,
    );
  }
}

class BudgetLife {
  BudgetLife({required this.income, required this.expenses});
  final int income, expenses;
  int get remaining => income - expenses;
  int get lifePercent => income <= 0
      ? 0
      : (BigInt.from(remaining.clamp(0, income)) *
                BigInt.from(100) ~/
                BigInt.from(income))
            .toInt()
            .clamp(0, 100);
  int get alertTier => income <= 0
      ? 0
      : expenses >= income
      ? 2
      : BigInt.from(expenses) * BigInt.from(100) >=
            BigInt.from(income) * BigInt.from(80)
      ? 1
      : 0;
  PetMood get mood => remaining <= 0
      ? PetMood.crying
      : alertTier > 0
      ? PetMood.worried
      : PetMood.happy;
  factory BudgetLife.fromTotals(
    Map<String, Totals> totals,
    int rate, {
    int reserve = 0,
  }) {
    final estimate = estimateInThb(totals, rate);
    return BudgetLife(
      income: estimate.income - reserve,
      expenses: estimate.expense,
    );
  }
}

class PetProgress {
  PetProgress({required this.xpMicros, required this.highestMilestones});
  final int xpMicros, highestMilestones;
  int get reachedMilestones => xpMicros ~/ petXpScale;
  int get earnedMilestones => reachedMilestones > highestMilestones
      ? reachedMilestones
      : highestMilestones;
  int get level => (1 + earnedMilestones).clamp(1, 10);
  int get outfitsUnlocked => (earnedMilestones - 9).clamp(0, 1000000000);
  double get nextRewardProgress => reachedMilestones < highestMilestones
      ? 0
      : (xpMicros % petXpScale) / petXpScale;
  double get bodyScale => 0.60 + (level - 1) * 0.04;
}
