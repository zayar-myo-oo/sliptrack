import 'package:intl/intl.dart';
import 'models.dart';

/// Spreadsheet-friendly export of every transaction. Starts with a UTF-8 BOM
/// so Excel shows Burmese and Thai text correctly.
String transactionsCsv(Iterable<Slip> slips) {
  String cell(Object? v) {
    final text = '${v ?? ''}';
    return RegExp(r'[",\n\r]').hasMatch(text) ||
            text.startsWith(RegExp(r'[=+\-@]'))
        ? '"${text.startsWith(RegExp(r'[=+\-@]')) ? "'" : ''}${text.replaceAll('"', '""')}"'
        : text;
  }

  final rows = [
    [
      'Date',
      'Type',
      'Amount',
      'Currency',
      'Category',
      'Receiver',
      'Sender',
      'Bank',
      'Reference',
      'Note',
      'Status',
    ],
    for (final s in [
      ...slips,
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0))))
      [
        s.date == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(s.date!),
        s.direction == Direction.income
            ? 'Income'
            : s.direction == Direction.expense
            ? 'Expense'
            : 'Unknown',
        s.amountMinor == null ? '' : (s.amountMinor! / 100).toStringAsFixed(2),
        s.currency,
        s.category,
        s.receiver,
        s.sender,
        s.isManualExpense || s.isManualIncome ? 'Manual' : s.bank.label,
        s.reference,
        s.description,
        s.review == ReviewStatus.confirmed ? 'Confirmed' : 'Needs review',
      ],
  ];
  return '﻿${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
}
