import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../slip_recognition/parsers.dart';
import '../../shared/components.dart';
import '../../shared/localized_text.dart';
import '../../shared/design.dart';
import '../../core/categories.dart';
import 'package:flutter/services.dart';

class IncomeScreen extends ConsumerStatefulWidget {
  const IncomeScreen({
    this.id,
    this.initialMonth,
    this.expense = false,
    super.key,
  });
  final bool expense;
  final String? id;
  final DateTime? initialMonth;
  @override
  ConsumerState<IncomeScreen> createState() => _IncomeState();
}

class _IncomeState extends ConsumerState<IncomeScreen> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), note = TextEditingController();
  final reserve = TextEditingController(text: '0');
  String currency = 'THB', category = 'Salary';
  DateTime date = DateTime.now();
  Slip? original;
  bool loading = false, saving = false;
  @override
  void initState() {
    super.initState();
    if (widget.expense) category = 'Food';
    final month = widget.initialMonth;
    if (month != null &&
        (month.month != date.month || month.year != date.year)) {
      date = DateTime(month.year, month.month);
    }
    if (widget.id != null) {
      loading = true;
      load();
    }
  }

  Future<void> load() async {
    final existing = (await ref.read(repositoryProvider).slips())
        .where(
          (s) =>
              s.id == widget.id &&
              (widget.expense ? s.isManualExpense : s.isManualIncome),
        )
        .firstOrNull;
    if (!mounted) return;
    if (existing == null) {
      context.pop();
      return;
    }
    original = existing;
    currency = existing.currency;
    category = existing.category;
    date = existing.date!;
    amount.text =
        '${existing.amountMinor! ~/ 100}.${(existing.amountMinor! % 100).toString().padLeft(2, '0')}';
    reserve.text = (existing.savingsReserveMinor / 100).toStringAsFixed(2);
    note.text = existing.description;
    setState(() => loading = false);
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final s =
          original ??
          Slip(
            id: newId(),
            isManualIncome: !widget.expense,
            isManualExpense: widget.expense,
          );
      s.savingsReserveMinor = widget.expense ? 0 : parseMinor(reserve.text)!;
      s.amountMinor = parseMinor(amount.text);
      s.currency = currency;
      s.date = date;
      s.zone = currency == 'MMK' ? 'Asia/Yangon' : 'Asia/Bangkok';
      s.direction = widget.expense ? Direction.expense : Direction.income;
      s.review = ReviewStatus.confirmed;
      s.description = note.text.trim();
      s.category = category;
      s.type = widget.expense ? 'Manual expense' : 'Manual income';
      s.receiver = widget.expense ? category : 'Manual income';
      await ref.read(repositoryProvider).saveSlip(s);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) message(context, 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    reserve.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LText(widget.expense ? 'Manual expense' : 'Manual income'),
      actions: [
        if (widget.id != null)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: saving
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: LText(
                          widget.expense
                              ? 'Delete this expense?'
                              : 'Delete this income?',
                        ),
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
                    );
                    if (ok == true) {
                      await ref.read(repositoryProvider).deleteSlip(widget.id!);
                      if (context.mounted) context.pop();
                    }
                  },
          ),
      ],
    ),
    bottomNavigationBar: loading
        ? null
        : SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton(
              onPressed: saving
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      save();
                    },
              child: LText(widget.expense ? 'Save expense' : 'Save income'),
            ),
          ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: widget.expense
                        ? Palette.expenseSoft(context)
                        : Palette.incomeSoft(context),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    children: [
                      LText(
                        widget.expense
                            ? 'How much did you spend?'
                            : 'How much came in?',
                        style: TextStyle(
                          fontSize: 13,
                          color: Palette.muted(context),
                        ),
                      ),
                      TextFormField(
                        key: Key(
                          widget.expense ? 'expenseAmount' : 'incomeAmount',
                        ),
                        controller: amount,
                        autofocus: widget.id == null,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          color: widget.expense
                              ? Palette.expense
                              : Palette.income,
                        ),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          filled: false,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintStyle: TextStyle(
                            color: Palette.muted(context).withValues(alpha: .5),
                          ),
                        ),
                        validator: (v) =>
                            (parseMinor(v ?? '') ?? 0) <= 0 ||
                                normalizeDigits(v ?? '').trim().startsWith('-')
                            ? tr(context, 'Enter a positive amount')
                            : null,
                      ),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          for (final c in ['THB', 'MMK'])
                            ButtonSegment(value: c, label: Text(c)),
                        ],
                        selected: {currency},
                        onSelectionChanged: (v) =>
                            setState(() => currency = v.first),
                      ),
                    ],
                  ),
                ),
                const SectionHeader(LText('Category')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name
                        in widget.expense
                            ? expenseCategories.map((c) => c.name)
                            : incomeCategories)
                      ChoiceChip(
                        avatar: widget.expense
                            ? Icon(
                                categoryStyle(name).icon,
                                size: 18,
                                color: categoryStyle(name).color,
                              )
                            : null,
                        label: LText(name),
                        selected: category == name,
                        showCheckmark: false,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => category = name);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Surface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.event_rounded),
                        title: const LText('Date'),
                        trailing: Text(
                          DateFormat.yMMMd().format(date),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        onTap: () async {
                          final chosen = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (chosen != null && mounted) {
                            setState(() => date = chosen);
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: TextFormField(
                          controller: note,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.notes_rounded),
                            hintText: tr(context, 'Description'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.expense) ...[
                  const SectionHeader(LText('Savings plan')),
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          'Salary starts a new period on this date, until your next salary. Set aside your savings plan before spending.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Palette.muted(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          key: const Key('savingsReserve'),
                          controller: reserve,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.savings_outlined),
                            labelText:
                                '${tr(context, 'Savings to set aside')} ($currency)',
                            helperText: tr(
                              context,
                              'Reserved from spending. Not recorded as actual savings.',
                            ),
                          ),
                          validator: (v) {
                            final n = parseMinor(v ?? '');
                            return n == null ||
                                    normalizeDigits(
                                      v ?? '',
                                    ).trim().startsWith('-') ||
                                    n > (parseMinor(amount.text) ?? 0)
                                ? tr(
                                    context,
                                    'Enter an amount from 0 to your income',
                                  )
                                : null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
  );
}
