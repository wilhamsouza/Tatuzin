abstract interface class AppSnapshotRemoteDataSource {
  Future<AppSnapshotResponse> fetchSnapshot({
    Iterable<String> features = const <String>[],
  });
}

class AppSnapshotResponse {
  const AppSnapshotResponse({
    required this.companyId,
    required this.serverFirstSnapshotVersion,
    required this.features,
  });

  final String companyId;
  final String serverFirstSnapshotVersion;
  final Map<String, AppSnapshotFeature> features;

  factory AppSnapshotResponse.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    final parsedFeatures = <String, AppSnapshotFeature>{};
    if (rawFeatures is Map<String, dynamic>) {
      for (final entry in rawFeatures.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          parsedFeatures[entry.key] = AppSnapshotFeature.fromJson(value);
        }
      }
    }

    return AppSnapshotResponse(
      companyId: _stringValue(json['companyId']) ?? '',
      serverFirstSnapshotVersion:
          _stringValue(json['serverFirstSnapshotVersion']) ?? '0',
      features: parsedFeatures,
    );
  }
}

class AppSnapshotFeature {
  const AppSnapshotFeature({
    required this.feature,
    required this.mode,
    required this.count,
    this.updatedAt,
  });

  final String feature;
  final String mode;
  final int count;
  final DateTime? updatedAt;

  factory AppSnapshotFeature.fromJson(Map<String, dynamic> json) {
    return AppSnapshotFeature(
      feature: _stringValue(json['feature']) ?? '',
      mode: _stringValue(json['mode']) ?? 'server_first_cache',
      count: _intValue(json['count']) ?? 0,
      updatedAt: DateTime.tryParse(_stringValue(json['updatedAt']) ?? ''),
    );
  }
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
