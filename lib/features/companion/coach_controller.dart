import '../../core/budgets.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
import '../../core/income_cycle.dart';
import '../../core/strings.dart';
import '../../database/database.dart';
import 'coach_models.dart';

abstract interface class BudgetNotifications {
  Future<bool> permission({bool request = false});
  Future<bool> show({
    required int id,
    required String title,
    required String body,
  });
}

class NativeBudgetNotifications implements BudgetNotifications {
  static const channel = MethodChannel('app.sliptrack/media');
  @override
  Future<bool> permission({bool request = false}) async =>
      await channel.invokeMethod<bool>('notificationPermission', {
        'request': request,
      }) ??
      false;
  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
  }) async =>
      await channel.invokeMethod<bool>('notifyBudget', {
        'id': id,
        'title': title,
        'body': body,
      }) ??
      false;
}

class CoachController extends ChangeNotifier {
  CoachController(this.repo, this.preferenceChanges, this.notifications);
  final Repository repo;
  final Listenable preferenceChanges;
  final BudgetNotifications notifications;
  PetProgress progress = PetProgress(xpMicros: 0, highestMilestones: 0);
  Map<String, dynamic> settings = {};
  int get outfit =>
      ((settings['petOutfit'] as int?) ?? 0).clamp(0, progress.outfitsUnlocked);
  bool _started = false, _running = false, _again = false, _disposed = false;
  StreamSubscription<void>? _subscription;
  void _schedule() {
    unawaited(evaluate());
  }

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    _subscription = repo.changes.stream.listen((_) => _schedule());
    preferenceChanges.addListener(_schedule);
    await evaluate();
  }

  Future<void> evaluate({DateTime? now}) async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        progress = await repo.petProgress();
        settings = await repo.settings();
        if (settings['budgetAlertsEnabled'] == true &&
            await notifications.permission()) {
          final current = now ?? DateTime.now();
          final slips = await repo.slips();
          final cycle = IncomeCycle.fromIncome(current, slips);
          final key = 'cycle:${cycle.key}';
          final totals = totalsFor(slips.where((s) => cycle.contains(s.date)));
          final life = BudgetLife.fromTotals(
            totals,
            (settings['mmkPerThbMicros'] as int?) ?? defaultMmkPerThbMicros,
          );
          final sent = Map<String, dynamic>.from(
            settings['sentBudgetTiers'] ?? {},
          );
          for (
            var tier = ((sent[key] as int?) ?? 0) + 1;
            tier <= life.alertTier;
            tier++
          ) {
            final language = settings['language'] ?? 'en';
            final body = tier == 2
                ? 'This pay cycle\'s spending has reached your income. Open SlipTrack to review.'
                : 'You have used 80% of this pay cycle\'s income. Open SlipTrack to review.';
            final accepted = await notifications.show(
              id: cycle.notificationId * 10 + tier,
              title: translate(language, 'Pay cycle spending alert'),
              body: translate(language, body),
            );
            if (accepted) {
              sent[key] = tier;
              await repo.patchSettings({'sentBudgetTiers': sent});
            } else {
              break;
            }
          }
        }
        if (settings['budgetAlertsEnabled'] == true &&
            budgetLimits(settings).isNotEmpty &&
            await notifications.permission()) {
          await _categoryAlerts(now ?? DateTime.now());
        }
        if (!_disposed) notifyListeners();
      } while (_again && !_disposed);
    } catch (_) {
      /* Keep financial content out of logs. OS notification denial never blocks the journal. */
    } finally {
      _running = false;
    }
  }

  /// Sends at most one 80% and one 100% alert per category each month.
  Future<void> _categoryAlerts(DateTime now) async {
    final language = settings['language'] ?? 'en';
    final month = '${now.year}-${now.month}';
    final sent = Map<String, dynamic>.from(
      settings['sentCategoryAlerts'] ?? {},
    );
    final statuses = budgetStatus(
      await repo.slips(),
      budgetLimits(settings),
      now,
      (settings['mmkPerThbMicros'] as int?) ?? defaultMmkPerThbMicros,
    );
    for (final b in statuses) {
      final key = '$month:${b.category}';
      if (b.tier == 0 || ((sent[key] as int?) ?? 0) >= b.tier) continue;
      final category = translate(language, b.category);
      final body = b.tier == 2
          ? '${translate(language, 'Over budget')}: $category'
          : '${translate(language, '80% of budget used')}: $category';
      final accepted = await notifications.show(
        id: 900000 + (key.hashCode & 0xffff) * 3 + b.tier,
        title: translate(language, 'Budget alert'),
        body: body,
      );
      if (!accepted) break;
      sent[key] = b.tier;
      await repo.patchSettings({'sentCategoryAlerts': sent});
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    preferenceChanges.removeListener(_schedule);
    super.dispose();
  }
}
