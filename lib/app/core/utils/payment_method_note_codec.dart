import '../../../modules/vendas/domain/entities/sale_enums.dart';

abstract final class PaymentMethodNoteCodec {
  static final RegExp _tagPattern = RegExp(r'^\[pm:([a-z_]+)\]\s*');

  static String withPaymentMethod(
    String message, {
    PaymentMethod? paymentMethod,
  }) {
    final trimmed = message.trim();
    if (paymentMethod == null) {
      return trimmed;
    }
    return '[pm:${paymentMethod.dbValue}] $trimmed';
  }

  static PaymentMethod? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final match = _tagPattern.firstMatch(raw);
    if (match == null) {
      return null;
    }

    return PaymentMethodX.fromDb(match.group(1)!);
  }

  static String? clean(String? raw) {
    if (raw == null) {
      return null;
    }

    final cleaned = raw.replaceFirst(_tagPattern, '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
