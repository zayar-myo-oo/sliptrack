import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../slip_recognition/parsers.dart';
import '../../shared/components.dart';
import '../../shared/localized_text.dart';

class IncomeScreen extends ConsumerStatefulWidget {
  const IncomeScreen({this.id, this.initialMonth, super.key});
  final String? id;
  final DateTime? initialMonth;
  @override
  ConsumerState<IncomeScreen> createState() => _IncomeState();
}

class _IncomeState extends ConsumerState<IncomeScreen> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), note = TextEditingController();
  String currency = 'THB', category = 'Salary';
  DateTime date = DateTime.now();
  Slip? original;
  bool loading = false, saving = false;
  @override
  void initState() {
    super.initState();
    final month = widget.initialMonth;
    if (month != null && (month.month != date.month || month.year != date.year))
      date = DateTime(month.year, month.month);
    if (widget.id != null) {
      loading = true;
      load();
    }
  }

  Future<void> load() async {
    final existing = (await ref.read(repositoryProvider).slips())
        .where((s) => s.id == widget.id && s.isManualIncome)
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
    note.text = existing.description;
    setState(() => loading = false);
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final s = original ?? Slip(id: newId(), isManualIncome: true);
      s.amountMinor = parseMinor(amount.text);
      s.currency = currency;
      s.date = date;
      s.zone = currency == 'MMK' ? 'Asia/Yangon' : 'Asia/Bangkok';
      s.direction = Direction.income;
      s.review = ReviewStatus.confirmed;
      s.description = note.text.trim();
      s.category = category;
      s.type = 'Manual income';
      s.receiver = 'Manual income';
      await ref.read(repositoryProvider).saveSlip(s);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) message(context, 'Could not save income. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LText('Manual income'),
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
                        title: const LText('Delete this income?'),
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
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const LText(
                  'Enter income yourself. It is recorded only in the month of the date below.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('incomeAmount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: tr(context, 'Amount')),
                  validator: (v) =>
                      (parseMinor(v ?? '') ?? 0) <= 0 ||
                          (v ?? '').startsWith('-')
                      ? tr(context, 'Enter a positive amount')
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: currency,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Currency'),
                  ),
                  items: ['THB', 'MMK']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => currency = v!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const LText('Date'),
                  subtitle: Text(DateFormat.yMMMd().format(date)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (chosen != null) setState(() => date = chosen);
                  },
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Category'),
                  ),
                  items: ['Salary', 'Extra income', 'Gift', 'Other income']
                      .map((c) => DropdownMenuItem(value: c, child: LText(c)))
                      .toList(),
                  onChanged: (v) => category = v!,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Description'),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: const LText('Save income'),
                ),
              ],
            ),
          ),
  );
}
