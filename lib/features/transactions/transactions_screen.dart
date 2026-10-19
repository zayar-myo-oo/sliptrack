import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../shared/components.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({
    this.reviewOnly = false,
    this.initialMonth,
    super.key,
  });
  final bool reviewOnly;
  final DateTime? initialMonth;
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsState();
}

class _TransactionsState extends ConsumerState<TransactionsScreen> {
  String search = '', currency = '', bank = '', direction = '', category = '';
  DateTimeRange? range;
  bool onlyReview = false;
  @override
  void initState() {
    super.initState();
    onlyReview = widget.reviewOnly;
    final month = widget.initialMonth;
    if (month != null) {
      range = DateTimeRange(
        start: DateTime(month.year, month.month),
        end: DateTime(month.year, month.month + 1, 0),
      );
    }
  }

  @override
  void didUpdateWidget(TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMonth != widget.initialMonth) {
      final month = widget.initialMonth;
      range = month == null
          ? null
          : DateTimeRange(
              start: DateTime(month.year, month.month),
              end: DateTime(month.year, month.month + 1, 0),
            );
    }
    if (oldWidget.reviewOnly != widget.reviewOnly) {
      onlyReview = widget.reviewOnly;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(slipsProvider).asData?.value ?? [];
    final slips = all
        .where(
          (s) =>
              (currency.isEmpty || s.currency == currency) &&
              (bank.isEmpty || s.bank.name == bank) &&
              (direction.isEmpty || s.direction.name == direction) &&
              (category.isEmpty || s.category == category) &&
              (!onlyReview || s.review == ReviewStatus.pending) &&
              (range == null ||
                  (s.date != null &&
                      !s.date!.isBefore(range!.start) &&
                      s.date!.isBefore(
                        range!.end.add(const Duration(days: 1)),
                      ))) &&
              '${s.sender} ${s.receiver} ${s.reference} ${s.description}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    return PageBody(ref.watch(preferencesProvider).text('Transactions'), [
      TextField(
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search names, notes, references',
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(
            label: const LText('Needs review'),
            selected: onlyReview,
            onSelected: (v) => setState(() => onlyReview = v),
          ),
          for (final c in ['THB', 'MMK'])
            FilterChip(
              label: Text(c),
              selected: currency == c,
              onSelected: (v) => setState(() => currency = v ? c : ''),
            ),
          ActionChip(
            label: Text(
              range == null
                  ? 'Date range'
                  : '${DateFormat('dd MMM').format(range!.start)} – ${DateFormat('dd MMM').format(range!.end)}',
            ),
            onPressed: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDateRange: range,
              );
              if (mounted && r != null) setState(() => range = r);
            },
          ),
          if (range != null)
            ActionChip(
              label: const LText('Clear dates'),
              onPressed: () => setState(() => range = null),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField(
              isExpanded: true,
              initialValue: bank,
              decoration: InputDecoration(labelText: tr(context, 'Bank')),
              items: [
                const DropdownMenuItem(value: '', child: LText('All banks')),
                ...Bank.values.map(
                  (b) => DropdownMenuItem(value: b.name, child: Text(b.label)),
                ),
              ],
              onChanged: (v) => setState(() => bank = v ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField(
              isExpanded: true,
              initialValue: direction,
              decoration: InputDecoration(labelText: tr(context, 'Direction')),
              items: [
                const DropdownMenuItem(value: '', child: LText('All types')),
                ...Direction.values.map(
                  (d) => DropdownMenuItem(value: d.name, child: Text(d.name)),
                ),
              ],
              onChanged: (v) => setState(() => direction = v ?? ''),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField(
        isExpanded: true,
        initialValue: category,
        decoration: InputDecoration(labelText: tr(context, 'Category')),
        items: [
          const DropdownMenuItem(value: '', child: LText('All categories')),
          ...all
              .map((s) => s.category)
              .toSet()
              .map((c) => DropdownMenuItem(value: c, child: Text(c))),
        ],
        onChanged: (v) => setState(() => category = v ?? ''),
      ),
      const SizedBox(height: 16),
      LText('${slips.length} transactions'),
      ...slips.map(SlipTile.new),
      if (slips.isEmpty)
        const EmptyState(
          'No matching receipts',
          'Try another filter or import a bank slip.',
        ),
    ]);
  }
}
