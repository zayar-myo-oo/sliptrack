import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/core/exchange_rate.dart';
import 'package:sliptrack/core/models.dart';
import 'package:sliptrack/core/vault.dart';
import 'package:sliptrack/database/database.dart';
import 'package:sliptrack/features/companion/coach_controller.dart';
import 'package:sliptrack/features/companion/coach_models.dart';

class FakeNotifications implements BudgetNotifications {
  bool allowed = true, accept = true;
  final posts = <({int id, String body})>[];
  Completer<void>? gate;
  @override
  Future<bool> permission({bool request = false}) async => allowed;
  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await gate?.future;
    if (accept) posts.add((id: id, body: body));
    return accept;
  }
}

Repository memoryRepo() => Repository(
  SlipDatabase(NativeDatabase.memory()),
  Vault(List.generate(32, (i) => i)),
);

SavingsEntry savings(int thb, {int goal = defaultSavingsGoalThbMinor}) =>
    SavingsEntry.create(
      amountMinor: thb,
      currency: 'THB',
      date: DateTime(2026, 10, 25),
      rateMicros: defaultMmkPerThbMicros,
      goalThbMinor: goal,
    );

Slip income(DateTime month, int minor) => Slip(
  id: newId(),
  isManualIncome: true,
  category: 'Salary',
  amountMinor: minor,
  date: month,
  direction: Direction.income,
  review: ReviewStatus.confirmed,
);
Slip expense(
  DateTime month,
  int minor, {
  ReviewStatus review = ReviewStatus.confirmed,
}) => Slip(
  id: newId(),
  bank: Bank.trueMoney,
  currency: 'THB',
  amountMinor: minor,
  date: month,
  direction: Direction.expense,
  review: review,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Repository repo;
  late ChangeNotifier preferences;
  late FakeNotifications notifications;
  late CoachController coach;
  final october = DateTime(2026, 10, 25);
  setUp(() async {
    repo = memoryRepo();
    preferences = ChangeNotifier();
    notifications = FakeNotifications();
    coach = CoachController(repo, preferences, notifications);
    await repo.patchSettings({'budgetAlertsEnabled': true});
  });
  tearDown(() async {
    coach.dispose();
    preferences.dispose();
    await repo.close();
  });

  test('mood and thresholds include exact 80/100 boundaries and no income', () {
    for (final (spent, tier, mood) in [
      (7999, 0, PetMood.happy),
      (8000, 1, PetMood.worried),
      (9999, 1, PetMood.worried),
      (10000, 2, PetMood.crying),
      (12000, 2, PetMood.crying),
    ]) {
      final life = BudgetLife(income: 10000, expenses: spent);
      expect(life.alertTier, tier);
      expect(life.mood, mood);
    }
    expect(BudgetLife(income: 0, expenses: 100).alertTier, 0);
    expect(BudgetLife(income: 0, expenses: 0).mood, PetMood.crying);
    expect(
      BudgetLife(income: 9000000000000000000, expenses: 0).lifePercent,
      100,
    );
  });

  test(
    '80 and 100 alert only once per calendar month across edits and restart',
    () async {
      await repo.saveSlip(income(october, 10000));
      final spending = expense(october, 7999);
      await repo.saveSlip(spending);
      // Old, unconfirmed and internal-transfer receipts must not trigger alerts.
      await repo.saveSlip(expense(DateTime(2026, 9, 1), 999999));
      await repo.saveSlip(
        expense(october, 999999, review: ReviewStatus.pending),
      );
      await repo.saveSlip(
        expense(october, 999999)..direction = Direction.internalTransfer,
      );
      await coach.evaluate(now: october);
      expect(notifications.posts, isEmpty);
      spending.amountMinor = 8000;
      await repo.saveSlip(spending);
      await coach.evaluate(now: october);
      expect(notifications.posts.map((p) => p.id), [202610251]);
      await coach.evaluate(now: october);
      expect(notifications.posts.length, 1);
      spending.amountMinor = 10000;
      await repo.saveSlip(spending);
      await coach.evaluate(now: october);
      expect(notifications.posts.length, 2);
      spending.amountMinor = 100;
      await repo.saveSlip(spending);
      await coach.evaluate(now: october);
      spending.amountMinor = 12000;
      await repo.saveSlip(spending);
      coach.dispose();
      coach = CoachController(repo, preferences, notifications);
      await coach.evaluate(now: october);
      expect(notifications.posts.length, 2);
      final november = DateTime(2026, 11, 25);
      await repo.saveSlip(income(november, 10000));
      await repo.saveSlip(expense(november, 8000));
      await coach.evaluate(now: november);
      expect(notifications.posts.map((p) => p.id), [
        202610251,
        202610252,
        202611251,
      ]);
    },
  );

  test(
    'crossing both thresholds posts both; denial/failure can retry',
    () async {
      await repo.saveSlip(income(october, 10000));
      await repo.saveSlip(expense(october, 11000));
      notifications.allowed = false;
      await coach.evaluate(now: october);
      expect(notifications.posts, isEmpty);
      notifications.allowed = true;
      notifications.accept = false;
      await coach.evaluate(now: october);
      expect((await repo.settings())['sentBudgetTiers'], isNull);
      notifications.accept = true;
      await coach.evaluate(now: october);
      expect(notifications.posts.map((p) => p.id), [202610251, 202610252]);
      expect(notifications.posts.first.body, contains('80%'));
      expect(notifications.posts.last.body, contains('reached your income'));
    },
  );

  test('overlapping evaluations cannot repeat the same threshold', () async {
    await repo.saveSlip(income(october, 10000));
    await repo.saveSlip(expense(october, 8000));
    notifications.gate = Completer<void>();
    final first = coach.evaluate(now: october);
    await coach.evaluate(now: october);
    notifications.gate!.complete();
    await first;
    expect(notifications.posts.length, 1);
  });

  test('THB estimate combines confirmed MMK using offline rate', () async {
    await repo.saveSlip(income(october, 10000));
    await repo.saveSlip(
      expense(october, 1064000)
        ..currency = 'MMK'
        ..bank = Bank.kbz,
    );
    await coach.evaluate(now: october);
    expect(notifications.posts.length, 1);
    final totals = totalsFor(await repo.slips(), month: october);
    expect(totals['MMK']!.expense, 1064000);
    expect(totals['THB']!.expense, 0);
    expect((await repo.savings()), isEmpty);
  });

  test(
    'savings snapshot rate and goal; rewards survive immediate delete',
    () async {
      final entry = SavingsEntry.create(
        amountMinor: 66500000,
        currency: 'MMK',
        date: october,
        rateMicros: defaultMmkPerThbMicros,
        goalThbMinor: defaultSavingsGoalThbMinor,
      );
      await repo.saveSavings(entry);
      await repo.patchSettings({
        'mmkPerThbMicros': 200000000,
        'savingsGoalThbMinor': 1000000,
      });
      final stored = (await repo.savings()).single;
      expect(stored.thbEquivalentMinor, 500000);
      expect(stored.xpMicros, petXpScale);
      expect(stored.rateMicros, defaultMmkPerThbMicros);
      expect(stored.goalThbMinor, defaultSavingsGoalThbMinor);
      await repo.deleteSavings(entry.id);
      final progress = await repo.petProgress();
      expect(progress.level, 2);
      expect(progress.xpMicros, 0);
      expect(progress.nextRewardProgress, 0);
      expect(totalsFor(await repo.slips())['THB']!.net, 0);
    },
  );

  test(
    'growth caps at ten then outfits unlock and persist after decrease',
    () async {
      final entry = savings(500000 * 12);
      await repo.saveSavings(entry);
      var progress = await repo.petProgress();
      expect(progress.level, 10);
      expect(progress.outfitsUnlocked, 3);
      await repo.deleteSavings(entry.id);
      progress = await repo.petProgress();
      expect(progress.level, 10);
      expect(progress.outfitsUnlocked, 3);
    },
  );

  test(
    'encrypted savings backup restores snapshots and earned rewards under a new key',
    () async {
      final earned = savings(500000 * 10);
      await repo.saveSavings(earned);
      await repo.deleteSavings(earned.id);
      final retained = savings(250000);
      await repo.saveSavings(retained);
      final raw = await repo.db
          .customSelect('SELECT payload FROM savings')
          .getSingle();
      expect(raw.read<String>('payload'), isNot(contains('amountMinor')));
      const password = 'synthetic backup password';
      final backup = await repo.exportEncrypted(password);
      final restored = Repository(
        SlipDatabase(NativeDatabase.memory()),
        Vault(List.generate(32, (i) => 255 - i)),
      );
      addTearDown(restored.close);
      await restored.importEncrypted(backup, password);
      expect((await restored.savings()).single.toJson(), retained.toJson());
      expect((await restored.petProgress()).outfitsUnlocked, 1);
      expect((await restored.settings())['budgetAlertsEnabled'], false);
      await expectLater(
        restored.importEncrypted(backup, password),
        throwsStateError,
      );
    },
  );

  test('savings rejects invalid rate even when input currency is THB', () {
    expect(
      () => SavingsEntry.create(
        amountMinor: 100,
        currency: 'THB',
        date: october,
        rateMicros: 0,
        goalThbMinor: 500000,
      ),
      throwsArgumentError,
    );
  });

  test('native notifications use the existing channel contract', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBudgetNotifications.channel, (
          call,
        ) async {
          calls.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBudgetNotifications.channel, null),
    );
    final native = NativeBudgetNotifications();
    expect(await native.permission(), true);
    expect(await native.permission(request: true), true);
    expect(
      await native.show(id: 202610251, title: 'Alert', body: 'Review spending'),
      true,
    );
    expect(calls.map((c) => c.method), [
      'notificationPermission',
      'notificationPermission',
      'notifyBudget',
    ]);
    expect(calls.first.arguments, {'request': false});
    expect(calls[1].arguments, {'request': true});
    expect(calls.last.arguments['id'], 202610251);
  });
}
