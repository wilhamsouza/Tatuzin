import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/cost_overview.dart';
import '../../domain/entities/cost_status.dart';
import '../../domain/entities/cost_type.dart';
import '../../domain/repositories/cost_repository.dart';

class RemoteCostRecord {
  const RemoteCostRecord({
    required this.remoteId,
    required this.localUuid,
    required this.description,
    required this.type,
    required this.category,
    required this.amountCents,
    required this.referenceDate,
    required this.status,
    required this.isRecurring,
    required this.paidAt,
    required this.paymentMethod,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.canceledAt,
  });

  final String remoteId;
  final String localUuid;
  final String description;
  final CostType type;
  final String? category;
  final int amountCents;
  final DateTime referenceDate;
  final CostStatus status;
  final bool isRecurring;
  final DateTime? paidAt;
  final PaymentMethod? paymentMethod;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? canceledAt;

  factory RemoteCostRecord.fromJson(Map<String, dynamic> json) {
    return RemoteCostRecord(
      remoteId: json['id'] as String? ?? '',
      localUuid: json['localUuid'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: CostTypeX.fromDb(json['type'] as String? ?? 'variable'),
      category: json['category'] as String?,
      amountCents: _readInt(json['amountCents']),
      referenceDate: _readDate(json['referenceDate']),
      status: CostStatusX.fromDb(json['status'] as String? ?? 'pending'),
      isRecurring: json['isRecurring'] == true,
      paidAt: _readNullableDate(json['paidAt']),
      paymentMethod: _paymentMethodFromRemote(json['paymentMethod'] as String?),
      notes: json['notes'] as String?,
      createdAt: _readDate(json['createdAt']),
      updatedAt: _readDate(json['updatedAt']),
      canceledAt: _readNullableDate(json['canceledAt']),
    );
  }

  Map<String, dynamic> toCreateBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'description': description,
      'type': type.dbValue,
      'category': category,
      'amountCents': amountCents,
      'referenceDate': referenceDate.toUtc().toIso8601String(),
      'notes': notes,
      'isRecurring': isRecurring,
    };
  }

  static RemoteCostRecord fromCreateInput({
    required String localUuid,
    required CreateCostInput input,
  }) {
    final now = DateTime.now();
    return RemoteCostRecord(
      remoteId: '',
      localUuid: localUuid,
      description: input.description,
      type: input.type,
      category: input.category,
      amountCents: input.amountCents,
      referenceDate: input.referenceDate,
      status: CostStatus.pending,
      isRecurring: input.isRecurring,
      paidAt: null,
      paymentMethod: null,
      notes: input.notes,
      createdAt: now,
      updatedAt: now,
      canceledAt: null,
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static DateTime _readDate(Object? value) {
    return DateTime.parse(value as String? ?? DateTime.now().toIso8601String());
  }

  static DateTime? _readNullableDate(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }

  static PaymentMethod? _paymentMethodFromRemote(String? value) {
    switch (value) {
      case 'pix':
        return PaymentMethod.pix;
      case 'card':
      case 'cartao':
        return PaymentMethod.card;
      case 'cash':
      case 'dinheiro':
        return PaymentMethod.cash;
      default:
        return null;
    }
  }

  static String paymentMethodToRemote(PaymentMethod method) {
    return switch (method) {
      PaymentMethod.cash => 'cash',
      PaymentMethod.pix => 'pix',
      PaymentMethod.card => 'card',
      PaymentMethod.fiado => 'other',
    };
  }
}

class RemoteCostOverview {
  const RemoteCostOverview({
    required this.pendingFixedCents,
    required this.pendingVariableCents,
    required this.overdueFixedCents,
    required this.overdueVariableCents,
    required this.paidFixedThisMonthCents,
    required this.paidVariableThisMonthCents,
    required this.openFixedCount,
    required this.openVariableCount,
  });

  final int pendingFixedCents;
  final int pendingVariableCents;
  final int overdueFixedCents;
  final int overdueVariableCents;
  final int paidFixedThisMonthCents;
  final int paidVariableThisMonthCents;
  final int openFixedCount;
  final int openVariableCount;

  factory RemoteCostOverview.fromJson(Map<String, dynamic> json) {
    return RemoteCostOverview(
      pendingFixedCents: RemoteCostRecord._readInt(json['pendingFixedCents']),
      pendingVariableCents: RemoteCostRecord._readInt(
        json['pendingVariableCents'],
      ),
      overdueFixedCents: RemoteCostRecord._readInt(json['overdueFixedCents']),
      overdueVariableCents: RemoteCostRecord._readInt(
        json['overdueVariableCents'],
      ),
      paidFixedThisMonthCents: RemoteCostRecord._readInt(
        json['paidFixedThisMonthCents'],
      ),
      paidVariableThisMonthCents: RemoteCostRecord._readInt(
        json['paidVariableThisMonthCents'],
      ),
      openFixedCount: RemoteCostRecord._readInt(json['openFixedCount']),
      openVariableCount: RemoteCostRecord._readInt(json['openVariableCount']),
    );
  }

  CostOverview toOverview() {
    return CostOverview(
      pendingFixedCents: pendingFixedCents,
      pendingVariableCents: pendingVariableCents,
      overdueFixedCents: overdueFixedCents,
      overdueVariableCents: overdueVariableCents,
      paidFixedThisMonthCents: paidFixedThisMonthCents,
      paidVariableThisMonthCents: paidVariableThisMonthCents,
      openFixedCount: openFixedCount,
      openVariableCount: openVariableCount,
    );
  }
}
