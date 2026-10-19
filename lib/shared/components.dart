import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/models.dart';
import 'localized_text.dart';

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
        title: LText(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: actions,
        floating: true,
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        sliver: SliverList.list(children: children),
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
  Widget build(BuildContext context) => Card(
    color: currency == 'THB'
        ? const Color(0xff075e55)
        : const Color(0xff243e5e),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$currency · $caption',
              style: const TextStyle(color: Colors.white70, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            FittedBox(
              child: Text(
                money(totals.net, currency),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: [
                Text(
                  '${tr(context, 'Income')}\n${money(totals.income, currency)}',
                ),
                Text(
                  '${tr(context, 'Expenses')}\n${money(totals.expense, currency)}',
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class SlipTile extends StatelessWidget {
  const SlipTile(this.slip, {super.key});
  final Slip slip;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        child: Icon(
          slip.review == ReviewStatus.pending
              ? Icons.rule
              : slip.direction == Direction.income
              ? Icons.south_west
              : Icons.north_east,
        ),
      ),
      title: Text(
        slip.receiver.isNotEmpty ? slip.receiver : slip.bank.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${slip.isManualIncome ? tr(context, 'Manual income') : slip.bank.label} · ${slip.date == null ? 'Date needs review' : DateFormat('dd MMM').format(slip.date!)}\n${slip.review == ReviewStatus.pending ? 'Needs review' : slip.category}',
      ),
      isThreeLine: true,
      trailing: Text(
        slip.amountMinor == null
            ? 'Check amount'
            : money(slip.amountMinor!, slip.currency),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onTap: () => context.push(slip.isManualIncome ? '/income/${slip.id}' : '/review/${slip.id}'),
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
        const Icon(Icons.receipt_long_outlined, size: 48),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center),
      ],
    ),
  );
}
