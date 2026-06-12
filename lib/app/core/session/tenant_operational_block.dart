import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_environment.dart';
import '../errors/app_exceptions.dart';
import '../network/endpoint_config.dart';
import '../utils/app_logger.dart';
import 'app_session.dart';
import 'auth_token_storage.dart';

class TenantOperationalBlock {
  const TenantOperationalBlock({
    required this.companyId,
    required this.companyName,
    required this.detectedAt,
    this.acknowledgedAt,
    this.tenantDeletionRequestId,
    this.clientInstanceId,
    this.deviceLabel,
    this.platform,
    this.appVersion,
    this.remoteAcknowledgedAt,
    this.acknowledgementAttemptCount = 0,
    this.acknowledgementNextAttemptAt,
  });

  final String companyId;
  final String? companyName;
  final DateTime detectedAt;
  final DateTime? acknowledgedAt;
  final String? tenantDeletionRequestId;
  final String? clientInstanceId;
  final String? deviceLabel;
  final String? platform;
  final String? appVersion;
  final DateTime? remoteAcknowledgedAt;
  final int acknowledgementAttemptCount;
  final DateTime? acknowledgementNextAttemptAt;

  bool get isAcknowledged => acknowledgedAt != null;
  bool get isRemotelyAcknowledged => remoteAcknowledgedAt != null;
  bool get hasPendingRemoteAcknowledgement =>
      !isRemotelyAcknowledged &&
      tenantDeletionRequestId != null &&
      clientInstanceId != null;

  bool appliesTo(AppSession session) {
    return session.company.remoteId?.trim() == companyId;
  }

  bool shouldPresentFor(AppSession session) {
    return appliesTo(session) ||
        (!session.hasOperationalIdentity && !isAcknowledged);
  }

  TenantOperationalBlock copyWith({
    DateTime? acknowledgedAt,
    DateTime? remoteAcknowledgedAt,
    int? acknowledgementAttemptCount,
    DateTime? acknowledgementNextAttemptAt,
    bool clearAcknowledgementNextAttemptAt = false,
  }) {
    return TenantOperationalBlock(
      companyId: companyId,
      companyName: companyName,
      detectedAt: detectedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      tenantDeletionRequestId: tenantDeletionRequestId,
      clientInstanceId: clientInstanceId,
      deviceLabel: deviceLabel,
      platform: platform,
      appVersion: appVersion,
      remoteAcknowledgedAt: remoteAcknowledgedAt ?? this.remoteAcknowledgedAt,
      acknowledgementAttemptCount:
          acknowledgementAttemptCount ?? this.acknowledgementAttemptCount,
      acknowledgementNextAttemptAt: clearAcknowledgementNextAttemptAt
          ? null
          : acknowledgementNextAttemptAt ?? this.acknowledgementNextAttemptAt,
    );
  }
}

abstract interface class TenantOperationalBlockStorage {
  Future<TenantOperationalBlock?> load();

  Future<void> save(TenantOperationalBlock block);

  Future<void> clear();
}

