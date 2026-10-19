import '../core/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models.dart';
import '../database/database.dart';
import '../features/gallery_scanner/scan_controller.dart';
import '../features/ocr/ocr_service.dart';
import '../features/companion/coach_controller.dart';

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
final slipsProvider = StreamProvider<List<Slip>>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  yield await repo.slips();
  await for (final _ in repo.changes.stream) {
    yield await repo.slips();
  }
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
  Future<void> reset() async {
    values.clear();
    notifyListeners();
  }
}

final preferencesProvider = Provider<Preferences>(
  (ref) => throw UnimplementedError('Override at bootstrap'),
);
