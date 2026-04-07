abstract final class QuantityParser {
  static int parseToMil(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    final normalized = trimmed
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9\.-]'), '');

    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return 0;
    }

    return (parsed * 1000).round();
  }
}
