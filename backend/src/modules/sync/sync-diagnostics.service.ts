import type { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { ALLOWED_LOCAL_FIRST_SYNC_ENTITIES } from './sync-policy.service';

export type SyncDiagnosticClassification =
  | 'REPROCESSABLE'
  | 'NEEDS_PRODUCT_MAPPING'
  | 'MANUAL_STOCK_REVIEW'
  | 'IRRECOVERABLE_LEGACY_EVENT'
  | 'DANGEROUS'
  | 'UNKNOWN';

export type SyncDiagnosticRecommendedAction =
  | 'REPROCESS'
  | 'ARCHIVE_LEGACY'
  | 'MANUAL_STOCK_ADJUSTMENT'
  | 'REVIEW_PRODUCT_MAPPING'
  | 'CONTACT_SUPPORT'
  | 'NO_ACTION';

export type SyncDiagnosticInput = {
  companyId: string;
  entity: string;
  operation: string;
  status?: string | null;
  rejectionCode?: string | null;
  code?: string | null;
  payload: Prisma.JsonValue | null;
};

export type SyncDiagnosticResult = {
  classification: SyncDiagnosticClassification;
  recommendedAction: SyncDiagnosticRecommendedAction;
  canReprocess: boolean;
  canArchive: boolean;
  canCreateManualStockAdjustment: boolean;
  message: string;
  risks: string[];
  blockers: string[];
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const sensitiveKeyFragments = [
  'authorization',
  'apiKey',
  'apikey',
  'accessToken',
  'refreshToken',
  'token',
  'secret',
  'password',
  'mercadoPago',
  'headers',
  'cardNumber',
  'card_number',
  'securityCode',
  'cvv',
  'paymentPayload',
];

const stockDeductionPreviewKeys = [
  'saleUuid',
  'saleLocalId',
  'productId',
  'productVariantId',
  'quantityDeltaMil',
  'stockBeforeMil',
  'stockAfterMil',
  'occurredAt',
];

const cashSessionPreviewKeys = [
  'uuid',
  'status',
  'openedAt',
  'closedAt',
  'expectedBalanceCents',
  'initialFloatCents',
  'countedBalanceCents',
  'differenceCents',
  'operatorName',
];

const genericPreviewKeys = [
  'uuid',
  'localUuid',
  'localId',
  'status',
  'state',
  'occurredAt',
  'createdAt',
  'updatedAt',
  'code',
  'message',
];

export class SyncDiagnosticsService {
  async classify(input: SyncDiagnosticInput): Promise<SyncDiagnosticResult> {
    const payload = asRecord(input.payload);

    if (containsSensitiveValue(input.payload)) {
      return diagnostic({
        classification: 'DANGEROUS',
        recommendedAction: 'CONTACT_SUPPORT',
        message:
          'Payload contem dado sensivel ou cabecalho interno. A acao automatica foi bloqueada.',
        blockers: ['Payload sensivel nao pode ser reprocessado pelo Centro de Sincronizacao.'],
        risks: ['Reprocessar poderia expor ou reutilizar credenciais/pagamentos.'],
      });
    }

    if (
      !ALLOWED_LOCAL_FIRST_SYNC_ENTITIES.includes(
        input.entity as (typeof ALLOWED_LOCAL_FIRST_SYNC_ENTITIES)[number],
      )
    ) {
      return diagnostic({
        classification: 'DANGEROUS',
        recommendedAction: 'CONTACT_SUPPORT',
        message: 'Entidade fora do sync operacional local-first.',
        blockers: ['Entidade desconhecida ou server-first.'],
        risks: ['Reprocessamento poderia alterar dominio nao operacional.'],
      });
    }

    if (input.entity === 'stockDeduction') {
      return this.classifyStockDeduction(input.companyId, payload);
    }

    if (input.entity === 'cashSession' && input.operation === 'update') {
      return this.classifyCashSessionUpdate(payload);
    }

    if (input.status === 'ACCEPTED' || input.status === 'DUPLICATE') {
      return diagnostic({
        classification: 'UNKNOWN',
        recommendedAction: 'NO_ACTION',
        message: 'Evento ja foi processado ou deduplicado.',
        blockers: ['Nao ha acao recomendada para evento ja processado.'],
      });
    }

    if (input.rejectionCode === 'SYNC_MATERIALIZATION_FAILED') {
      return diagnostic({
        classification: 'UNKNOWN',
        recommendedAction: 'CONTACT_SUPPORT',
        message:
          'Falha generica sem regra segura especifica para reprocessamento automatico.',
        blockers: ['A falha precisa de revisao tecnica antes de qualquer escrita.'],
      });
    }

    return diagnostic({
      classification: 'UNKNOWN',
      recommendedAction: 'CONTACT_SUPPORT',
      message: 'Nao ha regra automatica segura para este evento.',
      blockers: ['Classificacao desconhecida.'],
    });
  }

  safePayloadPreview(entity: string, payload: Prisma.JsonValue | null) {
    const record = asRecord(payload);
    const keys =
      entity === 'stockDeduction'
        ? stockDeductionPreviewKeys
        : entity === 'cashSession'
          ? cashSessionPreviewKeys
          : genericPreviewKeys;
    return pickPreview(record, keys);
  }

  sanitizePayload(value: unknown): Prisma.InputJsonValue {
    return sanitizeValue(value) as Prisma.InputJsonValue;
  }

  private async classifyStockDeduction(
    companyId: string,
    payload: Record<string, unknown>,
  ): Promise<SyncDiagnosticResult> {
    const productId = firstValue(payload, ['productId', 'productServerId']);
    const variantId = firstValue(payload, [
      'productVariantId',
      'productVariantServerId',
      'variantId',
    ]);
    const productUuid = uuidString(productId);
    const variantUuid = uuidString(variantId);

    if (isLocalIdentity(productId) || isLocalIdentity(variantId)) {
      return diagnostic({
        classification: 'IRRECOVERABLE_LEGACY_EVENT',
        recommendedAction: 'ARCHIVE_LEGACY',
        message:
          'Evento antigo sem identificacao remota segura. Nao e recomendado reprocessar automaticamente. Revise estoque manualmente ou arquive como evento legado de teste.',
        blockers: [
          'O payload usa id local em campo remoto.',
          'Nao existe garantia de que o produto local corresponde ao produto remoto correto.',
        ],
        risks: ['Baixa automatica poderia atingir o produto errado.'],
      });
    }

    if (variantUuid != null) {
      const variant = await prisma.productVariant.findFirst({
        where: {
          id: variantUuid,
          product: {
            companyId,
            deletedAt: null,
          },
        },
        select: { id: true },
      });

      if (variant == null) {
        return diagnostic({
          classification: 'NEEDS_PRODUCT_MAPPING',
          recommendedAction: 'REVIEW_PRODUCT_MAPPING',
          message:
            'A variante remota indicada nao foi encontrada nesta empresa.',
          blockers: ['Confirme o mapeamento do produto/variante antes de reprocessar.'],
        });
      }

      return diagnostic({
        classification: 'REPROCESSABLE',
        recommendedAction: 'REPROCESS',
        message: 'Baixa de estoque possui variante remota segura.',
        risks: ['Reprocessar pode alterar o estoque remoto se ainda nao foi materializado.'],
      });
    }

    if (productUuid != null) {
      const product = await prisma.product.findFirst({
        where: {
          id: productUuid,
          companyId,
          deletedAt: null,
        },
        select: {
          id: true,
          _count: {
            select: {
              variants: {
                where: { isActive: true },
              },
            },
          },
        },
      });

      if (product == null) {
        return diagnostic({
          classification: 'NEEDS_PRODUCT_MAPPING',
          recommendedAction: 'REVIEW_PRODUCT_MAPPING',
          message: 'O produto remoto indicado nao foi encontrado nesta empresa.',
          blockers: ['Confirme o mapeamento do produto antes de reprocessar.'],
        });
      }

      if (product._count.variants > 0) {
        return diagnostic({
          classification: 'NEEDS_PRODUCT_MAPPING',
          recommendedAction: 'REVIEW_PRODUCT_MAPPING',
          message:
            'O produto possui variantes ativas e o evento nao informa variante remota.',
          blockers: ['Informe ou recupere a variante remota antes de qualquer baixa.'],
          risks: ['Baixar no nivel do produto poderia distorcer estoque por variante.'],
        });
      }

      return diagnostic({
        classification: 'REPROCESSABLE',
        recommendedAction: 'REPROCESS',
        message: 'Produto remoto sem variantes ativas permite baixa segura.',
        risks: ['Reprocessar pode alterar o estoque remoto se ainda nao foi materializado.'],
      });
    }

    return diagnostic({
      classification: 'MANUAL_STOCK_REVIEW',
      recommendedAction: 'MANUAL_STOCK_ADJUSTMENT',
      message:
        'Baixa de estoque sem identidade remota. Revise o estoque manualmente com auditoria.',
      blockers: ['Nao ha productId/productVariantId remoto seguro no payload.'],
      risks: ['Reprocessamento automatico poderia afetar item incorreto.'],
    });
  }

  private classifyCashSessionUpdate(
    payload: Record<string, unknown>,
  ): SyncDiagnosticResult {
    const uuid = textValue(payload.uuid);
    const status = textValue(payload.status ?? payload.state)?.toLowerCase();
    const openedAt = textValue(payload.openedAt ?? payload.createdAt);
    const normalizedStatus = normalizeCashStatus(status);

    if (
      uuid != null &&
      openedAt != null &&
      normalizedStatus === 'open'
    ) {
      return diagnostic({
        classification: 'REPROCESSABLE',
        recommendedAction: 'REPROCESS',
        message:
          'Atualizacao de sessao aberta tem uuid, status e abertura suficientes para upsert idempotente.',
        risks: ['Reprocessar pode atualizar saldos esperados da sessao de caixa.'],
      });
    }

    if (normalizedStatus == null) {
      return diagnostic({
        classification: 'UNKNOWN',
        recommendedAction: 'CONTACT_SUPPORT',
        message: 'Status de sessao de caixa nao reconhecido.',
        blockers: ['Status invalido para regra automatica.'],
      });
    }

    return diagnostic({
      classification: 'UNKNOWN',
      recommendedAction: 'CONTACT_SUPPORT',
      message:
        'Payload de sessao de caixa nao possui dados minimos para upsert seguro.',
      blockers: ['uuid, status open/aberto e openedAt sao obrigatorios para reprocessar.'],
    });
  }
}

function diagnostic(input: {
  classification: SyncDiagnosticClassification;
  recommendedAction: SyncDiagnosticRecommendedAction;
  message: string;
  risks?: string[];
  blockers?: string[];
}): SyncDiagnosticResult {
  return {
    classification: input.classification,
    recommendedAction: input.recommendedAction,
    canReprocess: input.classification === 'REPROCESSABLE',
    canArchive: [
      'IRRECOVERABLE_LEGACY_EVENT',
      'MANUAL_STOCK_REVIEW',
      'UNKNOWN',
    ].includes(input.classification),
    canCreateManualStockAdjustment:
      input.classification === 'MANUAL_STOCK_REVIEW',
    message: input.message,
    risks: input.risks ?? [],
    blockers: input.blockers ?? [],
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

function pickPreview(record: Record<string, unknown>, keys: string[]) {
  const preview: Record<string, unknown> = {};
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(record, key)) {
      preview[key] = sanitizeValue(record[key]);
    }
  }
  return preview;
}

function sanitizeValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sanitizeValue);
  }
  if (typeof value === 'string') {
    return containsSensitiveText(value) ? '[redacted]' : value;
  }
  if (value == null || typeof value !== 'object') {
    return value;
  }

  const sanitized: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    sanitized[key] = isSensitiveKey(key) ? '[redacted]' : sanitizeValue(nested);
  }
  return sanitized;
}

