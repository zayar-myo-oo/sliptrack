import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../shared/components.dart';
import '../../shared/design.dart';

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
    final extraFilters = [
      bank,
      direction,
      category,
    ].where((f) => f.isNotEmpty).length;
    final groups = <String, List<Slip>>{};
    for (final s in slips) {
      final key = s.date == null
          ? tr(context, 'Date needs review')
          : DateFormat('EEE, d MMM yyyy').format(s.date!);
      groups.putIfAbsent(key, () => []).add(s);
    }
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: LText(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
    return PageBody(ref.watch(preferencesProvider).text('Transactions'), [
      TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: tr(context, 'Search names, notes, references'),
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: Palette.text(context),
                ),
                label: Text(
                  extraFilters == 0
                      ? tr(context, 'Filters')
                      : '${tr(context, 'Filters')} · $extraFilters',
                ),
                onPressed: () => _filters(context, all),
              ),
            ),
            chip('Needs review', onlyReview, () {
              setState(() => onlyReview = !onlyReview);
            }),
            for (final c in ['THB', 'MMK'])
              chip(c, currency == c, () {
                setState(() => currency = currency == c ? '' : c);
              }),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                avatar: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  range == null
                      ? tr(context, 'Date range')
                      : '${DateFormat('d MMM').format(range!.start)} – ${DateFormat('d MMM').format(range!.end)}',
                ),
                selected: range != null,
                showCheckmark: false,
                onDeleted: range == null
                    ? null
                    : () => setState(() => range = null),
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
            ),
          ],
        ),
      ),
      SectionHeader(LText('${slips.length} transactions')),
      if (slips.isEmpty)
        const Surface(
          child: EmptyState(
            'No matching receipts',
            'Try another filter or import a bank slip.',
          ),
        ),
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Palette.muted(context),
            ),
          ),
        ),
        SlipGroup(entry.value, swipeToDelete: true),
      ],
    ]);
  }

  Future<void> _filters(
    BuildContext context,
    List<Slip> all,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        void update(VoidCallback f) {
          setState(f);
          set(() {});
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LText('Filters', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField(
                isExpanded: true,
                initialValue: bank,
                decoration: InputDecoration(labelText: tr(context, 'Bank')),
                items: [
                  const DropdownMenuItem(value: '', child: LText('All banks')),
                  ...Bank.values.map(
                    (b) =>
                        DropdownMenuItem(value: b.name, child: Text(b.label)),
                  ),
                ],
                onChanged: (v) => update(() => bank = v ?? ''),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                isExpanded: true,
                initialValue: direction,
                decoration: InputDecoration(labelText: tr(context, 'Type')),
                items: [
                  const DropdownMenuItem(value: '', child: LText('All types')),
                  ...Direction.values.map(
                    (d) =>
                        DropdownMenuItem(value: d.name, child: LText(d.label)),
                  ),
                ],
                onChanged: (v) => update(() => direction = v ?? ''),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                isExpanded: true,
                initialValue: category,
                decoration: InputDecoration(labelText: tr(context, 'Category')),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: LText('All categories'),
                  ),
                  ...all
                      .map((s) => s.category)
                      .toSet()
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => update(() => category = v ?? ''),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => update(() {
                        bank = '';
                        direction = '';
                        category = '';
                      }),
                      child: const LText('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(c),
                      child: const LText('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
