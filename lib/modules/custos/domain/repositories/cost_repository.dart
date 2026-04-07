import '../../../vendas/domain/entities/sale_enums.dart';
import '../entities/cost_entry.dart';
import '../entities/cost_overview.dart';
import '../entities/cost_status.dart';
import '../entities/cost_type.dart';

class CreateCostInput {
  const CreateCostInput({
    required this.description,
    required this.type,
    required this.amountCents,
    required this.referenceDate,
    this.category,
    this.notes,
    this.isRecurring = false,
  });

  final String description;
  final CostType type;
  final String? category;
  final int amountCents;
  final DateTime referenceDate;
  final String? notes;
  final bool isRecurring;
}

class UpdateCostInput {
  const UpdateCostInput({
    required this.description,
    required this.type,
    required this.amountCents,
    required this.referenceDate,
    this.category,
    this.notes,
    this.isRecurring = false,
  });

  final String description;
  final CostType type;
  final String? category;
  final int amountCents;
  final DateTime referenceDate;
  final String? notes;
  final bool isRecurring;
}

class MarkCostPaidInput {
  const MarkCostPaidInput({
    required this.costId,
    required this.paidAt,
    required this.paymentMethod,
    required this.registerInCash,
    this.notes,
  });

  final int costId;
  final DateTime paidAt;
  final PaymentMethod paymentMethod;
  final bool registerInCash;
  final String? notes;
}

abstract class CostRepository {
  Future<CostOverview> fetchOverview();

  Future<List<CostEntry>> searchCosts({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  });

  Future<CostEntry> fetchCost(int costId);

  Future<int> createCost(CreateCostInput input);

  Future<CostEntry> updateCost({
    required int costId,
    required UpdateCostInput input,
  });

  Future<CostEntry> markCostPaid(MarkCostPaidInput input);

  Future<CostEntry> cancelCost({required int costId, String? notes});
}
