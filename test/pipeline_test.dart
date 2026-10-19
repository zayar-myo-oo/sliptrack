import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/core/vault.dart';
import 'package:sliptrack/database/database.dart';
import 'package:sliptrack/features/slip_recognition/parsers.dart';
import 'package:sliptrack/features/ocr/ocr_service.dart';
import 'package:sliptrack/features/gallery_scanner/scan_controller.dart';
import 'fixtures.dart';

class FakeGallery implements GalleryService {
  String state = 'full';
  int reads = 0;
  List<String> ids = ['asset-a'];
  @override
  Future<List<String>> incoming() async => [];
  @override
  Future<String> permission({bool request = false}) async => state;
  @override
  Future<List<String>> pick() async => ids;
  @override
  Future<List<String>> assets({
    required int afterMs,
    required int sinceMs,
    required int offset,
  }) async {
    reads++;
    return offset == 0 ? ids : [];
  }

  @override
  Future<Uint8List?> thumbnail(String id) async => null;
  @override
  Future<void> automatic(bool enabled) async {}
  @override
  Stream<void> get changes => const Stream.empty();
}

class FakeOcr implements OCRService {
  int calls = 0;
  bool fail = false;
  String text = kbzReceipt;
  @override
  Future<OcrResult> recognizeText(String source) async {
    calls++;
    if (fail) throw StateError('Synthetic failure');
    return OcrResult(text: text, hash: 'synthetic-hash-$source', blocks: []);
  }
}

