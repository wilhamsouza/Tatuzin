import 'cash_enums.dart';

class CashManualMovementInput {
  const CashManualMovementInput({
    required this.type,
    required this.amountCents,
    required this.description,
  });

  final CashMovementType type;
  final int amountCents;
  final String description;
}
