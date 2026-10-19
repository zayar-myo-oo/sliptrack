import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../shared/components.dart';
import '../../shared/category_chart.dart';
import '../../shared/design.dart';

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
    final periodKeys = groups.keys.toList()..sort();
    final recent = periodKeys.length > 6
        ? periodKeys.sublist(periodKeys.length - 6)
        : periodKeys;
    return PageBody('Analytics', [
      LText(
        'All months · Confirmed spending',
        style: TextStyle(fontSize: 13, color: Palette.muted(context)),
      ),
      const SizedBox(height: 14),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          'THB',
          'MMK',
        ].map((c) => ButtonSegment(value: c, label: Text(c))).toList(),
        selected: {currency},
        onSelectionChanged: (v) => setState(() => currency = v.first),
      ),
      const SizedBox(height: 12),
      CategoryChart(amounts: categories, currency: currency),
      SectionHeader(
        LText('$period spending'),
        action: SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -3),
          ),
          segments: [
            for (final p in ['Daily', 'Weekly', 'Monthly'])
              ButtonSegment(
                value: p,
                label: LText(p, style: const TextStyle(fontSize: 12)),
              ),
          ],
          selected: {period},
          onSelectionChanged: (v) => setState(() => period = v.first),
        ),
      ),
      Surface(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
        child: recent.isEmpty
            ? const EmptyState(
                'Your trends will appear here',
                'Confirm receipts to start exploring your spending.',
              )
            : _Trend(
                labels: [
                  for (final k in recent)
                    period == 'Monthly'
                        ? DateFormat('MMM').format(DateTime.parse('$k-01'))
                        : DateFormat('d MMM').format(DateTime.parse(k)),
                ],
                values: [for (final k in recent) groups[k]!],
                currency: currency,
              ),
      ),
      const SectionHeader(LText('By bank')),
      Surface(
        child: banks.isEmpty
            ? LText(
                'No confirmed spending yet',
                style: TextStyle(color: Palette.muted(context)),
              )
            : Column(children: _bars(banks, currency)),
      ),
    ]);
  }

  List<Widget> _bars(Map<String, int> data, String currency) {
    final max = data.values.fold<int>(0, (a, b) => a > b ? a : b);
    final keys = data.keys.toList()
      ..sort((a, b) => data[b]!.compareTo(data[a]!));
    return keys
        .map(
          (key) => Padding(
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : data[key]! / max,
                    minHeight: 8,
                    color: Palette.brand,
                    backgroundColor: Palette.soft(context),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}

class _Trend extends StatelessWidget {
  const _Trend({
    required this.labels,
    required this.values,
    required this.currency,
  });
  final List<String> labels;
  final List<int> values;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          money(values.last, currency),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        LText(
          'Latest period',
          style: TextStyle(fontSize: 12, color: Palette.muted(context)),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: (values[i] / max).clamp(.04, 1.0),
                            child: Tooltip(
                              message: money(values[i], currency),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: i == values.length - 1
                                      ? Palette.brand
                                      : Palette.mint,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          labels[i],
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
                ),
            ],
          ),
        ),
      ],
    );
  }
}
