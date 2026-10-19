import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/state.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
import '../../shared/components.dart';
import '../../shared/localized_text.dart';
import '../../shared/design.dart';
import 'package:flutter/services.dart';
import 'companion_card.dart';
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
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Palette.brand, Palette.brandDeep],
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .08),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Buddy(
                        mood: PetMood.happy,
                        progress: coach.progress,
                        outfit: coach.outfit,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${tr(context, 'Level')} ${coach.progress.level}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 10; i++)
                          Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i <= coach.progress.level
                                  ? const Color(0xffffcf5a)
                                  : Colors.white.withValues(alpha: .15),
                              shape: BoxShape.circle,
                            ),
                            child: i <= coach.progress.level
                                ? const Icon(
                                    Icons.star_rounded,
                                    size: 13,
                                    color: Color(0xff8a5a00),
                                  )
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: coach.progress.nextRewardProgress,
                        minHeight: 10,
                        color: const Color(0xffffcf5a),
                        backgroundColor: Colors.white.withValues(alpha: .15),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(coach.progress.nextRewardProgress * 100).round()}% ${tr(context, 'to the next reward')}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader(LText('Add savings')),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('savingsAmount'),
                      controller: amount,
                      validator: positive,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Palette.income,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(hintText: '0.00'),
                    ),
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: note,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.notes_rounded),
                        hintText: tr(context, 'Description'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              save();
                            },
                      icon: const Icon(Icons.savings_outlined),
                      label: const LText('Save savings'),
                    ),
                  ],
                ),
              ),
              if (coach.progress.outfitsUnlocked > 0) ...[
                const SectionHeader(LText('Wardrobe')),
                Surface(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (
                        var i = 0;
                        i <= coach.progress.outfitsUnlocked.clamp(0, 24);
                        i++
                      )
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            prefs.update('petOutfit', i);
                          },
                          child: Container(
                            width: 64,
                            height: 64,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Palette.soft(context),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: coach.outfit == i
                                    ? Palette.accent(context)
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: Buddy(
                              mood: PetMood.happy,
                              progress: coach.progress,
                              outfit: i,
                              compact: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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
              const SectionHeader(LText('Settings')),
              Surface(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: TextFormField(
                        controller: goal,
                        validator: positive,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.flag_rounded),
                          labelText: tr(context, 'Savings per reward (THB)'),
                          helperText: tr(
                            context,
                            'Each goal earns a level up to 10; later goals unlock outfits.',
                          ),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: const LText('Spending alerts'),
                      subtitle: const LText(
                        'Pay cycle at 80% and 100%, plus category budgets',
                      ),
                      value: prefs.values['budgetAlertsEnabled'] == true,
                      onChanged: (enabled) async {
                        try {
                          final allowed =
                              !enabled ||
                              await coach.notifications.permission(
                                request: true,
                              );
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
                  ],
                ),
              ),
              const SectionHeader(LText('Savings history')),
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
