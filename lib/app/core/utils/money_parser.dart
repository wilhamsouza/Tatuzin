abstract final class MoneyParser {
  static int parseToCents(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    final sanitized = trimmed.replaceAll(RegExp(r'[^0-9,.-]'), '');
    final isNegative = sanitized.startsWith('-');
    final lastComma = sanitized.lastIndexOf(',');
    final lastDot = sanitized.lastIndexOf('.');
    final separatorIndex = lastComma > lastDot ? lastComma : lastDot;

    String integerPart;
    String decimalPart;

    if (separatorIndex >= 0) {
      integerPart = sanitized
          .substring(0, separatorIndex)
          .replaceAll(RegExp(r'[^0-9]'), '');
      decimalPart = sanitized
          .substring(separatorIndex + 1)
          .replaceAll(RegExp(r'[^0-9]'), '');
    } else {
      integerPart = sanitized.replaceAll(RegExp(r'[^0-9]'), '');
      decimalPart = '';
    }

    if (integerPart.isEmpty) {
      integerPart = '0';
    }

    final normalizedDecimal = '$decimalPart${'00'}'.substring(0, 2);
    final cents = (int.parse(integerPart) * 100) + int.parse(normalizedDecimal);
    return isNegative ? -cents : cents;
  }
}
