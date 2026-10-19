import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../shared/components.dart';
import '../../shared/category_chart.dart';
import '../../shared/design.dart';
import '../../shared/motion.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsState();
}

class _AnalyticsState extends ConsumerState<AnalyticsScreen> {
  String currency = 'THB';

  /// The month being inspected; null shows every month together.
  DateTime? month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(slipsProvider).asData?.value ?? [];
    final usable = all.where(
      (s) =>
          s.currency == currency &&
          s.review == ReviewStatus.confirmed &&
          s.date != null &&
          s.amountMinor != null,
    );
    bool inMonth(Slip s, DateTime m) =>
        s.date!.year == m.year && s.date!.month == m.month;
    final scoped = month == null
        ? usable.toList()
        : usable.where((s) => inMonth(s, month!)).toList();
    final expenses = scoped
        .where((s) => s.direction == Direction.expense)
        .toList();
    final spent = expenses.fold<int>(0, (n, s) => n + s.amountMinor!);
    final earned = scoped
        .where((s) => s.direction == Direction.income)
        .fold<int>(0, (n, s) => n + s.amountMinor!);

    final categories = <String, int>{}, banks = <String, int>{};
    for (final s in expenses) {
      categories.update(
        s.category,
        (n) => n + s.amountMinor!,
        ifAbsent: () => s.amountMinor!,
      );
      banks.update(
        s.bank.label,
        (n) => n + s.amountMinor!,
        ifAbsent: () => s.amountMinor!,
      );
    }

    // Monthly totals across all data, for the comparison chart.
    final monthly = <DateTime, int>{};
    for (final s in usable.where((s) => s.direction == Direction.expense)) {
      final key = DateTime(s.date!.year, s.date!.month);
      monthly.update(
        key,
        (n) => n + s.amountMinor!,
        ifAbsent: () => s.amountMinor!,
      );
    }
    final months = monthly.keys.toList()..sort();
    final recentMonths = months.length > 6
        ? months.sublist(months.length - 6)
        : months;
    final previous = month == null
        ? null
        : monthly[DateTime(month!.year, month!.month - 1)];

    final top = [...expenses]
      ..sort((a, b) => b.amountMinor!.compareTo(a.amountMinor!));
    final locale = ref.watch(preferencesProvider).locale.languageCode;

