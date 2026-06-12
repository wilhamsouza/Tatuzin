import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/app_exceptions.dart';
import 'app_session.dart';

class TenantOperationalBlock {
  const TenantOperationalBlock({
    required this.companyId,
    required this.companyName,
    required this.detectedAt,
    this.acknowledgedAt,
  });

  final String companyId;
  final String? companyName;
  final DateTime detectedAt;
  final DateTime? acknowledgedAt;

  bool get isAcknowledged => acknowledgedAt != null;

  bool appliesTo(AppSession session) {
    return session.company.remoteId?.trim() == companyId;
  }

  bool shouldPresentFor(AppSession session) {
    return appliesTo(session) ||
        (!session.hasOperationalIdentity && !isAcknowledged);
  }

  TenantOperationalBlock copyWith({DateTime? acknowledgedAt}) {
    return TenantOperationalBlock(
      companyId: companyId,
      companyName: companyName,
      detectedAt: detectedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
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

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(companyIdKey);
    await preferences.remove(companyNameKey);
    await preferences.remove(detectedAtKey);
    await preferences.remove(acknowledgedAtKey);
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
  }
}

final tenantOperationalBlockStorageProvider =
    Provider<TenantOperationalBlockStorage>((ref) {
      return const SharedPreferencesTenantOperationalBlockStorage();
    });

final tenantOperationalBlockControllerProvider =
    AsyncNotifierProvider<
      TenantOperationalBlockController,
      TenantOperationalBlock?
    >(TenantOperationalBlockController.new);

class TenantOperationalBlockController
    extends AsyncNotifier<TenantOperationalBlock?> {
  String? _confirmedOperationalCompanyId;

  @override
  Future<TenantOperationalBlock?> build() async {
    final storage = ref.read(tenantOperationalBlockStorageProvider);
    final block = await storage.load();
    if (block?.companyId == _confirmedOperationalCompanyId) {
      await storage.clear();
      return null;
    }
    return block;
  }

  Future<void> markPendingDeletion({
    required String companyId,
    String? companyName,
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
          )
        : TenantOperationalBlock(
            companyId: normalizedCompanyId,
            companyName: companyName?.trim().isNotEmpty == true
                ? companyName!.trim()
                : null,
            detectedAt: DateTime.now().toUtc(),
          );

    state = AsyncData(block);
    await ref.read(tenantOperationalBlockStorageProvider).save(block);
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
