import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/state.dart';
import '../core/exchange_rate.dart';
import '../core/models.dart';
import 'localized_text.dart';
import 'design.dart';

class EstimatedCashFlowCard extends ConsumerWidget {
  const EstimatedCashFlowCard({
    required this.totals,
    required this.scope,
    this.reserveThb = 0,
    super.key,
  });
  final Map<String, Totals> totals;
  final String scope;
  final int reserveThb;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, _) {
        final rate =
            (prefs.values['mmkPerThbMicros'] as int?) ?? defaultMmkPerThbMicros;
        final estimate = estimateInThb(totals, rate);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Palette.brand, Palette.brandDeep],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Palette.brandDeep.withValues(alpha: .22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LText(
                        'Available · approximate THB',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '≈ ${money(estimate.net - reserveThb, 'THB')}',
                    key: const Key('estimatedNetThb'),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final item in [
                      ('Income', estimate.income, Icons.south_west),
                      ('Expenses', estimate.expense, Icons.north_east),
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
                            const SizedBox(height: 4),
                            Text(
                              money(item.$2, 'THB'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Savings reserved: ≈ ${money(reserveThb, 'THB')}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '1 THB = ${formatManualRate(rate)} MMK · ${tr(context, 'Manual estimate')}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
