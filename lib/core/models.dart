import 'dart:math';

enum Bank { trueMoney, kbank, kbz, unknown }

enum Direction { income, expense, internalTransfer, unknown }

extension DirectionLabel on Direction {
  String get label => switch (this) {
    Direction.income => 'Money in',
    Direction.expense => 'Money out',
    Direction.internalTransfer => 'Own transfer',
    Direction.unknown => 'Choose direction',
  };
}

enum ReviewStatus { pending, confirmed }

extension BankLabel on Bank {
  String get label => switch (this) {
    Bank.trueMoney => 'TrueMoney',
    Bank.kbank => 'KBank / K PLUS',
    Bank.kbz => 'KBZ Bank',
    Bank.unknown => 'Unknown provider',
  };
  String get currency => this == Bank.kbz ? 'MMK' : 'THB';
  String get zone => this == Bank.kbz ? 'Asia/Yangon' : 'Asia/Bangkok';
}

String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class Account {
  const Account({
    required this.id,
    required this.bank,
    required this.name,
    required this.holder,
    required this.identifier,
    required this.currency,
    this.createdAt,
  });
  final String id, name, holder, identifier, currency;
  final Bank bank;
  final DateTime? createdAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'bank': bank.name,
    'name': name,
    'holder': holder,
    'identifier': identifier,
    'currency': currency,
    'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
  };
  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'],
    bank: Bank.values.byName(j['bank']),
    name: j['name'],
    holder: j['holder'],
    identifier: j['identifier'],
    currency: j['currency'],
    createdAt: DateTime.tryParse(j['createdAt'] ?? ''),
  );
}

class Slip {
  Slip({
    required this.id,
    this.bank = Bank.unknown,
    this.amountMinor,
    this.currency = 'THB',
    this.date,
    this.zone,
    this.sender = '',
    this.receiver = '',
    this.senderId = '',
    this.receiverId = '',
    this.reference = '',
    this.description = '',
    this.type = '',
    this.direction = Direction.unknown,
    this.review = ReviewStatus.pending,
    this.category = 'Uncategorized',
    this.source = '',
    this.imageHash = '',
    this.rawText = '',
    this.ruleScore = 0,
    this.ocrConfidence,
    this.possibleDuplicate = false,
    this.accountId,
    this.senderBank,
    this.receiverBank,
    this.savingsReserveMinor = 0,
    this.isManualIncome = false,
    this.isManualExpense = false,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();
  final String id;
  Bank bank;
  Bank? senderBank, receiverBank;
  int? amountMinor;
  String currency,
      sender,
      receiver,
      senderId,
      receiverId,
      reference,
      description,
      type,
      category,
      source,
      imageHash,
      rawText;
  String? zone, accountId;
  DateTime? date;
  Direction direction;
  ReviewStatus review;
  double ruleScore;
  double? ocrConfidence;
  bool possibleDuplicate;
  int savingsReserveMinor;
  final bool isManualIncome;
  final bool isManualExpense;
  final DateTime createdAt;
  DateTime? updatedAt;
  bool get valid =>
      amountMinor != null &&
      amountMinor! > 0 &&
      date != null &&
      direction != Direction.unknown &&
      (isManualExpense
          ? direction == Direction.expense && ['THB', 'MMK'].contains(currency)
          : isManualIncome
          ? direction == Direction.income && ['THB', 'MMK'].contains(currency)
          : bank != Bank.unknown && currency == bank.currency);
  Map<String, dynamic> toJson() => {
    'id': id,
    'savingsReserveMinor': savingsReserveMinor,
    'bank': bank.name,
    'amountMinor': amountMinor,
    'currency': currency,
    'date': date?.toIso8601String(),
    'zone': zone,
    'sender': sender,
    'receiver': receiver,
    'senderId': senderId,
    'receiverId': receiverId,
    'reference': reference,
    'description': description,
    'type': type,
    'direction': direction.name,
    'review': review.name,
    'category': category,
    'source': source,
    'imageHash': imageHash,
    'rawText': rawText,
    'ruleScore': ruleScore,
    'ocrConfidence': ocrConfidence,
    'possibleDuplicate': possibleDuplicate,
    'accountId': accountId,
    'senderBank': senderBank?.name,
    'receiverBank': receiverBank?.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': (updatedAt ?? createdAt).toIso8601String(),
    'isManualIncome': isManualIncome,
    'isManualExpense': isManualExpense,
  };
  factory Slip.fromJson(Map<String, dynamic> j) => Slip(
    id: j['id'],
    bank: Bank.values.byName(j['bank']),
    amountMinor: j['amountMinor'],
    currency: j['currency'],
    date: DateTime.tryParse(j['date'] ?? ''),
    zone: j['zone'],
    sender: j['sender'] ?? '',
    receiver: j['receiver'] ?? '',
    senderId: j['senderId'] ?? '',
    receiverId: j['receiverId'] ?? '',
    reference: j['reference'] ?? '',
    description: j['description'] ?? '',
    type: j['type'] ?? '',
    direction: Direction.values.byName(j['direction']),
    savingsReserveMinor: (j['savingsReserveMinor'] as int?) ?? 0,
    review: ReviewStatus.values.byName(j['review']),
    category: j['category'],
    source: j['source'],
    imageHash: j['imageHash'],
    rawText: j['rawText'] ?? '',
    ruleScore: (j['ruleScore'] as num?)?.toDouble() ?? 0,
    ocrConfidence: (j['ocrConfidence'] as num?)?.toDouble(),
    possibleDuplicate: j['possibleDuplicate'] ?? false,
    accountId: j['accountId'],
    senderBank: j['senderBank'] == null
        ? null
        : Bank.values.byName(j['senderBank']),
    receiverBank: j['receiverBank'] == null
        ? null
        : Bank.values.byName(j['receiverBank']),
    createdAt: DateTime.parse(j['createdAt']),
    updatedAt: DateTime.tryParse(j['updatedAt'] ?? ''),
    isManualIncome: j['isManualIncome'] ?? false,
    isManualExpense: j['isManualExpense'] ?? false,
  );
}

class Totals {
  int income = 0, expense = 0;
  int get net => income - expense;
}

Map<String, Totals> totalsFor(Iterable<Slip> slips, {DateTime? month}) {
  final totals = {'THB': Totals(), 'MMK': Totals()};
  for (final slip in slips) {
    if (slip.review != ReviewStatus.confirmed || slip.amountMinor == null) {
      continue;
    }
    if (month != null &&
        (slip.date?.year != month.year || slip.date?.month != month.month)) {
      continue;
    }
    final t = totals[slip.currency];
    if (t == null) continue;
    if (slip.direction == Direction.income) t.income += slip.amountMinor!;
    if (slip.direction == Direction.expense) t.expense += slip.amountMinor!;
  }
  return totals;
}

String money(int minor, String currency) {
  final sign = minor < 0 ? '-' : '';
  final n = minor.abs();
  final whole = (n ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$sign$whole.${(n % 100).toString().padLeft(2, '0')} $currency';
}
