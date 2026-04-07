import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../system/presentation/providers/system_providers.dart';

final accountCloudStatusProvider = Provider<AccountCloudStatusSnapshot>((ref) {
  final authStatus = ref.watch(authStatusProvider);
  final session = ref.watch(appSessionProvider);
  final company = ref.watch(currentCompanyContextProvider);
  final connectionAsync = ref.watch(backendConnectionStatusProvider);
  final syncOverview = ref.watch(syncHealthOverviewProvider);
  final connection = connectionAsync.valueOrNull;
  final hasRecentSync = syncOverview.lastProcessedAt != null;

  if (!authStatus.isRemoteAuthenticated || session.isLocalDefault) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Modo local',
      statusMessage:
          'O Tatuzin esta pronto para operar neste aparelho. Quando voce entrar na conta, a nuvem volta a acompanhar sua empresa.',
      tone: AppStatusTone.neutral,
      icon: Icons.offline_bolt_rounded,
      accountModeLabel: 'Modo local',
      cloudAvailabilityLabel: 'Uso local disponivel',
      supportingLabel: hasRecentSync ? 'Ultima sincronizacao' : null,
      supportingValue: hasRecentSync
          ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
          : null,
    );
  }

  if (!company.hasCloudLicense) {
    return const AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua empresa ainda nao tem uma licenca de nuvem pronta para sincronizar. O uso local continua disponivel.',
      tone: AppStatusTone.warning,
      icon: Icons.info_outline_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
    );
  }

  if (company.isSuspendedLicense) {
    return const AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua licenca de nuvem esta suspensa. O app continua funcionando no modo local.',
      tone: AppStatusTone.warning,
      icon: Icons.pause_circle_outline_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
    );
  }

  if (company.isExpiredLicense) {
    return const AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua licenca de nuvem venceu. O uso local continua disponivel enquanto a conta precisa de atencao.',
      tone: AppStatusTone.warning,
      icon: Icons.event_busy_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
    );
  }

  if (!company.syncEnabled) {
    return const AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'A nuvem desta empresa esta desativada no momento. O uso local continua liberado.',
      tone: AppStatusTone.warning,
      icon: Icons.cloud_off_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
    );
  }

  if (connectionAsync.isLoading && connection == null) {
    return const AccountCloudStatusSnapshot(
      statusLabel: 'Sincronizando',
      statusMessage: 'Estamos verificando sua conexao com a nuvem.',
      tone: AppStatusTone.info,
      icon: Icons.sync_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Verificando a nuvem',
    );
  }

  if (connection == null || !connection.isReachable) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Sem internet',
      statusMessage:
          'Nao conseguimos falar com a nuvem agora. Mesmo assim, o Tatuzin continua funcionando localmente.',
      tone: AppStatusTone.warning,
      icon: Icons.cloud_off_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Sem internet',
      supportingLabel: hasRecentSync
          ? 'Ultima sincronizacao'
          : 'Ultima verificacao',
      supportingValue: hasRecentSync
          ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
          : AppFormatters.shortDateTime(
              connection?.checkedAt ?? DateTime.now(),
            ),
    );
  }

  if (syncOverview.totalErrors > 0 ||
      syncOverview.totalBlocked > 0 ||
      syncOverview.totalConflicts > 0) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua conta esta conectada, mas a nuvem precisa de atencao para voltar ao ritmo normal.',
      tone: AppStatusTone.warning,
      icon: Icons.error_outline_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Precisa de atencao',
      supportingLabel: hasRecentSync
          ? 'Ultima sincronizacao'
          : 'Ultima verificacao',
      supportingValue: hasRecentSync
          ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
          : AppFormatters.shortDateTime(connection.checkedAt),
    );
  }

  if (syncOverview.totalPending > 0 || syncOverview.totalProcessing > 0) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Sincronizando',
      statusMessage:
          'Suas atualizacoes estao sendo enviadas para a nuvem em segundo plano.',
      tone: AppStatusTone.info,
      icon: Icons.sync_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem disponivel',
      supportingLabel: hasRecentSync ? 'Ultima sincronizacao' : null,
      supportingValue: hasRecentSync
          ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
          : null,
    );
  }

  return AccountCloudStatusSnapshot(
    statusLabel: 'Sincronizado',
    statusMessage:
        'Sua conta esta conectada e a nuvem esta funcionando normalmente para a sua empresa.',
    tone: AppStatusTone.success,
    icon: Icons.cloud_done_rounded,
    accountModeLabel: 'Conta conectada',
    cloudAvailabilityLabel: 'Nuvem disponivel',
    supportingLabel: hasRecentSync
        ? 'Ultima sincronizacao'
        : connection.remoteCompanyName == null
        ? 'Conta conectada'
        : 'Empresa na nuvem',
    supportingValue: hasRecentSync
        ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
        : connection.remoteCompanyName ?? authStatus.companyLabel,
  );
});

final internalMobileSurfaceAccessProvider =
    Provider<InternalMobileSurfaceAccess>((ref) {
      final authStatus = ref.watch(authStatusProvider);
      final canOpenTechnicalSystem = kDebugMode || authStatus.isPlatformAdmin;
      final canOpenAdminCloud =
          authStatus.isRemoteAuthenticated && authStatus.isPlatformAdmin;

      return InternalMobileSurfaceAccess(
        canOpenTechnicalSystem: canOpenTechnicalSystem,
        canOpenAdminCloud: canOpenAdminCloud,
      );
    });

class AccountCloudStatusSnapshot {
  const AccountCloudStatusSnapshot({
    required this.statusLabel,
    required this.statusMessage,
    required this.tone,
    required this.icon,
    required this.accountModeLabel,
    required this.cloudAvailabilityLabel,
    this.supportingLabel,
    this.supportingValue,
  });

  final String statusLabel;
  final String statusMessage;
  final AppStatusTone tone;
  final IconData icon;
  final String accountModeLabel;
  final String cloudAvailabilityLabel;
  final String? supportingLabel;
  final String? supportingValue;
}

class InternalMobileSurfaceAccess {
  const InternalMobileSurfaceAccess({
    required this.canOpenTechnicalSystem,
    required this.canOpenAdminCloud,
  });

  final bool canOpenTechnicalSystem;
  final bool canOpenAdminCloud;

  bool get hasAnyAccess => canOpenTechnicalSystem || canOpenAdminCloud;
}
