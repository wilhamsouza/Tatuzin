import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_auth_storage.dart';
import '../../../core/auth/admin_providers.dart';
import '../../../core/network/admin_api_client.dart';

typedef PlatformMap = Map<String, dynamic>;

PlatformMap platformMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<PlatformMap> platformItems(Object? value) => value is List
    ? value.whereType<Map>().map(platformMap).toList(growable: false)
    : const [];
String platformText(Object? value, [String fallback = 'Não informado']) =>
    value is String && value.trim().isNotEmpty ? value : fallback;
int platformInt(Object? value) => value is num ? value.toInt() : 0;

int platformTotal(PlatformMap data) => platformInt(
  data['total'] ??
      platformMap(data['pagination'])['total'] ??
      platformMap(data['meta'])['total'],
);

/// UUID generated once per form. Retries retain it, so a timeout cannot create
/// a second case when the server already committed the first request.
String platformRequestKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class PlatformApi {
  const PlatformApi(this.client, this.storage);
  final AdminApiClient client;
  final AdminAuthStorage storage;

  Future<String> _token() async {
    final token = await storage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Sua sessão expirou. Entre novamente.',
        statusCode: 401,
      );
    }
    return token;
  }

  Future<PlatformMap> get(String resource) async {
    final uri = Uri.parse(resource);
    final response = await client.getJson(
      uri.path,
      queryParameters: uri.queryParameters,
      accessToken: await _token(),
    );
    if (response is! Map) {
      throw const AdminApiException(
        message: 'Resposta indisponível. Tente atualizar esta seção.',
      );
    }
    return platformMap(response);
  }

  Future<PlatformMap> post(String resource, PlatformMap body) async =>
      platformMap(
        await client.postJson(
          resource,
          body: body,
          accessToken: await _token(),
        ),
      );

  Future<PlatformMap> patch(String resource, PlatformMap body) async =>
      platformMap(
        await client.patchJson(
          resource,
          body: body,
          accessToken: await _token(),
        ),
      );
}

final platformApiProvider = Provider<PlatformApi>(
  (ref) => PlatformApi(
    ref.watch(adminApiClientProvider),
    ref.watch(adminAuthStorageProvider),
  ),
);

final platformResourceProvider = FutureProvider.autoDispose
    .family<PlatformMap, String>((ref, resource) async {
      ref.watch(
        adminAuthControllerProvider.select((auth) => auth.session?.user.id),
      );
      return ref.watch(platformApiProvider).get(resource);
    });

final platformCapabilitiesProvider = FutureProvider<PlatformMap>((ref) async {
  ref.watch(
    adminAuthControllerProvider.select((auth) => auth.session?.user.id),
  );
  return ref.watch(platformApiProvider).get('/admin/capabilities');
});

bool platformAllowsSection(PlatformMap? capabilities, String key) =>
    platformItems(
      capabilities?['sections'],
    ).any((section) => section['key'] == key && section['allowed'] == true);

bool platformAllowsAction(
  PlatformMap? capabilities,
  String key, {
  String? companyId,
}) {
  final matches = platformItems(
    capabilities?['actions'],
  ).where((item) => item['key'] == key && item['allowed'] == true);
  if (matches.isEmpty) return false;
  // The server revalidates exact target scope. Scoped actions stay visible only
  // in a company context; no client-side broadening is sent to the server.
  return matches.any(
    (item) => platformItems(item['scopes']).any(
      (grant) =>
          (grant['scope'] == 'platform' && grant['scopeId'] == '*') ||
          (companyId != null &&
              grant['scope'] == 'company' &&
              grant['scopeId'] == companyId),
    ),
  );
}

String platformResource(String path, Map<String, String?> query) => Uri(
  path: path,
  queryParameters: {
    for (final entry in query.entries)
      if (entry.value != null && entry.value!.trim().isNotEmpty)
        entry.key: entry.value!,
  },
).toString();