class SharedPreferencesTenantOperationalBlockStorage
    implements TenantOperationalBlockStorage {
  const SharedPreferencesTenantOperationalBlockStorage();

  static const companyIdKey = 'tenant.pending_deletion.company_id';
  static const companyNameKey = 'tenant.pending_deletion.company_name';
  static const detectedAtKey = 'tenant.pending_deletion.detected_at';
  static const acknowledgedAtKey = 'tenant.pending_deletion.acknowledged_at';
  static const requestIdKey = 'tenant.pending_deletion.request_id';
  static const clientInstanceIdKey =
      'tenant.pending_deletion.client_instance_id';
  static const deviceLabelKey = 'tenant.pending_deletion.device_label';
  static const platformKey = 'tenant.pending_deletion.platform';
  static const appVersionKey = 'tenant.pending_deletion.app_version';
  static const remoteAcknowledgedAtKey =
      'tenant.pending_deletion.remote_acknowledged_at';
  static const acknowledgementAttemptCountKey =
      'tenant.pending_deletion.ack_attempt_count';
  static const acknowledgementNextAttemptAtKey =
      'tenant.pending_deletion.ack_next_attempt_at';

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(companyIdKey);
    await preferences.remove(companyNameKey);
    await preferences.remove(detectedAtKey);
    await preferences.remove(acknowledgedAtKey);
    await preferences.remove(requestIdKey);
    await preferences.remove(clientInstanceIdKey);
    await preferences.remove(deviceLabelKey);
    await preferences.remove(platformKey);
    await preferences.remove(appVersionKey);
    await preferences.remove(remoteAcknowledgedAtKey);
    await preferences.remove(acknowledgementAttemptCountKey);
    await preferences.remove(acknowledgementNextAttemptAtKey);
  }

  @override
  Future<TenantOperationalBlock?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final companyId = preferences.getString(companyIdKey)?.trim();
    final detectedAt = DateTime.tryParse(
      preferences.getString(detectedAtKey) ?? '',
    );
    if (companyId == null || companyId.isEmpty || detectedAt == null) {
      return null;
    }

    final companyName = preferences.getString(companyNameKey)?.trim();
    final acknowledgedAt = DateTime.tryParse(
      preferences.getString(acknowledgedAtKey) ?? '',
    );
    return TenantOperationalBlock(
      companyId: companyId,
      companyName: companyName == null || companyName.isEmpty
          ? null
          : companyName,
      detectedAt: detectedAt,
      acknowledgedAt: acknowledgedAt,
      tenantDeletionRequestId: _readOptional(preferences, requestIdKey),
      clientInstanceId: _readOptional(preferences, clientInstanceIdKey),
      deviceLabel: _readOptional(preferences, deviceLabelKey),
      platform: _readOptional(preferences, platformKey),
      appVersion: _readOptional(preferences, appVersionKey),
      remoteAcknowledgedAt: DateTime.tryParse(
        preferences.getString(remoteAcknowledgedAtKey) ?? '',
      ),
      acknowledgementAttemptCount:
          preferences.getInt(acknowledgementAttemptCountKey) ?? 0,
      acknowledgementNextAttemptAt: DateTime.tryParse(
        preferences.getString(acknowledgementNextAttemptAtKey) ?? '',
      ),
    );
  }

  @override
  Future<void> save(TenantOperationalBlock block) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(companyIdKey, block.companyId);
    final companyName = block.companyName?.trim();
    if (companyName == null || companyName.isEmpty) {
      await preferences.remove(companyNameKey);
    } else {
      await preferences.setString(companyNameKey, companyName);
    }
    await preferences.setString(
      detectedAtKey,
      block.detectedAt.toIso8601String(),
    );
    final acknowledgedAt = block.acknowledgedAt;
    if (acknowledgedAt == null) {
      await preferences.remove(acknowledgedAtKey);
    } else {
      await preferences.setString(
        acknowledgedAtKey,
        acknowledgedAt.toIso8601String(),
      );
    }
    await _writeOptional(
      preferences,
      requestIdKey,
      block.tenantDeletionRequestId,
    );
    await _writeOptional(
      preferences,
      clientInstanceIdKey,
      block.clientInstanceId,
    );
    await _writeOptional(preferences, deviceLabelKey, block.deviceLabel);
    await _writeOptional(preferences, platformKey, block.platform);
    await _writeOptional(preferences, appVersionKey, block.appVersion);
    await _writeDate(
      preferences,
      remoteAcknowledgedAtKey,
      block.remoteAcknowledgedAt,
    );
    await preferences.setInt(
      acknowledgementAttemptCountKey,
      block.acknowledgementAttemptCount,
    );
    await _writeDate(
      preferences,
      acknowledgementNextAttemptAtKey,
      block.acknowledgementNextAttemptAt,
    );
  }

  static String? _readOptional(SharedPreferences preferences, String key) {
    final value = preferences.getString(key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> _writeOptional(
    SharedPreferences preferences,
    String key,
    String? value,
  ) async {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, normalized);
    }
  }

  static Future<void> _writeDate(
    SharedPreferences preferences,
    String key,
    DateTime? value,
  ) async {
    if (value == null) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, value.toUtc().toIso8601String());
    }
  }
}

abstract interface class TenantDeletionAcknowledgementTokenStorage {
  Future<String?> read();

  Future<void> save(String token);

  Future<void> clear();
}

class SecureTenantDeletionAcknowledgementTokenStorage
    implements TenantDeletionAcknowledgementTokenStorage {
  SecureTenantDeletionAcknowledgementTokenStorage({
    SecureTokenStore? secureTokenStore,
  }) : _secureTokenStore = secureTokenStore ?? FlutterSecureTokenStore();

  static const _tokenKey = 'tenant.pending_deletion.ack_token';
  final SecureTokenStore _secureTokenStore;

  @override
  Future<void> clear() => _secureTokenStore.delete(key: _tokenKey);

  @override
  Future<String?> read() => _secureTokenStore.read(key: _tokenKey);

  @override
  Future<void> save(String token) {
    return _secureTokenStore.write(key: _tokenKey, value: token.trim());
  }
}

