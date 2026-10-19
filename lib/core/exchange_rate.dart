import 'models.dart';

const defaultMmkPerThbMicros = 133000000;
const rateScale = 1000000;

int? parseManualRate(String input) {
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{1,6}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final value =
      int.parse(match[1]!) * rateScale +
      int.parse((match[2] ?? '').padRight(6, '0'));
  return value > 0 ? value : null;
}

String formatManualRate(int rateMicros) {
  final fraction = (rateMicros % rateScale)
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${rateMicros ~/ rateScale}${fraction.isEmpty ? '' : '.$fraction'}';
}

/// Both currencies use hundredths in storage. Convert with a rational rate,
/// rounding once per currency subtotal to the nearest THB hundredth, half up.
int mmkToThbMinor(int mmkMinor, int rateMicros) {
  if (rateMicros <= 0) throw ArgumentError('Rate must be positive');
  final numerator = BigInt.from(mmkMinor).abs() * BigInt.from(rateScale);
  final denominator = BigInt.from(rateMicros);
  final rounded = (numerator + denominator ~/ BigInt.two) ~/ denominator;
  if (rounded > BigInt.parse('9223372036854775807')) {
    throw RangeError('Converted amount exceeds supported range');
  }
  return (mmkMinor < 0 ? -rounded : rounded).toInt();
}

Totals estimateInThb(Map<String, Totals> original, int rateMicros) {
  final thb = original['THB'] ?? Totals(), mmk = original['MMK'] ?? Totals();
  return Totals()
    ..income = thb.income + mmkToThbMinor(mmk.income, rateMicros)
    ..expense = thb.expense + mmkToThbMinor(mmk.expense, rateMicros);
}
