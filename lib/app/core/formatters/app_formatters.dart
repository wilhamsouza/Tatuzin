abstract final class AppFormatters {
  static String shortDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  static String shortDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  static String currencyFromCents(int cents) {
    final isNegative = cents < 0;
    final absolute = cents.abs();
    final whole = absolute ~/ 100;
    final decimal = (absolute % 100).toString().padLeft(2, '0');
    final grouped = _groupThousands(whole.toString());
    final prefix = isNegative ? '-R\$ ' : 'R\$ ';
    return '$prefix$grouped,$decimal';
  }

  static String currencyInputFromCents(int cents) {
    final absolute = cents.abs();
    final whole = absolute ~/ 100;
    final decimal = (absolute % 100).toString().padLeft(2, '0');
    return '$whole,$decimal';
  }

  static int unitsFromMil(int value) {
    return value ~/ 1000;
  }

  static String quantityFromMil(int value) {
    final isNegative = value < 0;
    final absolute = value.abs();
    final whole = absolute ~/ 1000;
    final decimal = (absolute % 1000).toString().padLeft(3, '0');
    final trimmedDecimal = decimal.replaceFirst(RegExp(r'0+$'), '');
    final normalized = trimmedDecimal.isEmpty
        ? whole.toString()
        : '$whole,$trimmedDecimal';
    return isNegative ? '-$normalized' : normalized;
  }

  static String _groupThousands(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final reverseIndex = digits.length - index;
      buffer.write(digits[index]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write('.');
      }
    }
    return buffer.toString();
  }
}