class TenantDeletionAcknowledgementResult {
  const TenantDeletionAcknowledgementResult({required this.acknowledgedAt});

  final DateTime acknowledgedAt;
}

abstract interface class TenantDeletionAcknowledgementSender {
  Future<TenantDeletionAcknowledgementResult> send({
    required TenantOperationalBlock block,
    required String acknowledgementToken,
  });
}

class HttpTenantDeletionAcknowledgementSender
    implements TenantDeletionAcknowledgementSender {
  HttpTenantDeletionAcknowledgementSender(
    this._endpointConfig, {
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final EndpointConfig _endpointConfig;
  final http.Client _httpClient;

  @override
  Future<TenantDeletionAcknowledgementResult> send({
    required TenantOperationalBlock block,
    required String acknowledgementToken,
  }) async {
    final uri = _endpointConfig.uriFor(
      '/tenant-deletion/acknowledge-pending-deletion',
    );
    if (uri == null) {
      throw const NetworkRequestException(
        'Endpoint remoto nao configurado para acknowledgement.',
      );
    }
    final response = await _httpClient
        .post(
          uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'acknowledgementToken': acknowledgementToken,
            'companyId': block.companyId,
            'clientInstanceId': block.clientInstanceId,
            if (_notBlank(block.deviceLabel)) 'deviceLabel': block.deviceLabel,
            if (_notBlank(block.platform)) 'platform': block.platform,
            if (_notBlank(block.appVersion)) 'appVersion': block.appVersion,
            'acknowledgedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NetworkRequestException(
        'Acknowledgement remoto nao aceito.',
        cause: response.statusCode,
      );
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    final acknowledgedAt = payload is Map<String, dynamic>
        ? DateTime.tryParse(payload['acknowledgedAt']?.toString() ?? '')
        : null;
    return TenantDeletionAcknowledgementResult(
      acknowledgedAt: acknowledgedAt ?? DateTime.now().toUtc(),
    );
  }

  static bool _notBlank(String? value) => value?.trim().isNotEmpty == true;
}

final tenantOperationalBlockStorageProvider =
    Provider<TenantOperationalBlockStorage>((ref) {
      return const SharedPreferencesTenantOperationalBlockStorage();
    });

final tenantDeletionAcknowledgementTokenStorageProvider =
    Provider<TenantDeletionAcknowledgementTokenStorage>((ref) {
      return SecureTenantDeletionAcknowledgementTokenStorage();
    });

final tenantDeletionAcknowledgementSenderProvider =
    Provider<TenantDeletionAcknowledgementSender>((ref) {
      return HttpTenantDeletionAcknowledgementSender(
        ref.watch(appEnvironmentProvider).endpointConfig,
      );
    });

final tenantOperationalBlockControllerProvider =
    AsyncNotifierProvider<
      TenantOperationalBlockController,
      TenantOperationalBlock?
    >(TenantOperationalBlockController.new);

class TenantOperationalBlockController
    extends AsyncNotifier<TenantOperationalBlock?> {
  String? _confirmedOperationalCompanyId;
  bool _acknowledgementInFlight = false;

  @override
  Future<TenantOperationalBlock?> build() async {
    final storage = ref.read(tenantOperationalBlockStorageProvider);
    final block = await storage.load();
    if (block != null && block.companyId == _confirmedOperationalCompanyId) {
      await storage.clear();
      await ref.read(tenantDeletionAcknowledgementTokenStorageProvider).clear();
      return null;
    }
    if (block?.hasPendingRemoteAcknowledgement ?? false) {
      unawaited(
        Future<void>.delayed(Duration.zero, attemptPendingAcknowledgement),
      );
    }
    return block;
  }

  Future<void> markPendingDeletion({
    required String companyId,
    String? companyName,
    String? acknowledgementToken,
    String? tenantDeletionRequestId,
    String? clientInstanceId,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    final normalizedCompanyId = companyId.trim();
    if (normalizedCompanyId.isEmpty) {
      return;
    }

    final current = await future;
    final block = current != null && current.companyId == normalizedCompanyId
        ? TenantOperationalBlock(
            companyId: current.companyId,
            companyName: companyName?.trim().isNotEmpty == true
                ? companyName!.trim()
                : current.companyName,
            detectedAt: current.detectedAt,
            tenantDeletionRequestId:
                tenantDeletionRequestId ?? current.tenantDeletionRequestId,
            clientInstanceId: clientInstanceId ?? current.clientInstanceId,
            deviceLabel: deviceLabel ?? current.deviceLabel,
            platform: platform ?? current.platform,
            appVersion: appVersion ?? current.appVersion,
            remoteAcknowledgedAt:
                tenantDeletionRequestId == current.tenantDeletionRequestId
                ? current.remoteAcknowledgedAt
                : null,
            acknowledgementAttemptCount:
                tenantDeletionRequestId == current.tenantDeletionRequestId
                ? current.acknowledgementAttemptCount
                : 0,
            acknowledgementNextAttemptAt:
                tenantDeletionRequestId == current.tenantDeletionRequestId
                ? current.acknowledgementNextAttemptAt
                : null,
          )
        : TenantOperationalBlock(
            companyId: normalizedCompanyId,
            companyName: companyName?.trim().isNotEmpty == true
                ? companyName!.trim()
                : null,
            detectedAt: DateTime.now().toUtc(),
            tenantDeletionRequestId: tenantDeletionRequestId,
            clientInstanceId: clientInstanceId,
            deviceLabel: deviceLabel,
            platform: platform,
            appVersion: appVersion,
          );

    state = AsyncData(block);
    await ref.read(tenantOperationalBlockStorageProvider).save(block);
    if (acknowledgementToken?.trim().isNotEmpty == true) {
      await ref
          .read(tenantDeletionAcknowledgementTokenStorageProvider)
          .save(acknowledgementToken!.trim());
      unawaited(attemptPendingAcknowledgement());
    }
  }

  Future<void> acknowledge() async {
    final current = await future;
    if (current == null || current.isAcknowledged) {
      return;
    }

    final acknowledged = current.copyWith(
      acknowledgedAt: DateTime.now().toUtc(),
    );
    state = AsyncData(acknowledged);
    await ref.read(tenantOperationalBlockStorageProvider).save(acknowledged);
    unawaited(attemptPendingAcknowledgement(force: true));
  }

  Future<void> attemptPendingAcknowledgement({bool force = false}) async {
    if (_acknowledgementInFlight) {
      return;
    }
    final current = await future;
    if (current == null || !current.hasPendingRemoteAcknowledgement) {
      return;
    }
    final now = DateTime.now().toUtc();
    if (!force && current.acknowledgementNextAttemptAt?.isAfter(now) == true) {
      return;
    }
    final token = await ref
        .read(tenantDeletionAcknowledgementTokenStorageProvider)
        .read();
    if (token == null || token.trim().isEmpty) {
      return;
    }

    _acknowledgementInFlight = true;
    try {
      final result = await ref
          .read(tenantDeletionAcknowledgementSenderProvider)
          .send(block: current, acknowledgementToken: token);
      final acknowledged = current.copyWith(
        remoteAcknowledgedAt: result.acknowledgedAt,
        clearAcknowledgementNextAttemptAt: true,
      );
      state = AsyncData(acknowledged);
      await ref.read(tenantOperationalBlockStorageProvider).save(acknowledged);
      await ref.read(tenantDeletionAcknowledgementTokenStorageProvider).clear();
    } catch (error) {
      final attempts = current.acknowledgementAttemptCount + 1;
      final failed = current.copyWith(
        acknowledgementAttemptCount: attempts,
        acknowledgementNextAttemptAt: now.add(_backoffFor(attempts)),
      );
      state = AsyncData(failed);
      await ref.read(tenantOperationalBlockStorageProvider).save(failed);
      AppLogger.warn(
        '[TenantDeletionAck] envio adiado para retry controlado '
        'attempt=$attempts',
      );
    } finally {
      _acknowledgementInFlight = false;
    }
  }

  Future<void> clearIfOperational(String? companyId) async {
    final normalizedCompanyId = companyId?.trim();
    if (normalizedCompanyId == null || normalizedCompanyId.isEmpty) {
      return;
    }

    _confirmedOperationalCompanyId = normalizedCompanyId;
    final current = state.valueOrNull;
    if (current?.companyId != normalizedCompanyId) {
      return;
    }

    state = const AsyncData(null);
    await ref.read(tenantOperationalBlockStorageProvider).clear();
    await ref.read(tenantDeletionAcknowledgementTokenStorageProvider).clear();
  }

  Duration _backoffFor(int attempt) {
    const steps = <Duration>[
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(hours: 1),
      Duration(hours: 6),
      Duration(hours: 24),
    ];
    final index = (attempt - 1).clamp(0, steps.length - 1);
    return steps[index];
  }
}

void ensureTenantOperationalWriteAllowed(
  TenantOperationalBlock? block,
  AppSession session,
) {
  if (block?.appliesTo(session) ?? false) {
    throw const TenantPendingDeletionException();
  }
}
