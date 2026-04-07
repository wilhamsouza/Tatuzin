import 'fiado_account.dart';
import 'fiado_payment_entry.dart';

class FiadoDetail {
  const FiadoDetail({required this.account, required this.entries});

  final FiadoAccount account;
  final List<FiadoPaymentEntry> entries;
}
