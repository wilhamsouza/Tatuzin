abstract final class OwnerFormatters {
  static String moneyFromCents(int amountCents, {String currency = 'BRL'}) {
    final value = (amountCents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return currency.toUpperCase() == 'BRL' ? 'R\$ $value' : '$currency $value';
  }

  static String integer(int value) {
    return value.toString();
  }

  static String quantityFromMil(int quantityMil) {
    final value = quantityMil / 1000;
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  static String date(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Indisponível';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return 'Indisponível';
    }
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  static String status(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'active':
      case 'ativo':
        return 'Ativo';
      case 'pending':
        return 'Pendente';
      case 'in_process':
        return 'Em processamento';
      case 'paid':
      case 'approved':
        return 'Pago';
      case 'failed':
        return 'Falhou';
      case 'rejected':
        return 'Rejeitado';
      case 'cancelled':
      case 'canceled':
        return 'Cancelado';
      case 'refunded':
        return 'Estornado';
      case 'blocked':
        return 'Bloqueado';
      case 'revoked':
        return 'Revogado';
      default:
        return value == null || value.trim().isEmpty ? 'Indefinido' : value;
    }
  }
}