Slip synthetic({
  String? id,
  String source = 'asset-a',
  String reference = 'TEST123456',
}) => Slip(
  id: id ?? newId(),
  bank: Bank.kbz,
  currency: 'MMK',
  amountMinor: 14400000,
  date: DateTime(2026, 10, 17, 10, 27, 1),
  zone: 'Asia/Yangon',
  reference: reference,
  source: source,
  imageHash: 'hash-$source',
  senderId: '0911111111',
  receiverId: '0922222222',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('receipt extraction', () {
    test('KBZ sample structure, negative amount, notes and local time', () {
      final s = KBZSlipParser().parse(kbzReceipt);
      expect(s.amountMinor, 14400000);
      expect(s.currency, 'MMK');
      expect(s.date, DateTime(2026, 10, 17, 10, 27, 1));
      expect(s.zone, 'Asia/Yangon');
      expect(s.reference, '90000000000000000001');
      expect(s.description, 'Training class');
      expect(s.receiverId, '******1234');
    });
    test('TrueMoney sender, receiver, amount and transaction date', () {
      final s = TrueMoneySlipParser().parse(trueMoneyReceipt);
      expect(s.amountMinor, 63900);
      expect(s.senderId, '***-***-1111');
      expect(s.receiverId, '004-********-222');
      expect(s.receiver, 'SAMPLE RECIPIENT****');
      expect(s.date, DateTime(2026, 10, 18, 3, 22, 27));
      expect(s.reference, '900000000000001');
    });
    test('KBank generic label contract', () {
      final s = SlipRecognizer().parse(kbankReceipt)!;
      expect(s.bank, Bank.kbank);
      expect(s.amountMinor, 125025);
      expect(s.date!.year, 2026);
    });
    test('logo alone is not a receipt', () {
      expect(SlipRecognizer().parse('KBZ BANK\nMy holiday'), isNull);
    });
    test('missing amount and date remain pending', () {
      final s = SlipRecognizer().parse('KBZ BANK\nTransaction No TEST000123')!;
      expect(s.amountMinor, isNull);
      expect(s.date, isNull);
      expect(s.valid, isFalse);
      expect(s.review, ReviewStatus.pending);
    });
    test('exact minor units and Myanmar/Thai digits', () {
      expect(parseMinor('0.10'), 10);
      expect(parseMinor('1,234.56'), 123456);
      expect(parseMinor('၁၄၄၀၀၀.၀၀'), 14400000);
      expect(parseMinor('๖๓๙.๐๐'), 63900);
      expect(parseMinor('1.999'), isNull);
      expect(parseMinor('NaN'), isNull);
    });
    test('Buddhist Era and Thai/Myanmar month normalization', () {
      expect(
        parseSlipDate('18 ต.ค. 2569 03:22:27'),
        DateTime(2026, 10, 18, 3, 22, 27),
      );
      expect(
        parseSlipDate('၁၈ အောက်တိုဘာ ၂၀၂၆ ၀၃:၂၂:၂၇'),
        DateTime(2026, 10, 18, 3, 22, 27),
      );
      expect(parseSlipDate('31/02/2026 03:22:27'), isNull);
    });
    test('ambiguous ownership and names alone never imply income', () {
      final s = TrueMoneySlipParser().parse(trueMoneyReceipt);
      classify(s, [
        const Account(
          id: 'a',
          bank: Bank.trueMoney,
          name: 'wallet',
          holder: 'SAMPLE USER****',
          identifier: '1111',
          currency: 'THB',
        ),
      ]);
      expect(s.direction, Direction.unknown);
    });
    test('known endpoints classify internal transfer', () {
      final s = synthetic()
        ..currency = 'THB'
        ..senderBank = Bank.kbank
        ..receiverBank = Bank.trueMoney;
      classify(s, [
        const Account(
          id: 'a',
          bank: Bank.kbank,
          name: 'A',
          holder: 'A',
          identifier: '0911111111',
          currency: 'THB',
        ),
        const Account(
          id: 'b',
          bank: Bank.trueMoney,
          name: 'B',
          holder: 'B',
          identifier: '0922222222',
          currency: 'THB',
        ),
      ]);
      expect(s.direction, Direction.internalTransfer);
      s.review = ReviewStatus.confirmed;
      expect(totalsFor([s])['THB']!.expense, 0);
    });
    test(
      'currency-separated confirmed totals exclude review and transfers',
      () {
        final a = synthetic()
          ..direction = Direction.expense
          ..review = ReviewStatus.confirmed;
        final b = synthetic()
          ..currency = 'THB'
          ..amountMinor = 63900
          ..direction = Direction.income
          ..review = ReviewStatus.confirmed;
        final pending = synthetic()..direction = Direction.expense;
        final totals = totalsFor([a, b, pending]);
        expect(totals['MMK']!.expense, 14400000);
        expect(totals['THB']!.income, 63900);
        expect(totals['MMK']!.income, 0);
      },
    );
  });
  group('encrypted persistence and scanning', () {
    late Repository repo;
    setUp(() {
      repo = Repository(
        SlipDatabase(NativeDatabase.memory()),
        Vault(List.generate(32, (i) => i)),
      );
    });
    tearDown(() => repo.close());
    test('same image and source import once', () async {
      expect(await repo.importSlip(synthetic()), ImportResult.inserted);
      expect(
        await repo.importSlip(synthetic(reference: 'OTHER123')),
        ImportResult.duplicate,
      );
      expect((await repo.slips()).length, 1);
    });
    test('different images sharing provider reference import once', () async {
      await repo.importSlip(synthetic());
      expect(
        await repo.importSlip(synthetic(source: 'asset-b')),
        ImportResult.duplicate,
      );
    });
    test('image hash prevents duplicate across asset identifiers', () async {
      await repo.importSlip(synthetic());
      final second = synthetic(source: 'asset-b', reference: 'SECOND123')
        ..imageHash = 'hash-asset-a';
      expect(await repo.importSlip(second), ImportResult.duplicate);
    });
    test(
      'same amount with distinct references never silently merges',
      () async {
        await repo.importSlip(synthetic());
        expect(
          await repo.importSlip(
            synthetic(source: 'asset-b', reference: 'SECOND123'),
          ),
          ImportResult.possibleDuplicate,
        );
        expect((await repo.slips()).length, 2);
      },
    );
    test('missing-reference composite match is reviewable', () async {
      await repo.importSlip(synthetic(reference: ''));
      expect(
        await repo.importSlip(synthetic(source: 'asset-b', reference: '')),
        ImportResult.possibleDuplicate,
      );
      expect((await repo.slips()).last.review, ReviewStatus.pending);
    });
    test(
      'financial values are encrypted and authenticated with row identity',
      () async {
        await repo.importSlip(synthetic()..receiver = 'PRIVATE NAME');
        final raw =
            (await repo.db
                    .customSelect('SELECT payload FROM transactions')
                    .get())
                .single
                .read<String>('payload');
        expect(raw.contains('PRIVATE NAME'), isFalse);
        expect(raw.contains('14400000'), isFalse);
        expect((await repo.slips()).single.receiver, 'PRIVATE NAME');
        await expectLater(
          repo.vault.unseal(raw, 'transactions:wrong-id'),
          throwsA(anything),
        );
      },
    );
    test(
      'denied photo permissions prevent gallery reads but picker works',
      () async {
        final gallery = FakeGallery()..state = 'denied';
        final ocr = FakeOcr();
        final scanner = ScanController(repo, gallery, ocr);
        addTearDown(scanner.dispose);
        await repo.setSettings({'automatic': true});
        await scanner.catchUp();
        expect(gallery.reads, 0);
        expect(ocr.calls, 0);
        await scanner.pick();
        expect((await repo.slips()).length, 1);
      },
    );
    test('limited access reads only returned assets', () async {
      final gallery = FakeGallery()..state = 'limited';
      final ocr = FakeOcr();
      final scanner = ScanController(repo, gallery, ocr);
      addTearDown(scanner.dispose);
      await repo.setSettings({'automatic': true});
      await scanner.catchUp();
      expect(ocr.calls, 1);
      expect((await repo.slips()).single.source, 'asset-a');
    });
    test('OCR failures persist and retry successfully', () async {
      final ocr = FakeOcr()..fail = true;
      final scanner = ScanController(repo, FakeGallery(), ocr);
      addTearDown(scanner.dispose);
      await scanner.pick();
      expect(scanner.failed, 1);
      expect(await repo.slips(), isEmpty);
      expect((await repo.records('queue')).single['state'], 'failed');
      ocr.fail = false;
      await scanner.retry();
      expect((await repo.slips()).length, 1);
    });
    test('restart resumes durable queue and rescanning avoids OCR', () async {
      final gallery = FakeGallery();
      final ocr = FakeOcr();
      final first = ScanController(repo, gallery, ocr);
      await first.enqueue(['asset-a'], manual: true);
      first.dispose();
      final second = ScanController(repo, gallery, ocr);
      addTearDown(second.dispose);
      await second.process();
      await second.enqueue(['asset-a']);
      await second.process();
      expect(ocr.calls, 1);
      expect((await repo.slips()).length, 1);
    });
    test('background restriction and pause defer processing', () async {
      final gallery = FakeGallery();
      final ocr = FakeOcr();
      final scanner = ScanController(repo, gallery, ocr);
      addTearDown(scanner.dispose);
      await scanner.enqueue(['asset-a']);
      scanner.foreground = false;
      await scanner.process();
      expect(ocr.calls, 0);
      scanner.foreground = true;
      scanner.paused = true;
      await scanner.process();
      expect(ocr.calls, 0);
      scanner.paused = false;
      await scanner.process();
      expect(ocr.calls, 1);
    });
    test('unrelated photos are not imported automatically', () async {
      final ocr = FakeOcr()..text = 'A family picnic';
      final scanner = ScanController(repo, FakeGallery(), ocr);
      addTearDown(scanner.dispose);
      await scanner.enqueue(['asset-a']);
      await scanner.process();
      expect(await repo.slips(), isEmpty);
      expect(scanner.ignored, 1);
    });
    test('cannot confirm incomplete financial records', () async {
      final s = Slip(id: newId())..review = ReviewStatus.confirmed;
      await expectLater(repo.saveSlip(s), throwsStateError);
    });
    test('migration from encrypted v1 preserves existing records', () async {
      final prior = const Account(
        id: 'prior',
        bank: Bank.kbz,
        name: 'Existing',
        holder: 'Synthetic',
        identifier: '****1111',
        currency: 'MMK',
      );
      final encrypted = await repo.vault.seal(prior.toJson(), 'accounts:prior');
      final executor = NativeDatabase.memory(
        setup: (database) {
          for (final table in SlipDatabase.entities) {
            database.execute(
              'CREATE TABLE $table (id TEXT PRIMARY KEY,payload TEXT NOT NULL)',
            );
          }
          database.execute('PRAGMA user_version = 1');
          database.execute('INSERT INTO accounts(id,payload) VALUES (?,?)', [
            'prior',
            encrypted,
          ]);
        },
      );
      final vault = repo.vault;
      await repo.close();
      repo = Repository(SlipDatabase(executor), vault);
      final migrated = repo;
      expect((await migrated.accounts()).single.name, 'Existing');
      final version = await migrated.db
          .customSelect('PRAGMA user_version')
          .get();
      expect(version.single.data.values.single, 3);
      await migrated.importSlip(synthetic());
      expect((await migrated.slips()).length, 1);
    });
    test('conflicting reference values are preserved for review', () async {
      await repo.importSlip(synthetic());
      final conflicting = synthetic(source: 'asset-b')..amountMinor = 99900;
      expect(
        await repo.importSlip(conflicting),
        ImportResult.possibleDuplicate,
      );
      expect((await repo.slips()).length, 2);
      conflicting.direction = Direction.expense;
      conflicting.review = ReviewStatus.confirmed;
      await expectLater(repo.saveSlip(conflicting), throwsStateError);
    });
    test('failed OCR can become an editable manual review record', () async {
      final scanner = ScanController(
        repo,
        FakeGallery(),
        FakeOcr()..fail = true,
      );
      addTearDown(scanner.dispose);
      await scanner.pick();
      await scanner.reviewFailed((await repo.queueItems('failed')).single);
      final slip = (await repo.slips()).single;
      expect(slip.amountMinor, isNull);
      expect(slip.source, 'asset-a');
      expect(slip.review, ReviewStatus.pending);
      expect(await repo.queueItems('failed'), isEmpty);
    });
    test(
      'encrypted backup restores accounts and transactions under a new device key',
      () async {
        await repo.setSettings({'automatic': true, 'checkpoint': 12345});
        await repo.saveAccount(
          const Account(
            id: 'backup-account',
            bank: Bank.kbz,
            name: 'Test',
            holder: 'Synthetic',
            identifier: '****1111',
            currency: 'MMK',
          ),
        );
        await repo.importSlip(synthetic());
        final text = await repo.exportEncrypted('synthetic-password-123');
        expect(text.contains('TEST123456'), isFalse);
        await repo.close();
        repo = Repository(
          SlipDatabase(NativeDatabase.memory()),
          Vault(List.filled(32, 42)),
        );
        await repo.importEncrypted(text, 'synthetic-password-123');
        expect((await repo.slips()).single.reference, 'TEST123456');
        expect((await repo.accounts()).single.id, 'backup-account');
        expect((await repo.settings())['automatic'], isFalse);
        expect((await repo.settings())['checkpoint'], 0);
        await repo.deleteAll();
        await expectLater(
          repo.importEncrypted(text, 'wrong-password-123'),
          throwsA(anything),
        );
        expect(await repo.slips(), isEmpty);
      },
    );
    test(
      'permission upgrade discovers newly accessible historical assets',
      () async {
        final gallery = FakeGallery();
        final scanner = ScanController(repo, gallery, FakeOcr());
        addTearDown(scanner.dispose);
        await repo.setSettings({
          'automatic': true,
          'permission': 'limited',
          'checkpoint': DateTime.now().millisecondsSinceEpoch,
        });
        await scanner.catchUp();
        expect((await repo.slips()).length, 1);
        expect((await repo.settings())['permission'], 'full');
      },
    );
  });
}
