import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
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
        settings = await repo.settings();
        final entries = await repo.savings();
        final xp = entries.fold<int>(0, (sum, e) => sum + e.xpMicros);
        progress = PetProgress(
          xpMicros: xp,
          highestMilestones: (settings['petHighestMilestones'] as int?) ?? 0,
        );
        if (progress.earnedMilestones != settings['petHighestMilestones']) {
          await repo.patchSettings({
            'petHighestMilestones': progress.earnedMilestones,
          });
          settings['petHighestMilestones'] = progress.earnedMilestones;
        }
        if (settings['budgetAlertsEnabled'] == true &&
            await notifications.permission()) {
          final current = now ?? DateTime.now();
          final key =
              '${current.year}-${current.month.toString().padLeft(2, '0')}';
          final totals = totalsFor(await repo.slips(), month: current);
          final life = BudgetLife.fromTotals(
            totals,
            (settings['mmkPerThbMicros'] as int?) ?? defaultMmkPerThbMicros,
          );
          final sent = Map<String, dynamic>.from(
            settings['sentBudgetTiers'] ?? {},
          );
          if (life.alertTier > ((sent[key] as int?) ?? 0)) {
            final language = settings['language'] ?? 'en';
            final body = life.alertTier == 2
                ? 'This month\'s spending has reached your income. Open SlipTrack to review.'
                : 'You have used 80% of this month\'s income. Open SlipTrack to review.';
            final delivered = await notifications.show(
              id: current.year * 100 + current.month,
              title: translate(language, 'Monthly spending alert'),
              body: translate(language, body),
            );
            if (delivered) {
              sent[key] = life.alertTier;
              await repo.patchSettings({'sentBudgetTiers': sent});
            }
          }
        }
        if (!_disposed) notifyListeners();
      } while (_again && !_disposed);
    } catch (_) {
      /* Keep financial content out of logs. OS notification denial never blocks the journal. */
    } finally {
      _running = false;
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
