import 'models.dart';

enum DataGroup { receipts, income, expenses, savings }

extension DataGroupLabel on DataGroup {
  String get label => switch (this) {
    DataGroup.receipts => 'Imported receipts',
    DataGroup.income => 'Manual income',
    DataGroup.expenses => 'Manual expenses',
    DataGroup.savings => 'Savings entries',
  };
  bool matches(Slip slip) => switch (this) {
    DataGroup.receipts => !slip.isManualIncome && !slip.isManualExpense,
    DataGroup.income => slip.isManualIncome,
    DataGroup.expenses => slip.isManualExpense,
    DataGroup.savings => false,
  };
}
