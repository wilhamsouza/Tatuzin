export type SyncOperationalStatus =
  | 'healthy'
  | 'attention'
  | 'sync_disabled'
  | 'license_inactive'
  | 'telemetry_limited';

export type SyncOperationalStatusSource =
  | 'observed'
  | 'limited_inference'
  | 'telemetry_gap';

export type SyncTelemetryLevel = 'blocked' | 'partial' | 'limited';

export type SyncObservedFeatureDescriptor = {
  featureKey: string;
  displayName: string;
};

export const observedSyncFeatureCatalog: SyncObservedFeatureDescriptor[] = [
  { featureKey: 'categories', displayName: 'Categorias' },
  { featureKey: 'products', displayName: 'Produtos' },
  { featureKey: 'customers', displayName: 'Clientes' },
  { featureKey: 'suppliers', displayName: 'Fornecedores' },
  { featureKey: 'purchases', displayName: 'Compras' },
  { featureKey: 'sales', displayName: 'Vendas' },
  { featureKey: 'financial_events', displayName: 'Eventos financeiros' },
  { featureKey: 'cash_events', displayName: 'Eventos de caixa' },
  { featureKey: 'fiado_payments', displayName: 'Pagamentos de fiado' },
];

export const telemetryGapFeatures = [
  {
    featureKey: 'sale_cancellations',
    gapType: 'not_observed',
    reason:
      'O backend nao possui um modelo remoto dedicado para cancelamentos de venda.',
  },
  {
    featureKey: 'fiado',
    gapType: 'partial_only',
    reason:
      'O backend observa pagamentos de fiado, mas nao expoe o estado completo do modulo local de fiado.',
  },
  {
    featureKey: 'cash_movements',
    gapType: 'partial_only',
    reason:
      'O backend observa eventos de caixa remotos, nao a visao completa dos movimentos locais do app.',
  },
];

export const unavailableOperationalSignals = [
  'local_queue',
  'retry_state',
  'conflict_state',
  'client_repair_state',
  'client_sync_errors',
] as const;

export function classifySyncOperationalStatus(input: {
  companyIsActive: boolean;
  hasLicense: boolean;
  licenseStatus: string;
  syncEnabled: boolean;
  activeMobileSessionsCount: number;
  observedRemoteRecordCount: number;
}) {
  if (!input.companyIsActive) {
    return {
      status: 'license_inactive' as SyncOperationalStatus,
      statusSource: 'observed' as SyncOperationalStatusSource,
      telemetryLevel: 'blocked' as SyncTelemetryLevel,
      statusReason:
        'A empresa esta inativa. O backend bloqueia qualquer leitura otimista de saude de sync neste tenant.',
    };
  }

  if (!input.hasLicense) {
    return {
      status: 'license_inactive' as SyncOperationalStatus,
      statusSource: 'observed' as SyncOperationalStatusSource,
      telemetryLevel: 'blocked' as SyncTelemetryLevel,
      statusReason:
        'A empresa nao possui licenca cadastrada. O backend nao considera a sync operacionalmente habilitada.',
    };
  }

  if (input.licenseStatus === 'suspended' || input.licenseStatus === 'expired') {
    return {
      status: 'license_inactive' as SyncOperationalStatus,
      statusSource: 'observed' as SyncOperationalStatusSource,
      telemetryLevel: 'blocked' as SyncTelemetryLevel,
      statusReason:
        'A licenca esta suspensa ou expirada. O backend observa este bloqueio de forma direta.',
    };
  }

  if (!input.syncEnabled) {
    return {
      status: 'sync_disabled' as SyncOperationalStatus,
      statusSource: 'observed' as SyncOperationalStatusSource,
      telemetryLevel: 'blocked' as SyncTelemetryLevel,
      statusReason:
        'A sync esta desabilitada na licenca desta empresa. Este e um sinal observado diretamente no backend.',
    };
  }

  if (
    input.activeMobileSessionsCount > 0 &&
    input.observedRemoteRecordCount > 0
  ) {
    return {
      status: 'healthy' as SyncOperationalStatus,
      statusSource: 'limited_inference' as SyncOperationalStatusSource,
      telemetryLevel: 'partial' as SyncTelemetryLevel,
      statusReason:
        'O backend observa licenca habilitada, sessao mobile ativa e espelho remoto em pelo menos uma feature. Esta leitura e limitada: fila local, conflitos e retries nao sao visiveis aqui.',
    };
  }

  if (
    input.activeMobileSessionsCount > 0 &&
    input.observedRemoteRecordCount === 0
  ) {
    return {
      status: 'attention' as SyncOperationalStatus,
      statusSource: 'limited_inference' as SyncOperationalStatusSource,
      telemetryLevel: 'partial' as SyncTelemetryLevel,
      statusReason:
        'O backend observa sessao mobile ativa com sync habilitada, mas ainda nao ve espelho remoto nas features observaveis. Isso nao confirma erro, apenas pede atencao.',
    };
  }

  return {
    status: 'telemetry_limited' as SyncOperationalStatus,
    statusSource: 'telemetry_gap' as SyncOperationalStatusSource,
    telemetryLevel: 'limited' as SyncTelemetryLevel,
    statusReason:
      'O backend nao tem telemetria suficiente para afirmar saude de sync neste tenant. Ele nao enxerga fila local, conflitos, retries ou repair do app.',
  };
}
