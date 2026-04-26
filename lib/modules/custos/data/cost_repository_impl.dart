import '../domain/entities/cost_entry.dart';
import '../domain/entities/cost_overview.dart';
import '../domain/entities/cost_status.dart';
import '../domain/entities/cost_type.dart';
import '../domain/repositories/cost_repository.dart';
import 'sqlite_cost_repository.dart';

class CostRepositoryImpl implements CostRepository {
  const CostRepositoryImpl({required SqliteCostRepository localRepository})
    : _localRepository = localRepository;

  final SqliteCostRepository _localRepository;

  // /api/financial-events exists, but it only accepts sale_canceled and
  // fiado_payment events. It is not a compatible ERP cost CRUD contract.
  static const bool hasCompatibleRemoteCostContract = false;

  @override
  Future<CostEntry> cancelCost({required int costId, String? notes}) {
    return _localRepository
        .cancelCost(costId: costId, notes: notes)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<int> createCost(CreateCostInput input) {
    return _localRepository
        .createCost(input)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostEntry> fetchCost(int costId) {
    return _localRepository
        .fetchCost(costId)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostOverview> fetchOverview() {
    return _localRepository.fetchOverview().timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostEntry> markCostPaid(MarkCostPaidInput input) {
    return _localRepository
        .markCostPaid(input)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<List<CostEntry>> searchCosts({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) {
    return _localRepository
        .searchCosts(
          type: type,
          query: query,
          status: status,
          from: from,
          to: to,
          overdueOnly: overdueOnly,
        )
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostEntry> updateCost({
    required int costId,
    required UpdateCostInput input,
  }) {
    return _localRepository
        .updateCost(costId: costId, input: input)
        .timeout(const Duration(seconds: 8));
  }
}
