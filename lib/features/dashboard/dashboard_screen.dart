import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../core/income_cycle.dart';
import '../../shared/components.dart';
import '../../shared/estimated_cash_flow.dart';
import '../../shared/design.dart';
import '../../shared/motion.dart';
import '../../core/exchange_rate.dart';
import '../../core/plans.dart';
import '../companion/coach_models.dart';
import '../companion/companion_card.dart';
import 'home_extras.dart';
import '../../shared/budget_section.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<DashboardScreen> {
  String? account;
  bool payCycle = true;
  DateTime cycleDate = DateTime.now();
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    final data = ref.watch(slipsProvider);
    final accounts = ref.watch(accountsProvider).asData?.value ?? [];
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(
        child: LText(
          'Unable to open records. Restart after unlocking the device.',
        ),
      ),
      data: (all) {
        final cycle = IncomeCycle.fromIncome(cycleDate, all);
        final start = payCycle ? cycle.start : month;
        final end = payCycle
            ? cycle.end
            : DateTime(month.year, month.month + 1);
        bool inPeriod(DateTime? date) =>
            date != null && !date.isBefore(start) && date.isBefore(end);
        final scope = payCycle && !cycle.hasIncome(all)
            ? 'Add income to start'
            : payCycle
            ? '${DateFormat('d MMM yyyy').format(start)} – ${cycle.isOpen ? 'Next salary' : DateFormat('d MMM yyyy').format(end.subtract(const Duration(days: 1)))}'
            : DateFormat.yMMMM(prefs.locale.languageCode).format(month);
        final slips = all
            .where(
              (s) =>
                  (account == null || s.accountId == account) &&
                  inPeriod(s.date),
            )
            .toList();
        final totals = totalsFor(slips);
        final savedEntries = (ref.watch(savingsProvider).asData?.value ?? [])
            .where((entry) => inPeriod(entry.date));
        final savedThb = savedEntries.fold<int>(
          0,
          (sum, entry) => sum + entry.thbEquivalentMinor,
        );
        final review = slips
            .where((s) => s.review == ReviewStatus.pending)
            .length;
        final hour = DateTime.now().hour;
        final greeting = hour < 12
            ? 'Good morning'
            : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
        String monthQuery(String path) => payCycle
            ? path
            : '$path?month=${DateFormat('yyyy-MM').format(month)}';
        final canNextCycle = cycle.start.isBefore(
          IncomeCycle.fromIncome(DateTime.now(), all).start,
        );
        final coach = ref.watch(coachProvider);
        final rate = prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros;
        final current = IncomeCycle.fromIncome(DateTime.now(), all);
        final cycleSlips = all.where((s) => current.contains(s.date)).toList();
        final reserveNow = current.reserveThb(cycleSlips, rate);
        final life = BudgetLife.fromTotals(
          totalsFor(cycleSlips),
          rate,
          reserve: reserveNow,
        );
        final allowance = current.hasIncome(all)
            ? DailyAllowance.of(
                current,
                estimateInThb(totalsFor(cycleSlips), rate).net - reserveNow,
                DateTime.now(),
              )
            : null;
        int thbOf(Slip s) => s.currency == 'MMK'
            ? mmkToThbMinor(s.amountMinor ?? 0, rate)
            : s.amountMinor ?? 0;
        final today = DateTime.now();
        final spentToday = all
            .where(
              (s) =>
                  s.direction == Direction.expense &&
                  s.review == ReviewStatus.confirmed &&
                  s.date != null &&
                  s.date!.year == today.year &&
                  s.date!.month == today.month &&
                  s.date!.day == today.day,
            )
            .fold<int>(0, (n, s) => n + thbOf(s));
        final streak = allowance == null
            ? 0
            : spendingStreak(all, allowance.perDay, today, thbOf);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: staggered([
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LText(
                                    greeting,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Palette.muted(context),
                                    ),
                                  ),
                                  Text(
                                    'SlipTrack',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ],
                              ),
                            ),
                            Builder(
                              builder: (catContext) => SizedBox(
                                width: 60,
                                height: 60,
                                child: Buddy(
                                  mood: life.mood,
                                  progress: coach.progress,
                                  outfit: coach.outfit,
                                  onTap: () => showCatBubble(
                                    catContext,
                                    catTip(
                                      context,
                                      life: life,
                                      allowance: allowance,
                                      streak: streak,
                                      spentToday: spentToday,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: SegmentedButton<bool>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: LText('Pay cycle'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: LText('Calendar month'),
                                  ),
                                ],
                                selected: {payCycle},
                                onSelectionChanged: (value) =>
                                    setState(() => payCycle = value.single),
                              ),
                            ),
                            if (accounts.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                tooltip: tr(context, 'Account filter'),
                                initialValue: account ?? '',
                                onSelected: (v) => setState(
                                  () => account = v == '' ? null : v,
                                ),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: '',
                                    child: LText('All accounts'),
                                  ),
                                  for (final a in accounts)
                                    PopupMenuItem(
                                      value: a.id,
                                      child: Text(a.name),
                                    ),
                                ],
                                child: _RoundButton(
                                  icon: account == null
                                      ? Icons.filter_list_rounded
                                      : Icons.filter_alt_rounded,
                                  highlighted: account != null,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            IconButton(
                              key: Key(
                                payCycle ? 'cyclePrevious' : 'monthPrevious',
                              ),
                              tooltip: tr(
                                context,
                                payCycle ? 'Previous cycle' : 'Previous month',
                              ),
                              icon: const Icon(Icons.chevron_left_rounded),
                              onPressed: () => setState(() {
                                if (payCycle) {
                                  cycleDate = cycle.start.subtract(
                                    const Duration(days: 1),
                                  );
                                } else {
                                  month = DateTime(month.year, month.month - 1);
                                }
                              }),
                            ),
                            Expanded(
                              child: TextButton(
                                key: payCycle ? null : const Key('monthPicker'),
                                onPressed: payCycle
                                    ? null
                                    : () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: month,
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                          helpText: tr(context, 'Choose month'),
                                        );
                                        if (picked != null && mounted) {
                                          setState(
                                            () => month = DateTime(
                                              picked.year,
                                              picked.month,
                                            ),
                                          );
                                        }
                                      },
                                child: LText(
                                  scope,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Palette.text(context),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              key: Key(payCycle ? 'cycleNext' : 'monthNext'),
                              tooltip: tr(
                                context,
                                payCycle ? 'Next cycle' : 'Next month',
                              ),
                              icon: const Icon(Icons.chevron_right_rounded),
                              onPressed: payCycle
                                  ? canNextCycle
                                        ? () => setState(
                                            () => cycleDate = cycle.end,
                                          )
                                        : null
                                  : () => setState(
                                      () => month = DateTime(
                                        month.year,
                                        month.month + 1,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        EstimatedCashFlowCard(
                          allowance: payCycle ? allowance : null,
                          totals: totals,
                          scope: scope,
                          reserveThb: payCycle
                              ? cycle.reserveThb(
                                  slips,
                                  prefs.values['mmkPerThbMicros'] ?? 133000000,
                                )
                              : 0,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            for (final action in [
                              (
                                Icons.document_scanner_outlined,
                                'Scan slip',
                                '/scan',
                              ),
                              (
                                Icons.add_rounded,
                                'Add income',
                                monthQuery('/income'),
                              ),
                              (
                                Icons.remove_rounded,
                                'Add expense',
                                monthQuery('/expense'),
                              ),
                            ])
                              Expanded(
                                child: _QuickAction(
                                  onLongPress: action.$2 == 'Add expense'
                                      ? () => showQuickAdd(context, ref)
                                      : null,
                                  icon: action.$1,
                                  label: action.$2,
                                  onTap: () => action.$3 == '/scan'
                                      ? context.go('/scan')
                                      : context.push(action.$3),
                                ),
                              ),
                          ],
                        ),
                        const PlansStrip(),
                        RecapBanner(slips: all),
                        if (review > 0)
                          _Banner(
                            icon: Icons.fact_check_outlined,
                            color: Palette.warn,
                            title: '$review ${prefs.text('Needs review')}',
                            subtitle:
                                'Check extracted details before they affect totals',
                            onTap: () => context.go(
                              payCycle
                                  ? '/scan'
                                  : '/transactions?review=true&month=${DateFormat('yyyy-MM').format(month)}',
                            ),
                          ),
                        if (payCycle && !cycle.hasIncome(all))
                          _Banner(
                            icon: Icons.account_balance_wallet_outlined,
                            color: Palette.brand,
                            title: prefs.text(
                              'Add income to start this pay cycle',
                            ),
                            onTap: () => context.push('/income'),
                          ),
                        Surface(
                          onTap: () => context.push('/companion'),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Palette.incomeSoft(context),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.savings_outlined,
                                  color: Palette.income,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const LText(
                                      'Recorded savings',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    LText(
                                      savedEntries.isEmpty
                                          ? 'No savings recorded in this period'
                                          : 'Approximate THB · saved rates',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Palette.muted(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '≈ ${money(savedThb, 'THB')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        BudgetSection(
                          slips: all,
                          month: payCycle
                              ? DateTime(
                                  DateTime.now().year,
                                  DateTime.now().month,
                                )
                              : month,
                        ),
                        SectionHeader(
                          const LText('Recent activity'),
                          action: TextButton(
                            onPressed: () => context.go('/transactions'),
                            child: const LText('See all'),
                          ),
                        ),
                        if (slips.isEmpty)
                          Surface(
                            child: EmptyState(
                              payCycle
                                  ? 'No receipts in this pay cycle'
                                  : 'No receipts in this month',
                              'Scan a slip or add income to get started.',
                            ),
                          )
                        else
                          SlipGroup(slips.take(5)),
                        if (totals.length > 1) ...[
                          const SectionHeader(LText('Original currencies')),
                          Surface(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Column(
                              children: [
                                for (final e in totals.entries)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          e.key,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '+${money(e.value.income, e.key)}  −${money(e.value.expense, e.key)}',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Palette.muted(context),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          money(e.value.net, e.key),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, this.highlighted = false});
  final IconData icon;
  final bool highlighted;
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: highlighted
          ? Theme.of(context).colorScheme.primaryContainer
          : Palette.surface(context),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 21, color: Palette.text(context)),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });
  final VoidCallback? onLongPress;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Pressable(
      child: Material(
        color: Palette.surface(context),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Palette.soft(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: Palette.text(context)),
                ),
                const SizedBox(height: 8),
                LText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Surface(
      onTap: onTap,
      color: color.withValues(alpha: .1),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null)
                  LText(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Palette.muted(context),
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: color),
        ],
      ),
    ),
  );
}
