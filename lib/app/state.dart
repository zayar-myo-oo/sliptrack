import 'dart:async';
import '../core/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models.dart';
import '../database/database.dart';
import '../features/gallery_scanner/scan_controller.dart';
import '../features/ocr/ocr_service.dart';
import '../features/companion/coach_controller.dart';
import '../features/companion/coach_models.dart';

final coachProvider = Provider<CoachController>((ref) {
  final coach = CoachController(
    ref.watch(repositoryProvider),
    ref.watch(preferencesProvider),
    NativeBudgetNotifications(),
  );
  ref.onDispose(coach.dispose);
  return coach;
});

final repositoryProvider = Provider<Repository>(
  (ref) => throw UnimplementedError('Override at bootstrap'),
);
// Subscribe before the first database read so an import during loading cannot
// disappear until the next unrelated change. Serialize reads to keep order.
Stream<T> watchRepository<T>(Repository repo, Future<T> Function() read) =>
    Stream<T>.multi((controller) {
      var cancelled = false;
      Future<void> pending = Future.value();
      void refresh() {
        pending = pending.then((_) async {
          if (cancelled) return;
          try {
            final value = await read();
            if (!cancelled) controller.add(value);
          } catch (error, stack) {
            if (!cancelled) controller.addError(error, stack);
          }
        });
      }

      final subscription = repo.changes.stream.listen((_) => refresh());
      controller.onCancel = () async {
        cancelled = true;
        await subscription.cancel();
      };
      refresh();
    });
final slipsProvider = StreamProvider<List<Slip>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return watchRepository(repo, repo.slips);
});
final savingsProvider = StreamProvider<List<SavingsEntry>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return watchRepository(repo, repo.savings);
});
final accountsProvider = FutureProvider<List<Account>>(
  (ref) => ref.watch(repositoryProvider).accounts(),
);
final scannerProvider = Provider<ScanController>((ref) {
  final scanner = ScanController(
    ref.watch(repositoryProvider),
    NativeGallery(),
    OnDeviceOCR(),
  );
  ref.onDispose(scanner.dispose);
  return scanner;
});

class Preferences extends ChangeNotifier {
  Preferences(this.repo, this.values);
  final Repository repo;
  final Map<String, dynamic> values;
  Locale get locale => Locale(values['language'] ?? 'en');
  ThemeMode get theme => ThemeMode.values.byName(values['theme'] ?? 'system');
  Future<void> update(String key, dynamic value) async {
    await updateAll({key: value});
  }

  Future<void> updateAll(Map<String, dynamic> values) async {
    final latest = await repo.patchSettings(values);
    this.values.addAll(latest);
    notifyListeners();
  }

  String text(String english) => translate(locale.languageCode, english);
  Future<void> reload() async {
    final latest = await repo.settings();
    values
      ..clear()
      ..addAll(latest);
    notifyListeners();
  }

  Future<void> reset() async {
    values.clear();
    notifyListeners();
  }
}

final preferencesProvider = Provider<Preferences>(
  (ref) => throw UnimplementedError('Override at bootstrap'),
);
