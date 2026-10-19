import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/models.dart';
import '../core/data_groups.dart';
import '../core/vault.dart';
import '../core/backup.dart';
import '../features/companion/coach_models.dart';

// Custom SQL deliberately keeps financial payloads encrypted, including names,
// amounts and dates. Only random IDs and keyed lookup digests are indexed.
class SlipDatabase extends GeneratedDatabase {
  SlipDatabase(super.executor);
  @override
  int get schemaVersion => 4;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  static const entities = [
    'accounts',
    'transactions',
    'categories',
    'settings',
    'scan_history',
    'queue',
    'savings',
  ];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final table in entities) {
        await customStatement(
          'CREATE TABLE $table (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        );
      }
      await createLookups();
      await createQueueIndex();
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) await createLookups();
      if (from < 3) await createQueueIndex();
      if (from < 4) {
        await customStatement(
          'CREATE TABLE savings (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        );
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA secure_delete = ON');
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
  Future<void> createLookups() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS lookups (kind TEXT NOT NULL, digest TEXT NOT NULL, record_id TEXT NOT NULL, PRIMARY KEY(kind,digest,record_id))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS lookup_record ON lookups(record_id)',
    );
  }

  Future<void> createQueueIndex() async {
    await customStatement(
      "ALTER TABLE queue ADD COLUMN work_state TEXT NOT NULL DEFAULT 'pending'",
    );
    await customStatement('CREATE INDEX queue_work_state ON queue(work_state)');
  }
}

enum ImportResult { inserted, duplicate, possibleDuplicate }

