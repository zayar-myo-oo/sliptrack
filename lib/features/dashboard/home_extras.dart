import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/categories.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
import '../../core/plans.dart';
import '../../core/income_cycle.dart';
import '../../shared/components.dart';
import '../../shared/design.dart';
import '../../shared/localized_text.dart';
import '../../shared/motion.dart';
import '../companion/coach_models.dart';
import '../companion/companion_card.dart';
import '../slip_recognition/parsers.dart';

int _thb(Slip s, int rate) => s.currency == 'MMK'
    ? mmkToThbMinor(s.amountMinor ?? 0, rate)
    : s.amountMinor ?? 0;

bool _spend(Slip s) =>
    s.direction == Direction.expense &&
    s.review == ReviewStatus.confirmed &&
    s.date != null &&
    s.amountMinor != null;

/// Shortcuts to goals, bills and debts with live counts.
class PlansStrip extends ConsumerWidget {
  const PlansStrip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(preferencesProvider).values;
    final goals = readList(v, 'goals', SavingsGoal.fromJson);
    final bills = readList(v, 'recurring', RecurringBill.fromJson);
    final debts = readList(
      v,
      'debts',
      Debt.fromJson,
    ).where((d) => !d.settled).toList();
    final items = [
      (
        Icons.flag_rounded,
        'Goals',
        goals.isEmpty
            ? tr(context, 'Start saving')
            : '${(goals.fold<double>(0, (n, g) => n + g.ratio.clamp(0, 1)) / goals.length * 100).round()}%',
        const Color(0xff2e8b57),
        0,
      ),
      (
        Icons.event_repeat_rounded,
        'Bills',
        '${bills.length}',
        const Color(0xff8a79c9),
        1,
      ),
      (
        Icons.handshake_outlined,
        'Debts',
        debts.any((d) => d.overdue) ? '⚠️ ${debts.length}' : '${debts.length}',
        const Color(0xffe0874b),
        2,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (final i in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Pressable(
                  child: Material(
                    color: i.$4.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.push('/plans?tab=${i.$5}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(i.$1, color: i.$4, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LText(
                                    i.$2,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    i.$3,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Palette.muted(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Long-press "Add expense" for a two-tap entry: amount and category.
Future<void> showQuickAdd(BuildContext context, WidgetRef ref) async {
  HapticFeedback.mediumImpact();
  final amount = TextEditingController();
  var currency = 'THB', category = 'Food';
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(c).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LText('Quick expense', style: Theme.of(c).textTheme.titleLarge),
            TextField(
              controller: amount,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w700,
                color: Palette.expense,
              ),
              decoration: InputDecoration(
                hintText: '0',
                filled: false,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                suffixText: currency,
              ),
            ),
            Center(
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final x in ['THB', 'MMK'])
                    ButtonSegment(value: x, label: Text(x)),
                ],
                selected: {currency},
                onSelectionChanged: (v) => set(() => currency = v.first),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final cat in expenseCategories)
                  ChoiceChip(
                    avatar: Icon(cat.icon, size: 16, color: cat.color),
                    label: LText(cat.name),
                    showCheckmark: false,
                    selected: category == cat.name,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      set(() => category = cat.name);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const LText('Save expense'),
            ),
          ],
        ),
      ),
    ),
  );
  final minor = parseMinor(amount.text.trim()) ?? 0;
  amount.dispose();
  if (saved != true || minor <= 0) return;
  await ref
      .read(repositoryProvider)
      .saveSlip(
        Slip(
          id: newId(),
          isManualExpense: true,
          amountMinor: minor,
          currency: currency,
          date: DateTime.now(),
          zone: currency == 'MMK' ? 'Asia/Yangon' : 'Asia/Bangkok',
          direction: Direction.expense,
          review: ReviewStatus.confirmed,
          category: category,
          type: 'Manual expense',
          receiver: category,
        ),
      );
  HapticFeedback.heavyImpact();
  if (context.mounted) message(context, tr(context, 'Expense saved'));
}

