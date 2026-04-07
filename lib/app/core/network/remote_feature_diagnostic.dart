class RemoteFeatureDiagnostic {
  const RemoteFeatureDiagnostic({
    required this.featureKey,
    required this.displayName,
    required this.reachable,
    required this.requiresAuthentication,
    required this.isAuthenticated,
    required this.endpointLabel,
    required this.summary,
    required this.lastCheckedAt,
    required this.capabilities,
  });

  final String featureKey;
  final String displayName;
  final bool reachable;
  final bool requiresAuthentication;
  final bool isAuthenticated;
  final String endpointLabel;
  final String summary;
  final DateTime lastCheckedAt;
  final List<String> capabilities;
}
