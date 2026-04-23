import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class AdminFormatters {
  static final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTimeFormatter = DateFormat('dd/MM/yyyy HH:mm');
  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 2,
  );
  static final NumberFormat _decimalFormatter = NumberFormat.decimalPattern(
    'pt_BR',
  );

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

  static String formatIsoDate(String value) {
    final parsed = DateTime.tryParse('${value.trim()}T00:00:00');
    if (parsed == null) {
      return value;
    }
    return _dateFormatter.format(parsed.toLocal());
  }

  static String formatCurrencyFromCents(int cents) {
    return _currencyFormatter.format(cents / 100);
  }

  static String formatBasisPointsPercent(int basisPoints) {
    final percentValue = basisPoints / 100;
    return '${percentValue.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  static String formatQuantityMil(int quantityMil) {
    final value = quantityMil / 1000;
    return _decimalFormatter.format(value);
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

  static String formatBool(
    bool value, {
    String yes = 'Sim',
    String no = 'Nao',
  }) {
    return value ? yes : no;
  }

  static String formatCrmTaskStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'open':
        return 'Aberta';
      case 'completed':
        return 'Concluida';
      case 'canceled':
        return 'Cancelada';
      default:
        return value;
    }
  }

  static String formatCrmTimelineEventType(String value) {
    switch (value.trim().toLowerCase()) {
      case 'note_added':
        return 'Nota CRM';
      case 'task_created':
        return 'Tarefa criada';
      case 'tags_updated':
        return 'Tags atualizadas';
      case 'sale_recorded':
        return 'Venda sincronizada';
      case 'fiado_payment_received':
        return 'Recebimento de fiado';
      default:
        return value;
    }
  }

  static String formatHybridMode(String value) {
    switch (value.trim().toLowerCase()) {
      case 'advisory':
        return 'Advisory';
      case 'governed':
        return 'Governado';
      case 'cloud_master':
        return 'Cloud master';
      case 'hybrid_review':
        return 'Revisao hibrida';
      case 'manual_preview':
        return 'Preview manual';
      case 'scheduled_review':
        return 'Revisao agendada';
      case 'mirrored':
        return 'Espelhado';
      case 'not_mirrored_to_cloud':
        return 'Ainda nao espelhado';
      case 'governed_ready':
        return 'Pronto para governanca';
      case 'needs_attention':
        return 'Precisa de atencao';
      case 'not_seeded':
        return 'Nao semeado';
      case 'requires_future_local_snapshot':
        return 'Depende de snapshot local futuro';
      case 'ready_for_snapshot_reconciliation':
        return 'Pronto para reconciliacao';
      default:
        return value;
    }
  }

  static String formatAlertSeverity(String value) {
    switch (value.trim().toLowerCase()) {
      case 'critical':
        return 'Critico';
      case 'warning':
        return 'Atencao';
      case 'info':
        return 'Informativo';
      default:
        return value;
    }
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
