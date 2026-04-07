import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class AdminFormatters {
  static final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTimeFormatter = DateFormat('dd/MM/yyyy HH:mm');

  static String formatDate(DateTime? value) {
    if (value == null) {
      return 'Nao definido';
    }
    return _dateFormatter.format(value.toLocal());
  }

  static String formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Nao definido';
    }
    return _dateTimeFormatter.format(value.toLocal());
  }

  static String formatLicenseStatus(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'trial':
        return 'Trial';
      case 'active':
        return 'Ativa';
      case 'suspended':
        return 'Suspensa';
      case 'expired':
        return 'Expirada';
      case 'without_license':
        return 'Sem licenca';
      default:
        return (value == null || value.trim().isEmpty) ? 'Nao definido' : value;
    }
  }

  static String formatMembershipRole(String value) {
    switch (value.toUpperCase()) {
      case 'OWNER':
        return 'Owner';
      case 'MANAGER':
        return 'Gestor';
      case 'CASHIER':
        return 'Caixa';
      default:
        return value;
    }
  }

  static String formatPlan(String value) {
    if (value.trim().isEmpty) {
      return 'Nao definido';
    }
    final normalized = value.trim();
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }

  static String formatBool(bool value, {String yes = 'Sim', String no = 'Nao'}) {
    return value ? yes : no;
  }

  static Color statusColor(BuildContext context, String? status) {
    final scheme = Theme.of(context).colorScheme;
    switch ((status ?? '').toLowerCase()) {
      case 'active':
        return const Color(0xFF166534);
      case 'trial':
        return const Color(0xFF7C3AED);
      case 'expired':
        return const Color(0xFFB45309);
      case 'suspended':
        return scheme.error;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  static Color statusBackgroundColor(BuildContext context, String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'active':
        return const Color(0xFFDCFCE7);
      case 'trial':
        return const Color(0xFFEDE9FE);
      case 'expired':
        return const Color(0xFFFEF3C7);
      case 'suspended':
        return const Color(0xFFFEE2E2);
      default:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }
}