function containsSensitiveValue(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some(containsSensitiveValue);
  }
  if (typeof value === 'string') {
    return containsSensitiveText(value);
  }
  if (value == null || typeof value !== 'object') {
    return false;
  }
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    if (isSensitiveKey(key) || containsSensitiveValue(nested)) {
      return true;
    }
  }
  return false;
}

function isSensitiveKey(key: string) {
  const normalized = key.replace(/[^a-z0-9]/gi, '').toLowerCase();
  return sensitiveKeyFragments.some((fragment) =>
    normalized.includes(fragment.replace(/[^a-z0-9]/gi, '').toLowerCase()),
  );
}

function containsSensitiveText(value: string) {
  const normalized = value.trim().toLowerCase();
  return [
    'bearer ',
    'authorization:',
    'access_token=',
    'refresh_token=',
    'api_key=',
    'apikey=',
    'token=',
    'password=',
    'secret=',
    'client_secret=',
  ].some((pattern) => normalized.includes(pattern));
}

function firstValue(record: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = record[key];
    if (value != null) {
      return value;
    }
  }
  return null;
}

function uuidString(value: unknown) {
  const text = textValue(value);
  return text != null && uuidPattern.test(text) ? text : null;
}

function textValue(value: unknown) {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }
  return null;
}

function isLocalIdentity(value: unknown) {
  if (typeof value === 'number') {
    return Number.isFinite(value) && Number.isInteger(value);
  }
  if (typeof value !== 'string') {
    return false;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || uuidPattern.test(trimmed)) {
    return false;
  }
  return /^\d+$/.test(trimmed);
}

function normalizeCashStatus(value: string | null | undefined) {
  if (value == null || value.trim().length === 0) {
    return 'open';
  }
  const normalized = value.trim().toLowerCase();
  if (['open', 'opened', 'active', 'aberto', 'aberta'].includes(normalized)) {
    return 'open';
  }
  if (
    ['closed', 'finished', 'finalized', 'fechado', 'fechada'].includes(
      normalized,
    )
  ) {
    return 'closed';
  }
  return null;
}
