import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'exchange_rate.dart';
import 'income_cycle.dart';
import 'models.dart';
import 'strings.dart';
import '../features/companion/coach_models.dart';

const _channel = MethodChannel('app.sliptrack/widget');
String? _last;

/// Pushes the current pay cycle summary to the iOS home screen widget.
/// Amounts are hidden while app lock is on.
Future<void> syncHomeWidget(
  List<Slip> slips,
  Map<String, dynamic> settings,
) async {
  final rate = (settings['mmkPerThbMicros'] as int?) ?? defaultMmkPerThbMicros;
  final language = (settings['language'] as String?) ?? 'en';
  final now = DateTime.now();
  final cycle = IncomeCycle.fromIncome(now, slips);
  final inCycle = slips.where((s) => cycle.contains(s.date)).toList();
  final reserve = cycle.reserveThb(inCycle, rate);
  final estimate = estimateInThb(totalsFor(inCycle), rate);
  final life = BudgetLife.fromTotals(
    totalsFor(inCycle),
    rate,
    reserve: reserve,
  );
  final available = estimate.net - reserve;
  String thb(int minor) =>
      '${NumberFormat.decimalPattern().format((minor / 100).round())} THB';
  final snapshot = <String, Object>{
    'remaining': '≈ ${thb(available)}',
    'spent': thb(estimate.expense),
    'income': thb(estimate.income),
    'percent': estimate.income <= 0
        ? 0.0
        : (available / estimate.income).clamp(0, 1).toDouble(),
    'mood': life.mood.name,
    'period': cycle.hasIncome(slips)
        ? '${translate(language, 'Pay cycle')} · ${DateFormat('d MMM').format(cycle.start)}'
        : translate(language, 'Pay cycle'),
    'hidden': settings['lock'] == true,
    'empty': !cycle.hasIncome(slips),
  };
  final key = snapshot.toString();
  if (key == _last) return;
  try {
    await _channel.invokeMethod('update', snapshot);
    _last = key;
  } on MissingPluginException {
    /* Android and tests have no widget. */
  } on PlatformException {
    /* The widget is optional; the journal never depends on it. */
  }
}
