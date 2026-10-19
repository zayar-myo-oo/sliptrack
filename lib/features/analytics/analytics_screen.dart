import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../shared/components.dart';
import '../../shared/estimated_cash_flow.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsState();
}

class _AnalyticsState extends ConsumerState<AnalyticsScreen> {
  String currency = 'THB', period = 'Monthly';
  @override
  Widget build(BuildContext context) {
    final all = ref.watch(slipsProvider).asData?.value ?? [];
    final expenses = all.where(
      (s) =>
          s.currency == currency &&
          s.review == ReviewStatus.confirmed &&
          s.direction == Direction.expense &&
          s.date != null &&
          s.amountMinor != null,
    );
    final groups = <String, int>{},
        categories = <String, int>{},
        banks = <String, int>{};
    for (final s in expenses) {
      final d = s.date!;
      final key = period == 'Daily'
          ? DateFormat('yyyy-MM-dd').format(d)
          : period == 'Weekly'
          ? DateFormat(
              'yyyy-MM-dd',
            ).format(d.subtract(Duration(days: d.weekday - 1)))
          : DateFormat('yyyy-MM').format(d);
      groups.update(
        key,
        (n) => n + s.amountMinor!,
        ifAbsent: () => s.amountMinor!,
      );
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
    final totals = totalsFor(all)[currency]!;
    return PageBody('Analytics', [
      EstimatedCashFlowCard(
        totals: totalsFor(all),
        scope: tr(context, 'All months'),
      ),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: [
          'THB',
          'MMK',
        ].map((c) => ButtonSegment(value: c, label: Text(c))).toList(),
        selected: {currency},
        onSelectionChanged: (v) => setState(() => currency = v.first),
      ),
      const SizedBox(height: 20),
      BalanceCard(
        currency: currency,
        totals: totals,
        caption: 'ALL-TIME CASH FLOW',
      ),
      const LText('All-time confirmed totals · Internal transfers excluded'),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        children: ['Daily', 'Weekly', 'Monthly']
            .map(
              (p) => ChoiceChip(
                label: Text(p),
                selected: period == p,
                onSelected: (_) => setState(() => period = p),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 24),
      LText('$period spending', style: Theme.of(context).textTheme.titleLarge),
      ..._bars(groups, currency),
      const SizedBox(height: 24),
      LText('By category', style: Theme.of(context).textTheme.titleLarge),
      ..._bars(categories, currency),
      const SizedBox(height: 24),
      LText('By bank', style: Theme.of(context).textTheme.titleLarge),
      ..._bars(banks, currency),
      if (expenses.isEmpty)
        const EmptyState(
          'Your trends will appear here',
          'Confirm receipts to start exploring your spending.',
        ),
    ]);
  }

  List<Widget> _bars(Map<String, int> data, String currency) {
    final max = data.values.fold<int>(0, (a, b) => a > b ? a : b);
    final keys = data.keys.toList()..sort();
    return keys
        .map(
          (key) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(key)),
                    Text(money(data[key]!, currency)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : data[key]! / max,
                    minHeight: 10,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}
