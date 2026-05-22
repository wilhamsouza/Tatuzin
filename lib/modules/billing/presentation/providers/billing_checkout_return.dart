import 'package:shared_preferences/shared_preferences.dart';

class BillingCheckoutReturnStorage {
  static const _pendingCheckoutReturnKey =
      'billing.checkout.pending_return_started_at';
  static const _pendingCheckoutMaxAge = Duration(hours: 6);

  Future<void> markPending({DateTime? now}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _pendingCheckoutReturnKey,
      (now ?? DateTime.now()).toIso8601String(),
    );
  }

  Future<bool> consumePending({DateTime? now}) async {
    final preferences = await SharedPreferences.getInstance();
    final rawValue = preferences.getString(_pendingCheckoutReturnKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return false;
    }

    await preferences.remove(_pendingCheckoutReturnKey);
    final markedAt = DateTime.tryParse(rawValue);
    if (markedAt == null) {
      return true;
    }

    final currentTime = now ?? DateTime.now();
    return currentTime.difference(markedAt) <= _pendingCheckoutMaxAge;
  }
}
