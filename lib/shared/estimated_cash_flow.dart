import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../app/state.dart';
import '../core/exchange_rate.dart';
import '../core/models.dart';
import 'localized_text.dart';

class EstimatedCashFlowCard extends ConsumerWidget {
  const EstimatedCashFlowCard({
    required this.totals,
    required this.scope,
    super.key,
  });
  final Map<String, Totals> totals;
  final String scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, _) {
        final rate =
            (prefs.values['mmkPerThbMicros'] as int?) ?? defaultMmkPerThbMicros;
        final estimate = estimateInThb(totals, rate);
        final updated = DateTime.tryParse(
          prefs.values['manualRateUpdatedAt'] ?? '',
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.currency_exchange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LText(
                        'Estimated THB total',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(scope, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                FittedBox(
                  child: Text(
                    money(estimate.net, 'THB'),
                    key: const Key('estimatedNetThb'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    Text(
                      '${tr(context, 'Income')}: ${money(estimate.income, 'THB')}',
                    ),
                    Text(
                      '${tr(context, 'Expenses')}: ${money(estimate.expense, 'THB')}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '1 THB = ${formatManualRate(rate)} MMK · ${tr(context, 'Manual estimate')}',
                ),
                if (updated != null)
                  Text(
                    '${tr(context, 'Rate last set')}: ${DateFormat.yMMMd().add_Hm().format(updated.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 4),
                const LText(
                  'Approximate conversion. Original amounts stay in their currencies.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
