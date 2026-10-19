import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../shared/components.dart';
import '../../shared/estimated_cash_flow.dart';
import '../companion/companion_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<DashboardScreen> {
  String? account;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    final data = ref.watch(slipsProvider);
    final accounts = ref.watch(accountsProvider).asData?.value ?? [];
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(
        child: LText(
          'Unable to open records. Restart after unlocking the device.',
        ),
      ),
      data: (all) {
        final slips = all
            .where(
              (s) =>
                  (account == null || s.accountId == account) &&
                  s.date?.year == month.year &&
                  s.date?.month == month.month,
            )
            .toList();
        final totals = totalsFor(slips, month: month);
        final review = slips
            .where((s) => s.review == ReviewStatus.pending)
            .length;
        return PageBody('SlipTrack', [
          Row(
            children: [
              IconButton(
                key: const Key('monthPrevious'),
                tooltip: tr(context, 'Previous month'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => month = DateTime(month.year, month.month - 1),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('monthPicker'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: month,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      helpText: tr(context, 'Choose month'),
                    );
                    if (picked != null && mounted) {
                      setState(
                        () => month = DateTime(picked.year, picked.month),
                      );
                    }
                  },
                  child: Text(
                    DateFormat.yMMMM(prefs.locale.languageCode).format(month),
                  ),
                ),
              ),
              IconButton(
                key: const Key('monthNext'),
                tooltip: tr(context, 'Next month'),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => month = DateTime(month.year, month.month + 1),
                ),
              ),
            ],
          ),
          const Center(child: LText('Only this month is shown here')),
          const SizedBox(height: 8),
          LText(
            'A little clarity,\nevery day.',
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: account ?? '',
            decoration: InputDecoration(labelText: tr(context, 'Account')),
            items: [
              const DropdownMenuItem(value: '', child: LText('All accounts')),
              ...accounts.map(
                (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
              ),
            ],
            onChanged: (v) => setState(() => account = v == '' ? null : v),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push(
              '/income?month=${DateFormat('yyyy-MM').format(month)}',
            ),
            icon: const Icon(Icons.add),
            label: const LText('Add income'),
          ),
          CompanionCard(totals: totals),
          EstimatedCashFlowCard(
            totals: totals,
            scope: DateFormat.yMMMM(prefs.locale.languageCode).format(month),
          ),
          ...totals.entries.map(
            (e) => BalanceCard(currency: e.key, totals: e.value),
          ),
          if (review > 0)
            Card(
              child: ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: LText('$review ${prefs.text('Needs review')}'),
                subtitle: const LText(
                  'Check extracted details before they affect totals',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(
                  '/transactions?review=true&month=${DateFormat('yyyy-MM').format(month)}',
                ),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LText(
                'Recent activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () => context.go('/transactions'),
                child: const LText('All months'),
              ),
            ],
          ),
          if (slips.isEmpty)
            const EmptyState(
              'No receipts in this month',
              'Choose another month, import a receipt, or open All months to see the combined history.',
            ),
          ...slips.take(5).map((s) => SlipTile(s)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.go('/scan'),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(prefs.text('Import Photos')),
          ),
        ]);
      },
    );
  }
}