/// Shown during the first week of a month: a recap of the previous month.
class RecapBanner extends ConsumerWidget {
  const RecapBanner({required this.slips, super.key});
  final List<Slip> slips;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1);
    final key = monthKey(last);
    if (now.day > 7 || prefs.values['recapSeen'] == key) {
      return const SizedBox.shrink();
    }
    final rate = prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros;
    bool inMonth(Slip s, DateTime m) =>
        s.date!.year == m.year && s.date!.month == m.month;
    if (!slips.any((s) => _spend(s) && inMonth(s, last))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Surface(
        color: const Color(0xffffcf5a).withValues(alpha: .22),
        onTap: () => _showRecap(context, ref, last, rate),
        child: Row(
          children: [
            const Text('📬', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${tr(context, 'Your recap for')} ${DateFormat.MMMM(prefs.locale.languageCode).format(last)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecap(
    BuildContext context,
    WidgetRef ref,
    DateTime month,
    int rate,
  ) async {
    final prefs = ref.read(preferencesProvider);
    final coach = ref.read(coachProvider);
    final prev = DateTime(month.year, month.month - 1);
    int total(DateTime m) => slips
        .where(
          (s) =>
              _spend(s) && s.date!.year == m.year && s.date!.month == m.month,
        )
        .fold(0, (n, s) => n + _thb(s, rate));
    final spent = total(month), before = total(prev);
    final byCat = <String, int>{};
    for (final s in slips.where(
      (s) =>
          _spend(s) &&
          s.date!.year == month.year &&
          s.date!.month == month.month,
    )) {
      byCat.update(
        s.category,
        (n) => n + _thb(s, rate),
        ifAbsent: () => _thb(s, rate),
      );
    }
    final top = byCat.entries.isEmpty
        ? null
        : (byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first;
    final change = before == 0 ? null : (spent - before) * 100 / before;
    final happy = change == null || change <= 0;
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Buddy(
                  mood: happy ? PetMood.happy : PetMood.worried,
                  progress: coach.progress,
                  outfit: coach.outfit,
                ),
              ),
              Text(
                DateFormat.yMMMM(prefs.locale.languageCode).format(month),
                style: Theme.of(c).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              CountUpMoney(
                spent,
                'THB',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              LText(
                'spent in total',
                style: TextStyle(color: Palette.muted(c)),
              ),
              const SizedBox(height: 16),
              if (change != null)
                _RecapLine(
                  happy ? '🎉' : '📈',
                  '${change.abs().round()}% ${tr(c, happy ? 'less than the month before' : 'more than the month before')}',
                ),
              if (top != null)
                _RecapLine(
                  categoryStyle(top.key).name == uncategorized ? '🏷️' : '🏆',
                  '${tr(c, 'Most spent on')} ${tr(c, top.key)} · ${money(top.value, 'THB')}',
                ),
              _RecapLine(
                '🐱',
                tr(
                  c,
                  happy
                      ? 'Great job! Let’s keep it up this month.'
                      : 'Let’s set a budget and try again this month.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(c),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const LText('Done'),
              ),
            ],
          ),
        ),
      ),
    );
    await prefs.update('recapSeen', monthKey(month));
  }
}

class _RecapLine extends StatelessWidget {
  const _RecapLine(this.icon, this.text);
  final String icon, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// A short tip from the cat, based on how this pay cycle is going.
String catTip(
  BuildContext context, {
  required BudgetLife life,
  required DailyAllowance? allowance,
  required int streak,
  required int spentToday,
}) {
  final tips = <String>[
    if (life.mood == PetMood.crying)
      tr(
        context,
        'We’re over this pay cycle’s income. Only the essentials, okay?',
      ),
    if (life.mood == PetMood.worried)
      tr(context, 'Most of this cycle’s money is used. Let’s go slow.'),
    if (allowance != null && spentToday > allowance.perDay)
      tr(context, 'Today went over your daily amount. Tomorrow we try again!'),
    if (allowance != null && spentToday <= allowance.perDay)
      '${tr(context, 'You can still spend')} ${money(allowance.perDay - spentToday, 'THB')} ${tr(context, 'today')}.',
    if (streak >= 3)
      '🔥 $streak ${tr(context, 'days in a row within budget!')}',
    tr(context, 'Feed me your slips!'),
    tr(context, 'Saving a little every day adds up.'),
  ];
  return tips[DateTime.now().second % tips.length];
}

/// Speech bubble that pops up next to the cat, then fades away.
void showCatBubble(BuildContext context, String text) {
  final overlay = Overlay.of(context);
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return;
  final origin = box.localToGlobal(Offset.zero);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: origin.dy + box.size.height + 4,
      right: 16,
      left: 60,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.medium,
          curve: Curves.easeOutBack,
          builder: (_, t, child) => Opacity(
            opacity: t.clamp(0, 1),
            child: Transform.scale(
              scale: .8 + .2 * t,
              alignment: Alignment.topRight,
              child: child,
            ),
          ),
          child: Material(
            elevation: 6,
            color: Palette.surface(context),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

/// Current within-budget streak, using the same daily share as Overview.
int currentStreak(List<Slip> all, Map<String, dynamic> settings) {
  final rate = settings['mmkPerThbMicros'] ?? defaultMmkPerThbMicros;
  final cycle = IncomeCycle.fromIncome(DateTime.now(), all);
  if (!cycle.hasIncome(all)) return 0;
  final inCycle = all.where((s) => cycle.contains(s.date)).toList();
  final reserve = cycle.reserveThb(inCycle, rate);
  final allowance = DailyAllowance.of(
    cycle,
    estimateInThb(totalsFor(inCycle), rate).net - reserve,
    DateTime.now(),
  );
  if (allowance == null) return 0;
  return spendingStreak(
    all,
    allowance.perDay,
    DateTime.now(),
    (s) => _thb(s, rate),
  );
}

const streakBadges = [
  (3, '🌱', 'Sprout'),
  (7, '🔥', 'One week'),
  (14, '⭐', 'Two weeks'),
  (30, '🏆', 'Money master'),
];

/// Earned streak badges, remembered so they stay unlocked.
class StreakBadges extends ConsumerWidget {
  const StreakBadges({required this.slips, super.key});
  final List<Slip> slips;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final streak = currentStreak(slips, prefs.values);
    final best = (prefs.values['bestStreak'] as int? ?? 0);
    if (streak > best) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => prefs.update('bestStreak', streak),
      );
    }
    final record = streak > best ? streak : best;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🔥 $streak ${tr(context, 'days in a row within budget!')}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final b in streakBadges)
                Expanded(
                  child: Opacity(
                    opacity: record >= b.$1 ? 1 : .3,
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: record >= b.$1
                                ? const Color(0xffffcf5a).withValues(alpha: .3)
                                : Palette.soft(context),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            b.$2,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(height: 4),
                        LText(
                          b.$3,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          '${b.$1} ${tr(context, 'days')}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Palette.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
