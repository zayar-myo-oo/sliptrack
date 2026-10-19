import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/state.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
import '../../shared/components.dart';
import '../../shared/localized_text.dart';
import '../slip_recognition/parsers.dart';
import 'coach_models.dart';

class CompanionScreen extends ConsumerStatefulWidget {
  const CompanionScreen({super.key});
  @override
  ConsumerState<CompanionScreen> createState() => _CompanionState();
}

class _CompanionState extends ConsumerState<CompanionScreen> {
  final amount = TextEditingController(),
      goal = TextEditingController(),
      note = TextEditingController();
  final form = GlobalKey<FormState>();
  String currency = 'THB';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final n =
        ref.read(preferencesProvider).values['savingsGoalThbMinor'] ??
        defaultSavingsGoalThbMinor;
    goal.text = (n / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    amount.dispose();
    goal.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final prefs = ref.read(preferencesProvider);
      final target = parseMinor(goal.text)!;
      final entry = SavingsEntry.create(
        amountMinor: parseMinor(amount.text)!,
        currency: currency,
        date: DateTime.now(),
        rateMicros: prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros,
        goalThbMinor: target,
        note: note.text.trim(),
      );
      await prefs.update('savingsGoalThbMinor', target);
      await ref.read(repositoryProvider).saveSavings(entry);
      await ref.read(coachProvider).evaluate();
      amount.clear();
      note.clear();
      if (mounted) message(context, 'Savings recorded');
    } catch (_) {
      if (mounted) message(context, 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? positive(String? value) =>
      (parseMinor(value ?? '') ?? 0) <= 0 ||
          normalizeDigits(value ?? '').trim().startsWith('-')
      ? tr(context, 'Enter a positive amount')
      : null;
  @override
  Widget build(BuildContext context) {
    final coach = ref.watch(coachProvider),
        prefs = ref.watch(preferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const LText('Savings & companion')),
      body: ListenableBuilder(
        listenable: Listenable.merge([coach, prefs]),
        builder: (_, _) => Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Lv. ${coach.progress.level} / 10 • ${tr(context, 'Outfits')}: ${coach.progress.outfitsUnlocked}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: coach.progress.nextRewardProgress),
              const SizedBox(height: 12),
              const LText(
                'Add savings separately. Remaining income is not added to savings. Each goal earns a level up to 10; later goals unlock outfit colors. Earned rewards stay unlocked.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: goal,
                validator: positive,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: tr(context, 'Savings per reward (THB)'),
                ),
              ),
              const SizedBox(height: 12),
              const LText(
                'The goal and conversion rate are saved with each entry. Changes apply to new savings only.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('savingsAmount'),
                controller: amount,
                validator: positive,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: tr(context, 'Add savings'),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: currency,
                items: ['THB', 'MMK']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (c) => setState(() => currency = c!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                decoration: InputDecoration(
                  labelText: tr(context, 'Description'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : save,
                child: const LText('Save savings'),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const LText('Pay cycle spending alerts'),
                subtitle: const LText(
                  'Notify at 80% and 100% of pay cycle income',
                ),
                value: prefs.values['budgetAlertsEnabled'] == true,
                onChanged: (enabled) async {
                  try {
                    final allowed =
                        !enabled ||
                        await coach.notifications.permission(request: true);
                    if (allowed) {
                      await prefs.update('budgetAlertsEnabled', enabled);
                      await coach.evaluate();
                    } else if (context.mounted) {
                      message(
                        context,
                        'Allow notifications in device settings to receive alerts.',
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      message(
                        context,
                        'Notifications are unavailable on this device.',
                      );
                    }
                  }
                },
              ),
              const LText(
                'Alerts are checked when SlipTrack is open or receives imported records.',
              ),
              if (coach.progress.outfitsUnlocked > 0)
                Wrap(
                  spacing: 8,
                  children: List.generate(
                    (coach.progress.outfitsUnlocked + 1).clamp(1, 25),
                    (i) => ChoiceChip(
                      label: Text(
                        i == 0
                            ? tr(context, 'Original')
                            : '${tr(context, 'Outfit')} $i',
                      ),
                      selected: coach.outfit == i,
                      onSelected: (_) => prefs.update('petOutfit', i),
                    ),
                  ),
                ),
              if (coach.progress.outfitsUnlocked >= 25)
                TextFormField(
                  key: const Key('outfitNumber'),
                  decoration: InputDecoration(
                    labelText:
                        '${tr(context, 'Outfit')} 0–${coach.progress.outfitsUnlocked}',
                  ),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (v) async {
                    final i = int.tryParse(v);
                    if (i != null &&
                        i >= 0 &&
                        i <= coach.progress.outfitsUnlocked) {
                      await prefs.update('petOutfit', i);
                    }
                  },
                ),
              const SizedBox(height: 20),
              const LText('Savings history'),
              FutureBuilder<List<SavingsEntry>>(
                future: ref.read(repositoryProvider).savings(),
                builder: (_, snapshot) => Column(
                  children: (snapshot.data ?? [])
                      .map(
                        (e) => ListTile(
                          title: Text(money(e.amountMinor, e.currency)),
                          subtitle: Text(
                            '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')} • ${e.note}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const LText(
                                    'Delete this savings entry?',
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
                                await ref
                                    .read(repositoryProvider)
                                    .deleteSavings(e.id);
                                await coach.evaluate();
                              }
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
