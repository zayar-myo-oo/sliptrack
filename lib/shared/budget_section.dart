import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../app/state.dart';
import '../core/budgets.dart';
import '../core/categories.dart';
import '../core/exchange_rate.dart';
import '../core/models.dart';
import '../features/companion/coach_models.dart';
import '../features/companion/companion_card.dart';
import 'design.dart';
import 'motion.dart';
import 'localized_text.dart';

/// Monthly category budgets on the Overview, with the cat reacting to the
/// category closest to its limit.
class BudgetSection extends ConsumerWidget {
  const BudgetSection({required this.slips, required this.month, super.key});
  final List<Slip> slips;
  final DateTime month;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final coach = ref.watch(coachProvider);
    final limits = budgetLimits(prefs.values);
    final statuses = budgetStatus(
      slips,
      limits,
      month,
      prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros,
    );
    final worst = statuses.isEmpty ? null : statuses.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          LText(
            '${tr(context, 'Budgets')} · ${DateFormat('MMM', prefs.locale.languageCode).format(month)}',
          ),
          action: TextButton(
            onPressed: () => editBudgets(context, ref),
            child: LText(limits.isEmpty ? 'Set up' : 'Edit'),
          ),
        ),
        if (limits.isEmpty)
          Surface(
            onTap: () => editBudgets(context, ref),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Buddy(
                    mood: PetMood.happy,
                    progress: coach.progress,
                    outfit: coach.outfit,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LText(
                    'Set a monthly limit for food, transport and more. I’ll warn you before you go over.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Palette.muted(context),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Surface(
            child: Column(
              children: [
                if (worst != null && worst.tier > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Buddy(
                            mood: worst.tier == 2
                                ? PetMood.crying
                                : PetMood.worried,
                            progress: coach.progress,
                            outfit: coach.outfit,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            worst.tier == 2
                                ? '${tr(context, worst.category)}: ${tr(context, 'Over budget')}! ${tr(context, 'Let’s slow down spending.')}'
                                : '${tr(context, worst.category)}: ${tr(context, '80% of budget used')}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: worst.tier == 2
                                  ? Palette.expense
                                  : Palette.warn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final b in statuses) _BudgetRow(b),
              ],
            ),
          ),
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow(this.status);
  final BudgetStatus status;
  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(status.category);
    final color = status.tier == 2
        ? Palette.expense
        : status.tier == 1
        ? Palette.warn
        : style.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(style.icon, size: 18, color: style.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LText(
                        status.category,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${money(status.spent, 'THB')} / ${NumberFormat.decimalPattern().format(status.limit ~/ 100)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Palette.muted(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                GrowBar(
                  value: status.ratio,
                  height: 7,
                  color: color,
                  background: Palette.soft(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> editBudgets(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(preferencesProvider);
  final limits = budgetLimits(prefs.values);
  final controllers = {
    for (final c in expenseCategories)
      c.name: TextEditingController(
        text: limits[c.name] == null ? '' : '${limits[c.name]! ~/ 100}',
      ),
  };
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * .8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              LText(
                'Monthly budgets',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              LText(
                'THB per month · leave empty for no limit',
                style: TextStyle(fontSize: 12, color: Palette.muted(context)),
              ),
              const SizedBox(height: 14),
              for (final cat in expenseCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[cat.name],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      prefixIcon: Icon(cat.icon, color: cat.color),
                      labelText: tr(context, cat.name),
                      suffixText: 'THB',
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const LText('Save budgets'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (saved == true) {
    await prefs.update('categoryBudgets', {
      for (final e in controllers.entries)
        if ((int.tryParse(e.value.text) ?? 0) > 0)
          e.key: int.parse(e.value.text) * 100,
    });
    HapticFeedback.mediumImpact();
  }
  for (final c in controllers.values) {
    c.dispose();
  }
}
