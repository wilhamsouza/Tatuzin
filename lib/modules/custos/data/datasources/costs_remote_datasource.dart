import '../../domain/entities/cost_status.dart';
import '../../domain/entities/cost_type.dart';
import '../../domain/repositories/cost_repository.dart';
import '../models/remote_cost_record.dart';

abstract interface class CostsRemoteDatasource {
  Future<RemoteCostOverview> fetchSummary();

  Future<List<RemoteCostRecord>> list({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  });

  Future<RemoteCostRecord> create(RemoteCostRecord record);

  Future<RemoteCostRecord> update({
    required String remoteId,
    required UpdateCostInput input,
  });

  Future<RemoteCostRecord> pay({
    required String remoteId,
    required MarkCostPaidInput input,
  });

  Future<RemoteCostRecord> cancel({required String remoteId, String? notes});
}