    return PageBody('Analytics', [
      Row(
        children: [
          Expanded(
            child: _MonthSwitcher(
              label: month == null
                  ? tr(context, 'All time')
                  : DateFormat.yMMMM(locale).format(month!),
              onPrevious: () => setState(() {
                final m = month ?? DateTime.now();
                month = DateTime(m.year, m.month - 1);
              }),
              onNext: month == null
                  ? null
                  : () => setState(
                      () => month = DateTime(month!.year, month!.month + 1),
                    ),
              onTap: () => _pickMonth(context, months),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final c in ['THB', 'MMK'])
                ButtonSegment(value: c, label: Text(c)),
            ],
            selected: {currency},
            onSelectionChanged: (v) => setState(() => currency = v.first),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _Summary(
        spent: spent,
        earned: earned,
        previous: previous,
        currency: currency,
        caption: month == null
            ? tr(context, 'Spent · all confirmed receipts')
            : '${tr(context, 'Spent')} · ${DateFormat('d MMM', locale).format(month!)} – ${DateFormat('d MMM', locale).format(DateTime(month!.year, month!.month + 1, 0))}',
      ),
      if (month != null) ...[
        const SectionHeader(LText('Day by day')),
        Surface(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: _DailyChart(
            month: month!,
            expenses: expenses,
            currency: currency,
          ),
        ),
      ],
      const SizedBox(height: 6),
      CategoryChart(amounts: categories, currency: currency),
      if (top.isNotEmpty) ...[
        const SectionHeader(LText('Biggest spending')),
        SlipGroup(top.take(5)),
      ],
      if (banks.isNotEmpty) ...[
        const SectionHeader(LText('By bank')),
        Surface(child: Column(children: _bars(context, banks))),
      ],
      _SentHome(usable: usable.toList(), currency: currency),
      if (recentMonths.length > 1) ...[
        const SectionHeader(LText('Month to month')),
        Surface(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: _MonthBars(
            months: recentMonths,
            values: [for (final m in recentMonths) monthly[m]!],
            selected: month,
            currency: currency,
            onSelect: (m) => setState(() => month = m),
          ),
        ),
      ],
      if (scoped.isEmpty)
        const Surface(
          child: EmptyState(
            'Nothing here yet',
            'Confirm receipts to start exploring your spending.',
          ),
        ),
    ]);
  }

  Future<void> _pickMonth(BuildContext context, List<DateTime> months) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              ListTile(
                leading: const Icon(Icons.all_inclusive_rounded),
                title: const LText('All time'),
                selected: month == null,
                onTap: () {
                  setState(() => month = null);
                  Navigator.pop(c);
                },
              ),
              for (final m in months.reversed)
                ListTile(
                  leading: const Icon(Icons.calendar_month_rounded),
                  title: Text(DateFormat.yMMMM().format(m)),
                  selected: month == m,
                  onTap: () {
                    setState(() => month = m);
                    Navigator.pop(c);
                  },
                ),
            ],
          ),
        ),
      );

  List<Widget> _bars(BuildContext context, Map<String, int> data) {
    final max = data.values.fold<int>(0, (a, b) => a > b ? a : b);
    final keys = data.keys.toList()
      ..sort((a, b) => data[b]!.compareTo(data[a]!));
    return [
      for (final key in keys)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(money(data[key]!, currency)),
                ],
              ),
              const SizedBox(height: 8),
              GrowBar(
                value: max == 0 ? 0 : data[key]! / max,
                color: Palette.accent(context),
                background: Palette.soft(context),
              ),
            ],
          ),
        ),
    ];
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onTap,
  });
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: BoxDecoration(
      color: Palette.surface(context),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tr(context, 'Previous month'),
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tr(context, 'Next month'),
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.spent,
    required this.earned,
    required this.previous,
    required this.currency,
    required this.caption,
  });
  final int spent, earned;
  final int? previous;
  final String currency, caption;
  @override
  Widget build(BuildContext context) {
    final change = previous == null || previous == 0
        ? null
        : (spent - previous!) * 100 / previous!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.brand, Palette.brandDeep],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              caption,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: CountUpMoney(
                      spent,
                      currency,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (change > 0 ? Palette.expense : Palette.income)
                          .withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${change > 0 ? '▲' : '▼'} ${change.abs().round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (change != null)
              LText(
                'vs previous month',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final item in [
                  ('Income', earned, Icons.south_west_rounded),
                  (
                    'Left',
                    earned - spent,
                    Icons.account_balance_wallet_outlined,
                  ),
                ])
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(item.$3, size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            LText(
                              item.$1,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          money(item.$2, currency),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar per calendar day from the 1st to the last day of [month].
class _DailyChart extends StatefulWidget {
  const _DailyChart({
    required this.month,
    required this.expenses,
    required this.currency,
  });
  final DateTime month;
  final List<Slip> expenses;
  final String currency;
  @override
  State<_DailyChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<_DailyChart> {
  int? picked;
  @override
  void didUpdateWidget(_DailyChart old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month) picked = null;
  }

  @override
  Widget build(BuildContext context) {
    final days = DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final values = List<int>.filled(days, 0);
    for (final s in widget.expenses) {
      values[s.date!.day - 1] += s.amountMinor!;
    }
    final total = values.fold<int>(0, (a, b) => a + b);
    final max = values.fold<int>(0, (a, b) => a > b ? a : b);
    final busiest = max == 0 ? null : values.indexOf(max);
    final now = DateTime.now();
    final elapsed =
        widget.month.year == now.year && widget.month.month == now.month
        ? now.day
        : days;
    final shown = picked ?? busiest;
    final accent = Palette.accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Daily average',
                value: money(total ~/ elapsed.clamp(1, days), widget.currency),
              ),
            ),
            Expanded(
              child: _Stat(
                label: picked == null ? 'Biggest day' : 'Selected day',
                value: shown == null
                    ? '—'
                    : '${shown + 1} ${DateFormat('MMM').format(widget.month)} · ${money(values[shown], widget.currency)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TweenAnimationBuilder<double>(
          key: ValueKey(widget.month),
          tween: Tween(begin: 0, end: 1),
          duration: Motion.reduced(context) ? Duration.zero : Motion.slow,
          curve: Motion.curve,
          builder: (_, grow, _) => SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => picked = picked == i ? null : i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor:
                                (max == 0
                                        ? .03
                                        : (values[i] / max).clamp(.03, 1.0)) *
                                    grow +
                                .001,
                            child: Container(
                              decoration: BoxDecoration(
                                color: values[i] == 0
                                    ? Palette.soft(context)
                                    : i == shown
                                    ? accent
                                    : accent.withValues(alpha: .35),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final d in [1, 8, 15, 22, days])
              Text(
                '$d',
                style: TextStyle(fontSize: 11, color: Palette.muted(context)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LText(
        label,
        style: TextStyle(fontSize: 12, color: Palette.muted(context)),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ],
  );
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.months,
    required this.values,
    required this.selected,
    required this.currency,
    required this.onSelect,
  });
  final List<DateTime> months;
  final List<int> values;
  final DateTime? selected;
  final String currency;
  final ValueChanged<DateTime> onSelect;
  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(1, (a, b) => a > b ? a : b);
    final accent = Palette.accent(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.reduced(context) ? Duration.zero : Motion.slow,
      curve: Motion.curve,
      builder: (_, grow, _) => SizedBox(
        height: 160,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < months.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(months[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          child: Text(
                            NumberFormat.compact().format(values[i] / 100),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: months[i] == selected
                                  ? Palette.text(context)
                                  : Palette.muted(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor:
                                (values[i] / max).clamp(.04, 1.0) * grow + .001,
                            child: Container(
                              decoration: BoxDecoration(
                                color: months[i] == selected
                                    ? accent
                                    : accent.withValues(alpha: .3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat('MMM').format(months[i]),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: months[i] == selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: Palette.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Yearly total of money sent to family, for people supporting home.
class _SentHome extends StatelessWidget {
  const _SentHome({required this.usable, required this.currency});
  final List<Slip> usable;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final sent = usable
        .where(
          (s) =>
              s.direction == Direction.expense &&
              s.category == 'Family & transfers' &&
              s.date!.year == year,
        )
        .toList();
    if (sent.isEmpty) return const SizedBox.shrink();
    final byMonth = List<int>.filled(12, 0);
    for (final s in sent) {
      byMonth[s.date!.month - 1] += s.amountMinor!;
    }
    final total = byMonth.fold<int>(0, (a, b) => a + b);
    final max = byMonth.fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(Text('${tr(context, 'Sent home in')} $year')),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🏡', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CountUpMoney(
                      total,
                      currency,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${sent.length} ${tr(context, 'transfers')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Palette.muted(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 54,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var m = 0; m < 12; m++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FractionallySizedBox(
                            heightFactor: (byMonth[m] / max).clamp(.05, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: byMonth[m] == 0
                                    ? Palette.soft(context)
                                    : const Color(0xff3e9e9a),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final m in ['Jan', 'Apr', 'Jul', 'Oct', 'Dec'])
                    Text(
                      m,
                      style: TextStyle(
                        fontSize: 10,
                        color: Palette.muted(context),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
