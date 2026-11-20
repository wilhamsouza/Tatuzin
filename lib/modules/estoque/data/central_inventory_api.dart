import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/network/contracts/api_client_contract.dart';
import '../../../app/core/network/network_providers.dart';
import '../../../app/core/session/auth_token_storage.dart';
import '../../../app/core/session/session_provider.dart';
import '../../../app/core/sync/sync_providers.dart';

String inventoryRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

typedef InventoryJson = Map<String, dynamic>;
InventoryJson inventoryJson(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<InventoryJson> inventoryRows(Object? value) => value is List
    ? value.whereType<Map>().map(inventoryJson).toList(growable: true)
    : <InventoryJson>[];
int inventoryNumber(Object? value) => value is num ? value.toInt() : 0;
String inventoryText(Object? value, [String fallback = 'Não informado']) =>
    value is String && value.trim().isNotEmpty ? value : fallback;
String inventoryItemKey(InventoryJson item) =>
    '${item['productId']}:${item['productVariantId'] ?? ''}';

final centralInventoryApiProvider = Provider<CentralInventoryApi>((ref) {
  final session = ref.watch(appSessionProvider);
  final key = ref.watch(sessionIsolationKeyProvider);
  final runtimeKey = ref.watch(sessionRuntimeKeyProvider);
  return CentralInventoryApi(
    client: ref.read(realApiClientProvider),
    tokens: ref.read(authTokenStorageProvider),
    namespace: key,
    userId: session.user.remoteId ?? '',
    canWrite: session.canAccessPermission('stock.adjust'),
    ensureCurrent: () {
      if (ref.read(sessionIsolationKeyProvider) != key ||
          ref.read(sessionRuntimeKeyProvider) != runtimeKey) {
        throw const ValidationException('A empresa mudou. Reabra o estoque.');
      }
    },
    prepareWrite: () async {
      if (!ref.read(appSessionProvider).canStartSync) {
        throw const ValidationException(
          'Conecte-se para confirmar. O rascunho permanece neste aparelho.',
        );
      }
      final queue = ref.read(operationalSyncQueueRepositoryProvider);
      for (var attempt = 0; attempt < 20; attempt++) {
        final summaries = await queue.listFeatureSummaries();
        if (summaries.any((row) => row.hasAttention)) {
          throw const ValidationException(
            'Resolva as falhas ou conflitos de sincronização antes de alterar o estoque.',
          );
        }
        if (summaries.every(
          (row) => row.pendingForDisplay == 0 && !row.hasActiveProcessing,
        )) {
          return;
        }
        await ref
            .read(operationalSyncRunnerProvider)
            .run(retryOnly: false, ignoreRetryBackoff: true);
      }
      throw const ValidationException(
        'Ainda existem operações locais pendentes. Conclua a sincronização antes de confirmar.',
      );
    },
  );
});

/// Inventory is server authoritative. Local storage holds read snapshots and
/// explicitly marked drafts, never confirmed balance mutations.
class CentralInventoryApi {
  CentralInventoryApi({
    required this.client,
    required this.tokens,
    required this.namespace,
    required this.userId,
    required this.canWrite,
    required this.prepareWrite,
    required this.ensureCurrent,
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final ApiClientContract client;
  final AuthTokenStorage tokens;
  final String namespace;
  final String userId;
  final bool canWrite;
  final Future<void> Function() prepareWrite;
  final void Function() ensureCurrent;
  final Future<SharedPreferences> Function() _preferences;
  String get _prefix => 'inventory.workspace.$namespace.$userId.';

  Future<ApiRequestOptions> _options([
    Map<String, Object?> query = const {},
  ]) async {
    ensureCurrent();
    final token = await tokens.readAccessToken();
    ensureCurrent();
    if (token == null || token.isEmpty) {
      throw const AuthenticationException(
        'Entre novamente para acessar o estoque.',
      );
    }
    return ApiRequestOptions(
      headers: {'Authorization': 'Bearer $token'},
      queryParameters: query,
    );
  }

  Future<InventoryJson> read(
    String resource, {
    Map<String, Object?> query = const {},
    bool allowCache = true,
  }) async {
    final key = '$_prefix$resource?${jsonEncode(query)}';
    try {
      final response = await client.getJson(
        '/inventory$resource',
        options: await _options(query),
      );
      ensureCurrent();
      final data = <String, dynamic>{
        ...response.data,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'isCached': false,
      };
      await (await _preferences()).setString(key, jsonEncode(data));
      return data;
    } catch (error) {
      if (!allowCache ||
          error is AuthenticationException ||
          (error is NetworkRequestException &&
              (error.cause == 401 || error.cause == 403))) {
        rethrow;
      }
      ensureCurrent();
      final cached = (await _preferences()).getString(key);
      if (cached == null) rethrow;
      return {...inventoryJson(jsonDecode(cached)), 'isCached': true};
    }
  }

  Future<InventoryJson> write(
    String method,
    String resource,
    InventoryJson body,
  ) async {
    if (!canWrite) {
      throw const ValidationException('Seu acesso permite apenas consulta.');
    }
    await prepareWrite();
    ensureCurrent();
    final capabilities = await read('/capabilities', allowCache: false);
    final allowed = resource == '/initial-balances'
        ? capabilities['canInitializeStock'] == true
        : resource.startsWith('/counts')
        ? capabilities['canCount'] == true
        : capabilities['canAdjust'] == true;
    if (capabilities['enabled'] != true || !allowed) {
      throw const ValidationException(
        'A operação central de estoque ainda não está habilitada para esta empresa.',
      );
    }
    final options = await _options();
    final response = switch (method) {
      'PUT' => await client.putJson(
        '/inventory$resource',
        body: body,
        options: options,
      ),
      'PATCH' => await client.patchJson(
        '/inventory$resource',
        body: body,
        options: options,
      ),
      _ => await client.postJson(
        '/inventory$resource',
        body: body,
        options: options,
      ),
    };
    ensureCurrent();
    return response.data;
  }

  Future<List<InventoryJson>> drafts() async {
    ensureCurrent();
    final source = (await _preferences()).getString('${_prefix}drafts');
    if (source == null) return [];
    return inventoryRows(jsonDecode(source));
  }

  Future<void> saveDraft(InventoryJson draft) async {
    ensureCurrent();
    final values = await drafts();
    values.removeWhere((row) => row['id'] == draft['id']);
    values.insert(0, {
      ...draft,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await (await _preferences()).setString(
      '${_prefix}drafts',
      jsonEncode(values),
    );
  }

  Future<void> removeDraft(String id) async {
    final values = await drafts();
    values.removeWhere((row) => row['id'] == id);
    await (await _preferences()).setString(
      '${_prefix}drafts',
      jsonEncode(values),
    );
  }

  Future<InventoryJson> publishDraft(InventoryJson draft) async {
    var session = inventoryJson(draft['session']);
    final localId = inventoryText(draft['id']);
    if (session['id'] == null) {
      final created = await write('POST', '/counts', {
        'requestId': draft['requestId'],
        'name': draft['name'],
      });
      session = inventoryJson(created['session']);
      // Persist the server identity before a second request; retry does not
      // create a second session if connectivity is interrupted.
      draft = {...draft, 'session': session};
      await saveDraft(draft);
    }
    final result = await write('PUT', '/counts/${session['id']}/items', {
      'expectedRevision': session['revision'],
      'items': [
        ...inventoryRows(draft['items']).map(
          (row) => {
            'productId': row['productId'],
            'productVariantId': row['productVariantId'],
            'countedStockMil': row['countedStockMil'],
            'expectedStockRevision':
                row['expectedStockRevision'] ?? row['stockRevision'],
          },
        ),
        ...inventoryRows(draft['removedItems']).map(
          (row) => {
            'productId': row['productId'],
            'productVariantId': row['productVariantId'],
            'remove': true,
          },
        ),
      ],
    });
    await removeDraft(localId);
    return result;
  }

  InventoryJson newDraft(String name) => {
    'id': 'draft-${inventoryRequestId()}',
    'requestId': inventoryRequestId(),
    'name': name,
    'assigneeUserId': userId,
    'items': <InventoryJson>[],
  };
}
