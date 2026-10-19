import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/categories.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
import '../../core/plans.dart';
import '../../shared/components.dart';
import '../../shared/design.dart';
import '../../shared/localized_text.dart';
import '../../shared/motion.dart';
import '../companion/coach_models.dart';
import '../slip_recognition/parsers.dart';

/// Goals, recurring bills and debts in one place.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({this.tab = 0, super.key});
  final int tab;
  @override
  ConsumerState<PlansScreen> createState() => _PlansState();
}

class _PlansState extends ConsumerState<PlansScreen> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    return DefaultTabController(
      length: 3,
      initialIndex: widget.tab,
      child: Scaffold(
        appBar: AppBar(
          title: const LText('Plans'),
          bottom: TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: tr(context, 'Goals')),
              Tab(text: tr(context, 'Bills')),
              Tab(text: tr(context, 'Debts')),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: prefs,
          builder: (_, _) => TabBarView(
            children: [_Goals(prefs), _Bills(prefs), _Debts(prefs)],
          ),
        ),
      ),
    );
  }
}

Widget _list(List<Widget> children) => ListView(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
  children: staggered(children),
);

Widget _addButton(BuildContext context, String label, VoidCallback onTap) =>
    Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded),
        label: LText(label),
      ),
    );

String _amount(String text) => text.trim();

// ---------------------------------------------------------------- Goals

