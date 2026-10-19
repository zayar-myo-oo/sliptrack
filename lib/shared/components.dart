import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/models.dart';
import 'localized_text.dart';
import 'design.dart';
import 'motion.dart';
import 'privacy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/state.dart';
import '../features/ocr/ocr_service.dart';

void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class PageBody extends StatelessWidget {
  const PageBody(
    this.title,
    this.children, {
    this.actions = const [],
    super.key,
  });
  final String title;
  final List<Widget> children, actions;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverAppBar(
        title: LText(title, style: Theme.of(context).textTheme.headlineSmall),
        actions: actions,
        floating: true,
        titleSpacing: 20,
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: staggered(children),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class BalanceCard extends StatelessWidget {
  const BalanceCard({
    required this.currency,
    required this.totals,
    this.caption = 'MONTHLY CASH FLOW',
    super.key,
  });
  final String currency;
  final String caption;
  final Totals totals;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Palette.brand,
      borderRadius: BorderRadius.circular(24),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$currency · $caption',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            child: Text(
              money(totals.net, currency),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final item in [
                ('Income', totals.income, Icons.south_west_rounded),
                ('Expenses', totals.expense, Icons.north_east_rounded),
              ])
                Expanded(
                  child: Row(
                    children: [
                      Icon(item.$3, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${tr(context, item.$1)}  ${money(item.$2, currency)}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
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

class SlipTile extends StatelessWidget {
  const SlipTile(this.slip, {super.key});
  final Slip slip;
  @override
  Widget build(BuildContext context) {
    final income = slip.direction == Direction.income;
    final pending = slip.review == ReviewStatus.pending;
    final title = slip.receiver.isNotEmpty ? slip.receiver : slip.bank.label;
    final source = slip.isManualExpense
        ? tr(context, 'Manual expense')
        : slip.isManualIncome
        ? tr(context, 'Manual income')
        : slip.bank.label;
    final date = slip.date == null
        ? 'Date needs review'
        : DateFormat('d MMM').format(slip.date!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          context.push(
            slip.isManualExpense
                ? '/expense/${slip.id}'
                : slip.isManualIncome
                ? '/income/${slip.id}'
                : '/review/${slip.id}',
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pending
                      ? Palette.warn.withValues(alpha: .14)
                      : income
                      ? Palette.incomeSoft(context)
                      : Palette.expenseSoft(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  pending
                      ? Icons.priority_high_rounded
                      : income
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  size: 20,
                  color: pending
                      ? Palette.warn
                      : income
                      ? Palette.income
                      : Palette.expense,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pending
                          ? '${tr(context, 'Needs review')} · $date'
                          : '${tr(context, slip.category)} · $source',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: pending ? Palette.warn : Palette.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .36,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: hideAmounts,
                      builder: (_, _, _) => Text(
                        slip.amountMinor == null
                            ? 'Check amount'
                            : hideAmounts.value
                            ? '$maskedAmount ${slip.currency}'
                            : '${income ? '+' : '−'}${money(slip.amountMinor!, slip.currency)}',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: income
                              ? Palette.income
                              : Palette.text(context),
                        ),
                      ),
                    ),
                    if (!pending) ...[
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: 12,
                          color: Palette.muted(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups transaction rows into one rounded surface, like a bank statement.
class SlipGroup extends ConsumerWidget {
  const SlipGroup(this.slips, {this.swipeToDelete = false, super.key});
  final Iterable<Slip> slips;
  final bool swipeToDelete;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Surface(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    child: Column(
      children: [
        for (final s in slips)
          swipeToDelete
              ? Dismissible(
                  key: ValueKey('swipe:${s.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Palette.expense,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                  confirmDismiss: (_) async {
                    HapticFeedback.mediumImpact();
                    return await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const LText('Delete this transaction?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const LText('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const LText('Delete'),
                              ),
                            ],
                          ),
                        ) ==
                        true;
                  },
                  onDismissed: (_) async {
                    await ref.read(repositoryProvider).deleteSlip(s.id);
                    if (s.source.isNotEmpty) {
                      try {
                        await OnDeviceOCR.channel.invokeMethod('cleanup', {
                          'id': s.source,
                        });
                      } catch (_) {
                        /* Source cleanup can be retried on data deletion. */
                      }
                    }
                  },
                  child: SlipTile(s),
                )
              : SlipTile(s),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Palette.soft(context),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.receipt_long_outlined,
            size: 30,
            color: Palette.muted(context),
          ),
        ),
        const SizedBox(height: 14),
        LText(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        LText(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.muted(context), fontSize: 13),
        ),
      ],
    ),
  );
}
