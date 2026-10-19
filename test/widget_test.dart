import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliptrack/shared/screens.dart';

void main() {
  testWidgets('empty state clearly describes actual, empty finances', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState('No receipts', 'Import your first slip.'),
        ),
      ),
    );
    expect(find.text('No receipts'), findsOneWidget);
    expect(find.text('Import your first slip.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
