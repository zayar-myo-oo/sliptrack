import '../../core/models.dart';

String normalizeDigits(String value) {
  for (var i = 0; i < 10; i++) {
    value = value
        .replaceAll(String.fromCharCode(0x1040 + i), '$i')
        .replaceAll(String.fromCharCode(0x0e50 + i), '$i');
  }
  return value.replaceAll('−', '-').replaceAll('–', '-');
}

int? parseMinor(String input) {
  final clean = normalizeDigits(input).replaceAll(',', '').trim();
  final match = RegExp(r'^[-+]?([0-9]+)(?:\.([0-9]{1,2}))?$').firstMatch(clean);
  if (match == null) return null;
  final major = int.tryParse(match[1]!);
  if (major == null || major > 9000000000000) return null;
  return major * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
}

DateTime? parseSlipDate(String input) {
  var s = normalizeDigits(input);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const thai = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  const myanmar = [
    'ဇန်နဝါရီ',
    'ဖေဖော်ဝါရီ',
    'မတ်',
    'ဧပြီ',
    'မေ',
    'ဇွန်',
    'ဇူလိုင်',
    'ဩဂုတ်',
    'စက်တင်ဘာ',
    'အောက်တိုဘာ',
    'နိုဝင်ဘာ',
    'ဒီဇင်ဘာ',
  ];
  for (var i = 0; i < 12; i++) {
    s = s.replaceAll(thai[i], months[i]).replaceAll(myanmar[i], months[i]);
  }
  final numeric = RegExp(
    r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(s);
  final named = RegExp(
    r'(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(s);
  final m = numeric ?? named;
  if (m == null) return null;
  if (numeric == null && m[2]!.length < 3) return null;
  var year = int.parse(m[3]!);
  if (year >= 2400) year -= 543;
  final month = numeric != null
      ? int.parse(m[2]!)
      : months.indexWhere(
              (v) => v.toLowerCase() == m[2]!.substring(0, 3).toLowerCase(),
            ) +
            1;
  final day = int.parse(m[1]!),
      hour = int.parse(m[4]!),
      minute = int.parse(m[5]!),
      second = int.parse(m[6] ?? '0');
  if (year < 1900 ||
      month < 1 ||
      month > 12 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  // A receipt wall-clock time is preserved with its IANA timezone stored separately.
  final date = DateTime(year, month, day, hour, minute, second);
  return date.day == day ? date : null;
}

abstract interface class BankSlipParser {
  Bank get bank;
  bool recognizes(String text);
  Slip parse(String text);
}

abstract class LabeledSlipParser implements BankSlipParser {
  String field(String text, String label) {
    final match = RegExp(
      '(?:^|\\n)\\s*(?:$label)\\s*[:：]?\\s*([^\\n]+)',
      caseSensitive: false,
    ).firstMatch(text);
    return match?[1]?.trim() ?? '';
  }

  @override
  Slip parse(String text) {
    final s = normalizeDigits(text);
    final slip = Slip(
      id: newId(),
      bank: bank,
      currency: bank.currency,
      zone: bank.zone,
      rawText: text,
    );
    final amount = RegExp(
      r'(?:฿|\bTHB)\s*([-+]?\d[\d,]*\.\d{2})|([-+]?\d[\d,]*\.\d{2})\s*(?:Ks\b|MMK\b|THB\b|บาท)',
      caseSensitive: false,
    ).firstMatch(s);
    slip.amountMinor = parseMinor(amount?[1] ?? amount?[2] ?? '');
    slip.date = parseSlipDate(
      field(s, 'Transaction Time|Transaction date|Date|วันที่'),
    );
    slip.reference = field(
      s,
      'Transaction No|Reference number|Reference No|Transaction ID|เลขที่รายการ',
    ).replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^[A-Za-z0-9-]{6,60}$').hasMatch(slip.reference)) {
      slip.reference = '';
    }
    slip.sender = field(s, 'Transfer From|Sender|From(?! wallet)|ผู้โอน');
    slip.receiver = field(s, 'Transfer To|Receiver|To|ผู้รับ');
    slip.senderId = identifier(slip.sender);
    slip.receiverId = identifier(slip.receiver);
    slip.description = field(s, 'Notes|Description|บันทึก');
    slip.type = field(s, 'Transaction Type');
    slip.ruleScore =
        [
          slip.amountMinor != null,
          slip.date != null,
          slip.reference.isNotEmpty,
          slip.receiver.isNotEmpty,
        ].where((v) => v).length /
        4;
    return slip;
  }

  String identifier(String value) =>
      RegExp(r'[\d*Xx][\d*Xx-]{3,}').firstMatch(value)?[0] ?? '';
}

class KBZSlipParser extends LabeledSlipParser {
  @override
  Bank get bank => Bank.kbz;
  @override
  bool recognizes(String t) =>
      RegExp(r'KBZ\s*(BANK|Pay)', caseSensitive: false).hasMatch(t) &&
      RegExp(
        r'Transaction (Time|No)|Transfer To',
        caseSensitive: false,
      ).hasMatch(t);
}

class TrueMoneySlipParser extends LabeledSlipParser {
  @override
  Bank get bank => Bank.trueMoney;
  @override
  bool recognizes(String t) =>
      RegExp(r'true\s*money', caseSensitive: false).hasMatch(t) &&
      RegExp(
        r'Reference number|Transaction date|PromptPay',
        caseSensitive: false,
      ).hasMatch(t);
  @override
  Slip parse(String text) {
    final slip = super.parse(text);
    final lines = normalizeDigits(
      text,
    ).split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final accountLine = lines.indexWhere(
      (s) => s.toLowerCase().contains('truemoney account'),
    );
    if (accountLine > 0) {
      slip.sender = lines[accountLine - 1];
      slip.senderId = identifier(
        lines[accountLine].replaceFirst(
          RegExp(r'TrueMoney account', caseSensitive: false),
          '',
        ),
      );
      slip.senderBank = Bank.trueMoney;
    }
    final wallet = lines.indexWhere((s) => s.toLowerCase() == 'from wallet');
    if (wallet >= 0 && lines.length > wallet + 2) {
      final candidates = lines
          .skip(wallet + 1)
          .takeWhile((s) => !s.toLowerCase().contains('transaction date'))
          .where(
            (s) =>
                s.toLowerCase() != 'promptpay' &&
                s.toLowerCase() != 'prompt' &&
                s.toLowerCase() != 'pay',
          )
          .toList();
      if (candidates.isNotEmpty) slip.receiver = candidates.first;
      if (candidates.length > 1) slip.receiverId = identifier(candidates[1]);
    }
    return slip;
  }
}

class KBankSlipParser extends LabeledSlipParser {
  @override
  Bank get bank => Bank.kbank;
  @override
  bool recognizes(String t) =>
      RegExp(r'K\s*PLUS|KASIKORN|KBank', caseSensitive: false).hasMatch(t) &&
      RegExp(
        r'Reference|Transaction|เลขที่รายการ|วันที่',
        caseSensitive: false,
      ).hasMatch(t);
}

class SlipRecognizer {
  final List<BankSlipParser> parsers = [
    TrueMoneySlipParser(),
    KBankSlipParser(),
    KBZSlipParser(),
  ];
  Slip? parse(String text) {
    final matches = parsers.where((p) => p.recognizes(text)).toList();
    if (matches.length != 1) return null;
    return matches.single.parse(text);
  }
}

void classify(Slip slip, List<Account> accounts) {
  // Names and short account suffixes are insufficient proof of ownership.
  String canonical(String s) =>
      normalizeDigits(s).replaceAll(RegExp(r'[^0-9]'), '');
  Account? owner(String id, Bank? bank) {
    if (bank == null || bank == Bank.unknown) return null;
    if (id.contains(RegExp(r'[*xX]'))) return null;
    final digits = canonical(id);
    if (digits.length < 8) return null;
    final matched = accounts
        .where(
          (a) =>
              a.bank == bank &&
              a.currency == slip.currency &&
              !a.identifier.contains(RegExp(r'[*xX]')) &&
              canonical(a.identifier) == digits,
        )
        .toList();
    return matched.length == 1 ? matched.single : null;
  }

  final from = owner(slip.senderId, slip.senderBank),
      to = owner(slip.receiverId, slip.receiverBank);
  slip.direction = from != null && to != null
      ? Direction.internalTransfer
      : from != null
      ? Direction.expense
      : to != null
      ? Direction.income
      : Direction.unknown;
  slip.accountId = from?.id ?? to?.id;
}
