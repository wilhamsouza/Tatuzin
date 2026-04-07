import '../endpoint_config.dart';

abstract interface class RemoteDatasourceContract {
  String get featureKey;

  EndpointConfig get endpointConfig;

  bool get requiresAuthentication;

  Future<bool> canReachRemote();
}
