import 'dart:convert';

class ReconciliationPayloadSupport {
  const ReconciliationPayloadSupport._();

  static bool signaturesMatch(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    return payloadSignature(local) == payloadSignature(remote);
  }

  static String payloadSignature(Map<String, dynamic> payload) {
    return jsonEncode(canonicalize(payload));
  }

  static Object? canonicalize(Object? value) {
    if (value is Map<String, dynamic>) {
      final sortedKeys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final key in sortedKeys) key: canonicalize(value[key]),
      };
    }
    if (value is List) {
      return value.map(canonicalize).toList();
    }
    return value;
  }

  static Map<String, dynamic> normalizedSalePayload(
    Map<String, dynamic> payload,
  ) {
    final items = payload['items'];
    if (items is! List) {
      return payload;
    }

    final sortedItems =
        items
            .whereType<Map<String, dynamic>>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
          ..sort((left, right) {
            final nameCompare = (left['productNameSnapshot'] as String? ?? '')
                .compareTo(right['productNameSnapshot'] as String? ?? '');
            if (nameCompare != 0) {
              return nameCompare;
            }
            final quantityCompare = (left['quantityMil'] as int? ?? 0)
                .compareTo(right['quantityMil'] as int? ?? 0);
            if (quantityCompare != 0) {
              return quantityCompare;
            }
            return (left['totalPriceCents'] as int? ?? 0).compareTo(
              right['totalPriceCents'] as int? ?? 0,
            );
          });

    return <String, dynamic>{...payload, 'items': sortedItems};
  }
}
