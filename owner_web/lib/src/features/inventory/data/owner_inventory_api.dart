import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/owner_providers.dart';
import '../../../core/network/owner_api_client.dart';
import '../../../core/models/owner_models.dart';

typedef InventoryMap = Map<String, dynamic>;
InventoryMap inventoryMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<InventoryMap> inventoryRows(Object? value) =>
    value is List ? value.whereType<Map>().map(inventoryMap).toList() : [];
int inventoryInt(Object? value) => value is num ? value.toInt() : 0;
String inventoryText(Object? value, [String fallback = 'Não informado']) =>
    value is String && value.trim().isNotEmpty ? value : fallback;
String inventoryKey() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

int? inventoryScaled(String value, {int scale = 1000, bool signed = false}) {
  final input = value.trim().replaceAll(',', '.');
  if (scale == 100 && input.contains('.') && input.split('.').last.length > 2) {
    return null;
  }
  if (!RegExp(
    signed ? r'^-?\d+(\.\d{1,3})?$' : r'^\d+(\.\d{1,3})?$',
  ).hasMatch(input)) {
    return null;
  }
  final n = double.tryParse(input);
  if (n == null || !n.isFinite) return null;
  final result = (n * scale).round();
  return result.abs() <= 2147483647 ? result : null;
}

String inventoryError(Object error) {
  if (error is OwnerApiException) {
    if (error.statusCode == 403) {
      return 'Você não tem autorização para esta operação.';
    }
    if (error.statusCode == 409) {
      return 'Os dados mudaram. Atualize, confira as diferenças e tente novamente. ${error.message}';
    }
    return error.message;
  }
  return 'Não foi possível conectar. Confira sua conexão e tente novamente.';
}

class OwnerInventoryApi {
  const OwnerInventoryApi(this.client, this.token);
  final OwnerApiClient client;
  final Future<String?> Function() token;
  Future<InventoryMap> get(String resource) async {
    final uri = Uri.parse(resource);
    return inventoryMap(
      await client.getJson(
        uri.path,
        queryParameters: uri.queryParameters,
        accessToken: await token(),
      ),
    );
  }

  Future<InventoryMap> post(String resource, InventoryMap body) async =>
      inventoryMap(
        await client.postJson(resource, body: body, accessToken: await token()),
      );
  Future<InventoryMap> put(String resource, InventoryMap body) async =>
      inventoryMap(
        await client.putJson(resource, body: body, accessToken: await token()),
      );
  Future<InventoryMap> patch(String resource, InventoryMap body) async =>
      inventoryMap(
        await client.patchJson(
          resource,
          body: body,
          accessToken: await token(),
        ),
      );
}

final ownerInventoryApiProvider = Provider(
  (ref) => OwnerInventoryApi(
    ref.watch(ownerApiClientProvider),
    ref.watch(ownerAuthStorageProvider).readAccessToken,
  ),
);
final ownerInventoryResourceProvider = FutureProvider.autoDispose
    .family<InventoryMap, String>((ref, resource) async {
      ref.watch(ownerDataScopeProvider);
      ref.watch(ownerRefreshTickProvider);
      return ref.watch(ownerInventoryApiProvider).get(resource);
    });
final ownerInventoryCapabilitiesProvider =
    FutureProvider.autoDispose<InventoryMap>((ref) async {
      ref.watch(ownerDataScopeProvider);
      try {
        return await ref
            .watch(ownerInventoryApiProvider)
            .get('/inventory/capabilities');
      } on OwnerApiException catch (e) {
        if (e.statusCode == 404) return {'enabled': false};
        rethrow;
      }
    });
