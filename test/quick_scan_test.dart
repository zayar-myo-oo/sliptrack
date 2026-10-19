import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/core/vault.dart';
import 'package:sliptrack/database/database.dart';
import 'package:sliptrack/features/gallery_scanner/scan_controller.dart';
import 'fixtures.dart';
import 'pipeline_test.dart' show FakeGallery, FakeOcr;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Repository repo;
  late FakeGallery gallery;
  late FakeOcr ocr;
  late ScanController scanner;
  setUp(() {
    repo = Repository(
      SlipDatabase(NativeDatabase.memory()),
      Vault(List.generate(32, (i) => i)),
    );
    gallery = FakeGallery();
    ocr = FakeOcr();
    scanner = ScanController(
      repo,
      gallery,
      ocr,
      requireIncome: false,
      now: () => DateTime(2026, 10, 20),
    );
  });
  tearDown(() async {
    scanner.dispose();
    await repo.close();
  });
  test(
    'explicit expense scan immediately counts once; repeat scan cannot change direction',
    () async {
      await scanner.pick(direction: Direction.expense);
      expect((await repo.slips()).single.review, ReviewStatus.confirmed);
      expect(totalsFor(await repo.slips())['MMK']!.expense, 14400000);
      await scanner.pick(direction: Direction.income);
      expect((await repo.slips()).length, 1);
      expect(totalsFor(await repo.slips())['MMK']!.expense, 14400000);
      expect(totalsFor(await repo.slips())['MMK']!.income, 0);
    },
  );
  test(
    'explicit income scan counts income and preserves original currency',
    () async {
      ocr.text = trueMoneyReceipt;
      await scanner.pick(direction: Direction.income);
      expect(totalsFor(await repo.slips())['THB']!.income, 63900);
      expect(totalsFor(await repo.slips())['THB']!.expense, 0);
    },
  );
  test(
    'readable OCR counts automatically; missing dates stay out of totals',
    () async {
      ocr.confidence = .5;
      await scanner.pick(direction: Direction.expense);
      expect((await repo.slips()).single.review, ReviewStatus.confirmed);
      expect(totalsFor(await repo.slips())['MMK']!.expense, 14400000);
      gallery.ids = ['asset-b'];
      ocr.confidence = .99;
      ocr.text = kbzReceipt.replaceAll('17/10/2026 10:27:01', '');
      await scanner.pick(direction: Direction.expense);
      expect(
        (await repo.slips()).singleWhere((s) => s.source == 'asset-b').review,
        ReviewStatus.pending,
      );
    },
  );
  test(
    'complete provisional KBank result auto counts; sample validation still limited',
    () async {
      ocr.text = kbankReceipt;
      await scanner.pick(direction: Direction.expense);
      expect((await repo.slips()).single.review, ReviewStatus.confirmed);
    },
  );
  test(
    'receipt image and transaction screenshot with same reference count once',
    () async {
      ocr.text = trueMoneyReceipt;
      await scanner.pick(direction: Direction.expense);
      gallery.ids = ['transaction-screenshot'];
      ocr.text = trueMoneyReceipt.replaceAll(
        'SAMPLE USER****',
        'SAMPLE FULL NAME',
      );
      await scanner.pick(direction: Direction.expense);
      expect(await repo.slips(), hasLength(1));
      expect(totalsFor(await repo.slips())['THB']!.expense, 63900);
    },
  );
  test('reference conflict stays pending even on quick scan', () async {
    await scanner.pick(direction: Direction.expense);
    gallery.ids = ['asset-b'];
    ocr.text = kbzReceipt.replaceAll('144,000.00', '145,000.00');
    await scanner.pick(direction: Direction.expense);
    expect(
      (await repo.slips()).where((s) => s.possibleDuplicate).single.review,
      ReviewStatus.pending,
    );
    expect(totalsFor(await repo.slips())['MMK']!.expense, 14400000);
  });
  test('shared and gallery imports count without confirmation', () async {
    await scanner.enqueue(['shared-image'], manual: true);
    await scanner.process();
    expect((await repo.slips()).single.review, ReviewStatus.confirmed);
  });
}
