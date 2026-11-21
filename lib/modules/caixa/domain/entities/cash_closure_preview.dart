import 'cash_session.dart';

class CashClosurePreview {
  const CashClosurePreview({
    required this.session,
    required this.snapshotToken,
  });
  final CashSession session;
  final String snapshotToken;
}

/// Strict decimal input; blank and malformed amounts are never treated as zero.
const maxCashAmountCents = 2147483647;

int? parseCashAmount(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d{1,10}([,.]\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split(RegExp('[,.]'));
  final amount =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return amount > maxCashAmountCents ? null : amount;
}

class CashCountResult {
  const CashCountResult({
    required this.denominations,
    required this.coinsCents,
  });
  factory CashCountResult.fromJson(Map<String, dynamic> json) =>
      CashCountResult(
        denominations: {
          for (final item in (json['denominations'] as List? ?? []))
            (item as Map)['valueCents'] as int: item['quantity'] as int,
        },
        coinsCents: json['coinsCents'] as int? ?? 0,
      );
  Map<String, dynamic> toJson() => {
    'denominations': breakdown,
    'coinsCents': coinsCents,
  };
  bool get isValid =>
      coinsCents >= 0 &&
      coinsCents <= maxCashAmountCents &&
      denominations.entries.every(
        (e) =>
            const [
              20000,
              10000,
              5000,
              2000,
              1000,
              500,
              200,
              100,
            ].contains(e.key) &&
            e.value >= 0 &&
            e.value <= 1000000,
      ) &&
      totalCents >= 0 &&
      totalCents <= maxCashAmountCents;
  final Map<int, int> denominations;
  final int coinsCents;
  int get totalCents =>
      denominations.entries.fold(coinsCents, (sum, e) => sum + e.key * e.value);
  List<Map<String, int>> get breakdown => denominations.entries
      .where((e) => e.value > 0)
      .map((e) => {'valueCents': e.key, 'quantity': e.value})
      .toList();
}
