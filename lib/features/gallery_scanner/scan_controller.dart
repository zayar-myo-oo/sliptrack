import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/models.dart';
import '../../database/database.dart';
import '../ocr/ocr_service.dart';
import '../slip_recognition/parsers.dart';

class ScanController extends ChangeNotifier {
  ScanController(this.repository, this.gallery, this.ocr);
  final Repository repository;
  final GalleryService gallery;
  final OCRService ocr;
  bool busy = false, paused = false, foreground = true, _discovering = false;
  int scanned = 0, imported = 0, duplicates = 0, failed = 0, ignored = 0;
  String status = 'Ready to import', permissionState = 'unknown';
  StreamSubscription<void>? _observer;
  Timer? _debounce;
  Future<void> setSince(DateTime date) async {
    await repository.patchSettings({
      'since': date.millisecondsSinceEpoch,
      'checkpoint': 0,
    });
    notifyListeners();
  }

  Future<void> initialize() async {
    for (final h in await repository.records('scan_history')) {
      scanned += (h['scanned'] as int?) ?? 0;
      imported += (h['imported'] as int?) ?? 0;
      duplicates += (h['duplicates'] as int?) ?? 0;
      failed += (h['failed'] as int?) ?? 0;
      ignored += (h['ignored'] as int?) ?? 0;
    }
    permissionState = await gallery.permission();
    await enqueue(await gallery.incoming(), manual: true);
    _observer = gallery.changes.listen(
      (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), () async {
          if (!foreground) return;
          await enqueue(await gallery.incoming(), manual: true);
          await catchUp();
        });
      },
      onError: (_) {
        status = 'Photo access changed. Recheck permissions.';
        notifyListeners();
      },
    );
    await catchUp();
  }

  Future<void> lifecycle(bool active) async {
    foreground = active;
    if (active) {
      await enqueue(await gallery.incoming(), manual: true);
      await catchUp();
      await process();
    }
  }

  Future<void> setAutomatic(bool enabled) async {
    final prefs = await repository.settings();
    if (enabled) {
      permissionState = await gallery.permission(request: true);
      paused = false;
    }
    prefs['automatic'] =
        enabled && ['full', 'limited'].contains(permissionState);
    await gallery.automatic(prefs['automatic']);
    await repository.patchSettings({'automatic': prefs['automatic']});
    if (prefs['automatic']) await catchUp();
    notifyListeners();
  }

  Future<void> enqueue(List<String> ids, {bool manual = false}) async {
    for (final source in ids) {
      final id = await repository.vault.fingerprint('queue:$source');
      if (!await repository.containsRecord('queue', id)) {
        final item = {
          'id': id,
          'source': source,
          'manual': manual,
          'state': 'pending',
          'attempts': 0,
        };
        await repository.put('queue', id, item);
      }
    }
  }

  Future<void> stop() async {
    paused = true;
    await setAutomatic(false);
    await (() async {
      while (busy || _discovering) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    })().timeout(const Duration(seconds: 30));
  }

  void resetAfterDeletion() {
    paused = false;
    scanned = imported = duplicates = failed = ignored = 0;
    status = 'Ready to import';
    notifyListeners();
  }

  Future<void> reviewFailed(Map<String, dynamic> item) async {
    final slip = Slip(id: newId(), source: item['source']);
    await repository.importSlip(slip);
    item['state'] = 'done';
    await repository.put('queue', item['id'], item);
    notifyListeners();
  }

  Future<void> pick() async {
    try {
      await enqueue(await gallery.pick(), manual: true);
      await process();
    } catch (_) {
      status = 'Photo import failed. Please try again.';
      notifyListeners();
    }
  }

  Future<void> catchUp({bool force = false, bool historical = false}) async {
    if (_discovering || !foreground) return;
    final prefs = await repository.settings();
    if (!force && prefs['automatic'] != true) {
      await process();
      return;
    }
    permissionState = await gallery.permission();
    if (!['full', 'limited'].contains(permissionState)) {
      status =
          'Photo access unavailable. Import Photos still works through the system picker.';
      notifyListeners();
      return;
    }
    _discovering = true;
    final start = DateTime.now().millisecondsSinceEpoch;
    final after =
        historical ||
            permissionState == 'limited' ||
            prefs['permission'] != permissionState
        ? 0
        : ((prefs['checkpoint'] as int?) ?? 0);
    try {
      var offset = 0;
      while (!paused && foreground) {
        final ids = await gallery.assets(
          afterMs: after > 1000 ? after - 1000 : 0,
          sinceMs: (prefs['since'] as int?) ?? 0,
          offset: offset,
        );
        await enqueue(ids);
        if (ids.length < 100) {
          prefs['checkpoint'] = start;
          prefs['permission'] = permissionState;
          await repository.patchSettings({
            'checkpoint': start,
            'permission': permissionState,
          });
          break;
        }
        offset += ids.length;
      }
    } catch (_) {
      status = 'Library scan interrupted. Resume to retry safely.';
    } finally {
      _discovering = false;
      notifyListeners();
    }
    await process();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
    if (!paused) {
      unawaited(catchUp(force: true));
    }
  }

  Future<void> retry() async {
    for (final item in await repository.queueItems('failed', limit: 1000000)) {
      if (item['state'] == 'failed') {
        item['state'] = 'pending';
        await repository.put('queue', item['id'], item);
      }
    }
    await process();
  }

  Future<void> process() async {
    if (busy || paused || !foreground) return;
    busy = true;
    status = 'Reading receipts on device';
    notifyListeners();
    final started = DateTime.now().toUtc();
    final before = [scanned, imported, duplicates, failed, ignored];
    try {
      final accounts = await repository.accounts();
      while (!paused && foreground) {
        final pending = await repository.queueItems('pending');
        if (pending.isEmpty) break;
        for (final item in pending) {
          if (paused || !foreground) break;
          if (item['state'] != 'pending') continue;
          try {
            final result = await ocr.recognizeText(item['source']);
            var slip = SlipRecognizer().parse(result.text);
            if (slip == null && item['manual'] != true) {
              item['state'] = 'ignored';
              ignored++;
            } else {
              slip ??= Slip(id: newId(), rawText: result.text);
              slip.source = item['source'];
              slip.imageHash = result.hash;
              slip.ocrConfidence = result.confidence;
              classify(slip, accounts);
              final outcome = await repository.importSlip(slip);
              if (outcome == ImportResult.duplicate) {
                duplicates++;
              } else {
                imported++;
              }
              item['state'] = 'done';
            }
          } catch (_) {
            item['state'] = 'failed';
            item['attempts'] = (item['attempts'] as int) + 1;
            failed++;
            // No OCR content, identifiers, or exception payloads in logs.
          }
          scanned++;
          await repository.put('queue', item['id'], item);
          notifyListeners();
        }
      }
      if (scanned != before[0]) {
        final id = newId();
        await repository.put('scan_history', id, {
          'id': id,
          'started': started.toIso8601String(),
          'finished': DateTime.now().toUtc().toIso8601String(),
          'scanned': scanned - before[0],
          'imported': imported - before[1],
          'review': imported - before[1],
          'duplicates': duplicates - before[2],
          'failed': failed - before[3],
          'ignored': ignored - before[4],
        });
      }
      status = paused
          ? 'Paused — progress saved'
          : 'Up to date · all imports await review';
    } catch (_) {
      status = 'Storage unavailable. Your queue will resume when reopened.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _observer?.cancel();
    super.dispose();
  }
}