class Repository {
  Repository(this.db, this.vault);
  final SlipDatabase db;
  final Vault vault;
  final changes = StreamController<void>.broadcast();
  static Future<Repository> open() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'sliptrack.sqlite'));
    final vault = await Vault.open(requireExisting: await file.exists());
    return Repository(
      SlipDatabase(NativeDatabase.createInBackground(file)),
      vault,
    );
  }

  Future<List<Map<String, dynamic>>> records(String table) async {
    _checkTable(table);
    final rows = await db.customSelect('SELECT id,payload FROM $table').get();
    return Future.wait(
      rows.map(
        (row) => vault.unseal(
          row.read<String>('payload'),
          '$table:${row.read<String>('id')}',
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> record(String table, String id) async {
    _checkTable(table);
    final row = await db
        .customSelect(
          'SELECT payload FROM $table WHERE id=?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : vault.unseal(row.read<String>('payload'), '$table:$id');
  }

  Future<String?> existingSlipId({
    required String source,
    String hash = '',
  }) async {
    for (final entry in {'source': source, 'hash': hash}.entries) {
      if (entry.value.isEmpty) continue;
      final row = await db
          .customSelect(
            'SELECT record_id FROM lookups WHERE kind=? AND digest=? LIMIT 1',
            variables: [
              Variable(entry.key),
              Variable(await vault.fingerprint(entry.value)),
            ],
          )
          .getSingleOrNull();
      if (row != null) return row.read<String>('record_id');
    }
    return null;
  }

  Future<void> put(String table, String id, Map<String, dynamic> value) async {
    _checkTable(table);
    final encrypted = await vault.seal(value, '$table:$id');
    await db.customStatement(
      'INSERT INTO $table(id,payload) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
      [id, encrypted],
    );
    if (table == 'queue') {
      await db.customStatement('UPDATE queue SET work_state=? WHERE id=?', [
        value['state'] ?? 'pending',
        id,
      ]);
    }
  }

  Future<List<Map<String, dynamic>>> queueItems(
    String state, {
    int limit = 100,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT id,payload FROM queue WHERE work_state=? LIMIT ?',
          variables: [Variable(state), Variable(limit)],
        )
        .get();
    final values = await Future.wait(
      rows.map(
        (r) => vault.unseal(
          r.read<String>('payload'),
          'queue:${r.read<String>('id')}',
        ),
      ),
    );
    for (final value in values.where((v) => v['state'] != state)) {
      await db.customStatement('UPDATE queue SET work_state=? WHERE id=?', [
        value['state'],
        value['id'],
      ]);
    }
    final matched = values.where((v) => v['state'] == state).toList();
    if (matched.isEmpty && rows.length == limit) {
      return queueItems(state, limit: limit);
    }
    return matched;
  }

  void _checkTable(String table) {
    if (!SlipDatabase.entities.contains(table)) {
      throw ArgumentError('Unknown table');
    }
  }

  Future<bool> containsRecord(String table, String id) async {
    _checkTable(table);
    return (await db
            .customSelect(
              'SELECT id FROM $table WHERE id=?',
              variables: [Variable(id)],
            )
            .get())
        .isNotEmpty;
  }

  Future<List<Slip>> slips() async =>
      (await records('transactions')).map(Slip.fromJson).toList()..sort(
        (a, b) => (b.date ?? b.createdAt).compareTo(a.date ?? a.createdAt),
      );
  Future<List<Account>> accounts() async =>
      (await records('accounts')).map(Account.fromJson).toList();
  Future<List<SavingsEntry>> savings() async =>
      (await records('savings')).map(SavingsEntry.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  Future<void> saveSavings(SavingsEntry entry) async {
    if (entry.amountMinor <= 0 ||
        entry.goalThbMinor <= 0 ||
        entry.rateMicros <= 0 ||
        entry.xpMicros < 0 ||
        !['THB', 'MMK'].contains(entry.currency)) {
      throw ArgumentError('Invalid savings');
    }
    await db.transaction(() async {
      await _updatePetProgress();
      await put('savings', entry.id, entry.toJson());
      await _updatePetProgress();
    });
    changes.add(null);
  }

  Future<void> deleteSavings(String id) async {
    await db.transaction(() async {
      // Capture earned rewards before removing their source, even if the UI
      // controller has not observed the most recent savings change yet.
      await _updatePetProgress();
      await db.customStatement('DELETE FROM savings WHERE id=?', [id]);
    });
    changes.add(null);
  }

  Future<PetProgress> petProgress() => db.transaction(_updatePetProgress);
  Future<PetProgress> _updatePetProgress() async {
    final current = await settings();
    final progress = PetProgress(
      xpMicros: (await savings()).fold<int>(
        0,
        (sum, entry) => sum + entry.xpMicros,
      ),
      highestMilestones: (current['petHighestMilestones'] as int?) ?? 0,
    );
    if (progress.earnedMilestones != current['petHighestMilestones']) {
      current['petHighestMilestones'] = progress.earnedMilestones;
      await setSettings(current);
    }
    return progress;
  }

  Future<Map<String, dynamic>> settings() async =>
      (await records('settings')).firstOrNull ?? {};
  Future<void> setSettings(Map<String, dynamic> settings) =>
      put('settings', 'preferences', settings);
  Future<Map<String, dynamic>> patchSettings(Map<String, dynamic> values) =>
      db.transaction(() async {
        final current = await settings();
        current.addAll(values);
        await setSettings(current);
        return current;
      });
  Future<void> saveAccount(Account a) async {
    await put('accounts', a.id, a.toJson());
    changes.add(null);
  }

  Future<bool> _has(String kind, String value) async {
    if (value.isEmpty) return false;
    final rows = await db
        .customSelect(
          'SELECT record_id FROM lookups WHERE kind=? AND digest=? LIMIT 1',
          variables: [Variable(kind), Variable(await vault.fingerprint(value))],
        )
        .get();
    return rows.isNotEmpty;
  }

  Map<String, String> keys(Slip s) => {
    'source': s.source,
    'hash': s.imageHash,
    'reference': s.reference.isEmpty || s.bank == Bank.unknown
        ? ''
        : '${s.bank.name}:${s.reference}',
    'composite':
        s.date == null ||
            s.amountMinor == null ||
            s.senderId.isEmpty ||
            s.receiverId.isEmpty
        ? ''
        : '${s.bank.name}:${s.amountMinor}:${s.currency}:${s.date!.toIso8601String()}:${s.senderId}:${s.receiverId}',
  };
  Future<List<Slip>> matchingReferences(Slip s) async {
    final reference = keys(s)['reference']!;
    if (reference.isEmpty) return [];
    final rows = await db
        .customSelect(
          'SELECT t.id,t.payload FROM transactions t JOIN lookups l ON l.record_id=t.id WHERE l.kind=? AND l.digest=? AND t.id<>?',
          variables: [
            Variable('reference'),
            Variable(await vault.fingerprint(reference)),
            Variable(s.id),
          ],
        )
        .get();
    return Future.wait(
      rows.map(
        (r) async => Slip.fromJson(
          await vault.unseal(
            r.read<String>('payload'),
            'transactions:${r.read<String>('id')}',
          ),
        ),
      ),
    );
  }

  Future<ImportResult> importSlip(Slip s, {bool confirm = false}) =>
      db.transaction(() async {
        final k = keys(s);
        for (final kind in ['source', 'hash']) {
          if (await _has(kind, k[kind]!)) return ImportResult.duplicate;
        }
        final references = await matchingReferences(s);
        if (references.any(
          (other) =>
              s.amountMinor != null &&
              s.date != null &&
              other.amountMinor == s.amountMinor &&
              other.currency == s.currency &&
              other.date == s.date,
        )) {
          return ImportResult.duplicate;
        }
        s.possibleDuplicate =
            references.isNotEmpty || await _has('composite', k['composite']!);
        s.review = confirm && s.valid && !s.possibleDuplicate
            ? ReviewStatus.confirmed
            : ReviewStatus.pending;
        await _writeSlip(s);
        changes.add(null);
        return s.possibleDuplicate
            ? ImportResult.possibleDuplicate
            : ImportResult.inserted;
      });
  Future<void> _writeSlip(Slip s) async {
    s.updatedAt = DateTime.now().toUtc();
    await put('transactions', s.id, s.toJson());
    await db.customStatement('DELETE FROM lookups WHERE record_id=?', [s.id]);
    for (final entry in keys(s).entries.where((e) => e.value.isNotEmpty)) {
      await db.customStatement(
        'INSERT INTO lookups(kind,digest,record_id) VALUES (?,?,?)',
        [entry.key, await vault.fingerprint(entry.value), s.id],
      );
    }
  }

  Future<void> saveSlip(Slip s) async {
    if (s.savingsReserveMinor < 0 ||
        s.savingsReserveMinor > (s.amountMinor ?? 0)) {
      throw ArgumentError('Savings reserve must be between zero and income');
    }
    if (s.review == ReviewStatus.confirmed && !s.valid) {
      throw StateError('Review required');
    }
    await db.transaction(() async {
      if (s.review == ReviewStatus.confirmed &&
          (await matchingReferences(s)).isNotEmpty) {
        throw StateError(
          'Another transaction has this provider reference. Correct the reference or delete the duplicate before confirming.',
        );
      }
      await _writeSlip(s);
    });
    changes.add(null);
  }

  Future<void> deleteSlip(String id) async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM transactions WHERE id=?', [id]);
      await db.customStatement('DELETE FROM lookups WHERE record_id=?', [id]);
    });
    changes.add(null);
  }

  Future<void> deleteAll() async {
    await db.transaction(() async {
      for (final table in [...SlipDatabase.entities, 'lookups']) {
        await db.customStatement('DELETE FROM $table');
      }
    });
    changes.add(null);
  }

  Future<Map<DataGroup, int>> dataCounts({
    DateTime? start,
    DateTime? end,
  }) async {
    bool includes(DateTime? date) =>
        start == null ||
        (date != null && !date.isBefore(start) && date.isBefore(end!));
    final items = (await slips()).where((s) => includes(s.date)).toList();
    return {
      for (final group in DataGroup.values)
        group: group == DataGroup.savings
            ? (await savings()).where((s) => includes(s.date)).length
            : items.where(group.matches).length,
    };
  }

  Future<int> deleteData(
    Set<DataGroup> groups, {
    DateTime? start,
    DateTime? end,
  }) async {
    if ((start == null) != (end == null) ||
        (start != null && !end!.isAfter(start))) {
      throw ArgumentError('Invalid deletion period');
    }
    bool includes(DateTime? date) =>
        start == null ||
        (date != null && !date.isBefore(start) && date.isBefore(end!));
    final count = await db.transaction(() async {
      final remove = (await slips())
          .where((s) => includes(s.date) && groups.any((g) => g.matches(s)))
          .toList();
      final ids = remove.map((s) => s.id).toSet();
      final sources = remove
          .map((s) => s.source)
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final id in ids) {
        await db.customStatement('DELETE FROM transactions WHERE id=?', [id]);
        await db.customStatement('DELETE FROM lookups WHERE record_id=?', [id]);
      }
      // Explicitly picking a deleted receipt should be able to import it again.
      if (ids.isNotEmpty) {
        for (final item in await records('queue')) {
          if (ids.contains(item['recordId']) ||
              sources.contains(item['source'])) {
            await db.customStatement('DELETE FROM queue WHERE id=?', [
              item['id'],
            ]);
          }
        }
      }
      var removed = ids.length;
      if (groups.contains(DataGroup.savings)) {
        await _updatePetProgress();
        for (final entry in (await savings()).where((s) => includes(s.date))) {
          await db.customStatement('DELETE FROM savings WHERE id=?', [
            entry.id,
          ]);
          removed++;
        }
      }
      return removed;
    });
    changes.add(null);
    return count;
  }

  Future<String> exportEncrypted(String password) async {
    if (password.length < 12) throw ArgumentError('Use at least 12 characters');
    // Password-derived portable backup key, independent of the device Keychain.
    final snapshot = await db.transaction(
      () async => {for (final t in SlipDatabase.entities) t: await records(t)},
    );
    return BackupCodec.encode(snapshot, password);
  }

  Future<void> importEncrypted(String data, String password) async {
    final backup = await BackupCodec.decode(data, password);
    // Restore only into an empty database; preserving IDs avoids orphaned accounts.
    await db.transaction(() async {
      if ((await slips()).isNotEmpty ||
          (await accounts()).isNotEmpty ||
          (await savings()).isNotEmpty) {
        throw StateError('Restore requires an empty database');
      }
      for (final a in backup['accounts'] as List) {
        final account = Account.fromJson(Map<String, dynamic>.from(a));
        await put('accounts', account.id, account.toJson());
      }
      for (final t in backup['transactions'] as List) {
        await _writeSlip(Slip.fromJson(Map<String, dynamic>.from(t)));
      }
      for (final table in [
        'categories',
        'settings',
        'scan_history',
        'savings',
      ]) {
        for (final item in (backup[table] as List? ?? [])) {
          final record = Map<String, dynamic>.from(item);
          if (table == 'settings') {
            record['automatic'] = false;
            record['budgetAlertsEnabled'] = false;
            record['checkpoint'] = 0;
            record.remove('permission');
          }
          await put(
            table,
            record['id'] ?? (table == 'settings' ? 'preferences' : newId()),
            record,
          );
        }
      }
    });
    changes.add(null);
  }

  Future<void> close() async {
    await changes.close();
    await db.close();
  }
}