class _Goals extends ConsumerWidget {
  const _Goals(this.prefs);
  final Preferences prefs;
  List<SavingsGoal> get goals =>
      readList(prefs.values, 'goals', SavingsGoal.fromJson);
  Future<void> save(List<SavingsGoal> list) =>
      prefs.update('goals', [for (final g in list) g.toJson()]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = goals;
    return _list([
      if (list.isEmpty)
        const Surface(
          child: EmptyState(
            'No goals yet',
            'Save for something you want — a new phone, a trip home, an emergency fund.',
          ),
        ),
      for (final g in list)
        Surface(
          onTap: () => _contribute(context, ref, g, list),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(g.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${money(g.savedMinor, 'THB')} / ${money(g.targetMinor, 'THB')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Palette.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (g.ratio >= 1)
                    const Text('🎉', style: TextStyle(fontSize: 22))
                  else
                    Text(
                      '${(g.ratio * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (_) async {
                      list.removeWhere((x) => x.id == g.id);
                      await save(list);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'delete', child: LText('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GrowBar(
                value: g.ratio,
                height: 10,
                color: g.ratio >= 1 ? Palette.income : Palette.accent(context),
                background: Palette.soft(context),
              ),
            ],
          ),
        ),
      _addButton(context, 'New goal', () => _newGoal(context, list)),
    ]);
  }

  Future<void> _newGoal(BuildContext context, List<SavingsGoal> list) async {
    final name = TextEditingController(), target = TextEditingController();
    var emoji = '🎯';
    final ok = await _sheet(
      context,
      'New goal',
      (set) => [
        Wrap(
          spacing: 6,
          children: [
            for (final e in ['🎯', '📱', '✈️', '🏠', '🎓', '🛵', '💍', '🆘'])
              ChoiceChip(
                label: Text(e, style: const TextStyle(fontSize: 18)),
                selected: emoji == e,
                showCheckmark: false,
                onSelected: (_) => set(() => emoji = e),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: tr(context, 'Goal name')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr(context, 'Target'),
            suffixText: 'THB',
          ),
        ),
      ],
    );
    final minor = parseMinor(_amount(target.text)) ?? 0;
    if (ok && name.text.trim().isNotEmpty && minor > 0) {
      list.add(
        SavingsGoal(
          id: newId(),
          name: name.text.trim(),
          targetMinor: minor,
          emoji: emoji,
        ),
      );
      await save(list);
    }
    name.dispose();
    target.dispose();
  }

  Future<void> _contribute(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal g,
    List<SavingsGoal> list,
  ) async {
    final amount = TextEditingController();
    final ok = await _sheet(
      context,
      '${g.emoji} ${g.name}',
      (_) => [
        LText(
          'Add to this goal. It also counts toward your cat’s level.',
          style: TextStyle(fontSize: 12, color: Palette.muted(context)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr(context, 'Amount'),
            suffixText: 'THB',
          ),
        ),
      ],
    );
    final minor = parseMinor(_amount(amount.text)) ?? 0;
    amount.dispose();
    if (!ok || minor <= 0) return;
    g.savedMinor += minor;
    await save(list);
    try {
      await ref
          .read(repositoryProvider)
          .saveSavings(
            SavingsEntry.create(
              amountMinor: minor,
              currency: 'THB',
              date: DateTime.now(),
              rateMicros:
                  prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros,
              goalThbMinor:
                  prefs.values['savingsGoalThbMinor'] ??
                  defaultSavingsGoalThbMinor,
              note: g.name,
            ),
          );
      await ref.read(coachProvider).evaluate();
    } catch (_) {
      /* The goal total is already saved. */
    }
    HapticFeedback.heavyImpact();
    if (context.mounted && g.ratio >= 1) {
      message(context, '🎉 ${tr(context, 'Goal reached!')} ${g.name}');
    }
  }
}

// ---------------------------------------------------------------- Bills

class _Bills extends StatelessWidget {
  const _Bills(this.prefs);
  final Preferences prefs;
  List<RecurringBill> get bills =>
      readList(prefs.values, 'recurring', RecurringBill.fromJson);
  Future<void> save(List<RecurringBill> list) =>
      prefs.update('recurring', [for (final b in list) b.toJson()]);

  @override
  Widget build(BuildContext context) {
    final list = bills..sort((a, b) => a.day.compareTo(b.day));
    final now = DateTime.now();
    final monthly = list.fold<int>(
      0,
      (n, b) =>
          n +
          (b.currency == 'MMK'
              ? mmkToThbMinor(
                  b.amountMinor,
                  prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros,
                )
              : b.amountMinor),
    );
    return _list([
      if (list.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            '${tr(context, 'Every month')} ≈ ${money(monthly, 'THB')}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      if (list.isEmpty)
        const Surface(
          child: EmptyState(
            'No regular bills',
            'Add rent, phone or internet once. They are added automatically every month.',
          ),
        ),
      for (final b in list)
        Surface(
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: categoryStyle(b.category).color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${b.day}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(
                        b
                                .dueIn(now)
                                .isBefore(
                                  DateTime(now.year, now.month, now.day),
                                )
                            ? DateTime(now.year, now.month + 1)
                            : now,
                      ),
                      style: TextStyle(
                        fontSize: 10,
                        color: Palette.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      b.lastPosted == monthKey(now)
                          ? '✓ ${tr(context, 'Added this month')}'
                          : b.autoAdd
                          ? tr(context, 'Added automatically on the due day')
                          : tr(context, 'Reminder only'),
                      style: TextStyle(
                        fontSize: 12,
                        color: b.lastPosted == monthKey(now)
                            ? Palette.income
                            : Palette.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                money(b.amountMinor, b.currency),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              PopupMenuButton<String>(
                onSelected: (_) async {
                  list.removeWhere((x) => x.id == b.id);
                  await save(list);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: LText('Delete')),
                ],
              ),
            ],
          ),
        ),
      _addButton(context, 'New bill', () => _newBill(context, list)),
    ]);
  }

  Future<void> _newBill(BuildContext context, List<RecurringBill> list) async {
    final name = TextEditingController(), amount = TextEditingController();
    var currency = 'THB', category = 'Bills', day = DateTime.now().day;
    var autoAdd = true;
    final ok = await _sheet(
      context,
      'New bill',
      (set) => [
        TextField(
          controller: name,
          decoration: InputDecoration(
            labelText: tr(context, 'Name'),
            hintText: tr(context, 'Rent, phone, internet…'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: tr(context, 'Amount')),
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
              onSelectionChanged: (v) => set(() => currency = v.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: LText('Due day of month')),
            IconButton(
              onPressed: () => set(() => day = day <= 1 ? 31 : day - 1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '$day',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            IconButton(
              onPressed: () => set(() => day = day >= 31 ? 1 : day + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in expenseCategories)
              ChoiceChip(
                avatar: Icon(c.icon, size: 16, color: c.color),
                label: LText(c.name),
                selected: category == c.name,
                showCheckmark: false,
                onSelected: (_) => set(() => category = c.name),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const LText('Add automatically each month'),
          value: autoAdd,
          onChanged: (v) => set(() => autoAdd = v),
        ),
      ],
    );
    final minor = parseMinor(_amount(amount.text)) ?? 0;
    if (ok && name.text.trim().isNotEmpty && minor > 0) {
      final now = DateTime.now();
      list.add(
        RecurringBill(
          id: newId(),
          name: name.text.trim(),
          amountMinor: minor,
          currency: currency,
          category: category,
          day: day,
          autoAdd: autoAdd,
          // A bill whose day already passed starts next month, so creating it
          // never back-fills an expense the user may have recorded already.
          lastPosted: DateTime(now.year, now.month, day).isAfter(now)
              ? ''
              : monthKey(now),
        ),
      );
      await save(list);
    }
    name.dispose();
    amount.dispose();
  }
}

// ---------------------------------------------------------------- Debts

class _Debts extends StatelessWidget {
  const _Debts(this.prefs);
  final Preferences prefs;
  List<Debt> get debts => readList(prefs.values, 'debts', Debt.fromJson);
  Future<void> save(List<Debt> list) =>
      prefs.update('debts', [for (final d in list) d.toJson()]);

  @override
  Widget build(BuildContext context) {
    final list = debts
      ..sort((a, b) => (a.settled ? 1 : 0).compareTo(b.settled ? 1 : 0));
    int total(bool lent) => list
        .where((d) => d.lent == lent && !d.settled && d.currency == 'THB')
        .fold(0, (n, d) => n + d.amountMinor);
    return _list([
      Row(
        children: [
          for (final side in [true, false])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: side
                        ? Palette.incomeSoft(context)
                        : Palette.expenseSoft(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        side ? 'Owed to me' : 'I owe',
                        style: TextStyle(
                          fontSize: 12,
                          color: Palette.muted(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        child: Text(
                          money(total(side), 'THB'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: side ? Palette.income : Palette.expense,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      if (list.isEmpty)
        const Surface(
          child: EmptyState(
            'No debts',
            'Keep track of money you lent to friends or borrowed, with a reminder date.',
          ),
        ),
      for (final d in list)
        Opacity(
          opacity: d.settled ? .5 : 1,
          child: Surface(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: d.lent
                      ? Palette.incomeSoft(context)
                      : Palette.expenseSoft(context),
                  child: Text(
                    d.person.isEmpty ? '?' : d.person.characters.first,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: d.lent ? Palette.income : Palette.expense,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.person,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: d.settled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        [
                          tr(context, d.lent ? 'Lent' : 'Borrowed'),
                          if (d.due != null)
                            '${tr(context, 'Due')} ${DateFormat('d MMM').format(d.due!)}',
                          if (d.overdue) '⚠️',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: d.overdue
                              ? Palette.expense
                              : Palette.muted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  money(d.amountMinor, d.currency),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: d.lent ? Palette.income : Palette.expense,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') {
                      list.removeWhere((x) => x.id == d.id);
                    } else {
                      d.settled = !d.settled;
                      HapticFeedback.mediumImpact();
                    }
                    await save(list);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'settle',
                      child: LText(
                        d.settled ? 'Mark as open' : 'Mark as settled',
                      ),
                    ),
                    PopupMenuItem(value: 'delete', child: LText('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      _addButton(context, 'New debt', () => _newDebt(context, list)),
    ]);
  }

  Future<void> _newDebt(BuildContext context, List<Debt> list) async {
    final person = TextEditingController(), amount = TextEditingController();
    var currency = 'THB', lent = true;
    DateTime? due;
    final ok = await _sheet(
      context,
      'New debt',
      (set) => [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: true, label: LText('I lent')),
            ButtonSegment(value: false, label: LText('I borrowed')),
          ],
          selected: {lent},
          onSelectionChanged: (v) => set(() => lent = v.first),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: person,
          decoration: InputDecoration(labelText: tr(context, 'Person')),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: tr(context, 'Amount')),
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
              onSelectionChanged: (v) => set(() => currency = v.first),
            ),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: const LText('Due date'),
          trailing: Text(
            due == null ? '—' : DateFormat.yMMMd().format(due!),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 7)),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) set(() => due = d);
          },
        ),
      ],
    );
    final minor = parseMinor(_amount(amount.text)) ?? 0;
    if (ok && person.text.trim().isNotEmpty && minor > 0) {
      list.add(
        Debt(
          id: newId(),
          person: person.text.trim(),
          amountMinor: minor,
          currency: currency,
          lent: lent,
          due: due,
        ),
      );
      await save(list);
    }
    person.dispose();
    amount.dispose();
  }
}

/// A bottom sheet form; returns true when the user pressed Save.
Future<bool> _sheet(
  BuildContext context,
  String title,
  List<Widget> Function(StateSetter set) fields,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LText(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                ...fields(set),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const LText('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    ) ==
    true;
