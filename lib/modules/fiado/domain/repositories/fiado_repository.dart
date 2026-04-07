import '../entities/fiado_account.dart';
import '../entities/fiado_detail.dart';
import '../entities/fiado_payment_input.dart';

abstract interface class FiadoRepository {
  Future<List<FiadoAccount>> search({
    String query = '',
    String? status,
    bool overdueOnly = false,
  });

  Future<FiadoDetail> fetchDetail(int fiadoId);

  Future<FiadoDetail> registerPayment(FiadoPaymentInput input);
}
