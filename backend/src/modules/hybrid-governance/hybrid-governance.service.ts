import {
  HybridCustomerMasterMode,
  HybridPricePolicyMode,
  HybridPromotionMode,
  type HybridGovernanceProfile,
} from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type {
  HybridGovernanceProfileUpdateInput,
  HybridGovernanceQueryInput,
} from './hybrid-governance.schemas';

const REMOTE_IMAGE_GOVERNANCE_AVAILABLE = false;
const LOCAL_STOCK_TELEMETRY_AVAILABLE = false;
const FUTURE_PROMOTION_ENGINE_READY = false;

type GovernanceAlert = {
  code: string;
  domain: 'catalog' | 'pricing' | 'stock' | 'customers' | 'platform';
  severity: 'info' | 'warning' | 'critical';
  title: string;
  summary: string;
  count: number;
};

export class HybridGovernanceService {
  async getOverview(query: HybridGovernanceQueryInput) {
    const profile = await this.ensureProfile(query.companyId);

    const [
      company,
      activeCategories,
      products,
      customers,
      crmEnrichedCustomersCount,
    ] = await prisma.$transaction([
      prisma.company.findUnique({
        where: { id: query.companyId },
        select: {
          id: true,
          name: true,
          slug: true,
        },
      }),
      prisma.category.count({
        where: {
          companyId: query.companyId,
          deletedAt: null,
          isActive: true,
        },
      }),
      prisma.product.findMany({
        where: {
          companyId: query.companyId,
          deletedAt: null,
        },
        select: {
          id: true,
          categoryId: true,
          name: true,
          catalogType: true,
          costPriceCents: true,
          manualCostCents: true,
          salePriceCents: true,
          stockMil: true,
          isActive: true,
          variants: {
            select: {
              id: true,
              sku: true,
              stockMil: true,
              isActive: true,
            },
          },
        },
      }),
      prisma.customer.findMany({
        where: {
          companyId: query.companyId,
          deletedAt: null,
        },
        select: {
          id: true,
          name: true,
          phone: true,
          isActive: true,
        },
      }),
      prisma.customer.count({
        where: {
          companyId: query.companyId,
          deletedAt: null,
          OR: [
            { crmNotes: { some: {} } },
            { crmTasks: { some: {} } },
            { crmTagAssignments: { some: {} } },
          ],
        },
      }),
    ]);

    if (!company) {
      throw new AppError(
        'Empresa nao encontrada para a governanca hibrida.',
        404,
        'HYBRID_GOVERNANCE_COMPANY_NOT_FOUND',
      );
    }

    const activeProducts = products.filter((product) => product.isActive);
    const variantProducts = activeProducts.filter(
      (product) => product.catalogType === 'variant' || product.variants.length > 0,
    );
    const productsWithoutCategory = activeProducts.filter(
      (product) => product.categoryId == null,
    ).length;
    const productsWithBlankVariantSku = variantProducts.filter((product) =>
      product.variants.some((variant) => variant.sku.trim().length == 0),
    ).length;
    const marginBasisPoints = activeProducts
      .map((product) => calculateMarginBasisPoints(product.salePriceCents, resolveProductCost(product)))
      .filter((value): value is number => value != null);
    const productsBelowMarginPolicy = activeProducts.filter((product) => {
      const margin = calculateMarginBasisPoints(
        product.salePriceCents,
        resolveProductCost(product),
      );
      return margin == null || margin < profile.minMarginBasisPoints;
    }).length;
    const totalCloudStockMil = activeProducts.reduce(
      (sum, product) => sum + product.stockMil,
      0,
    );
    const productsWithoutCloudStock = activeProducts.filter(
      (product) => product.stockMil <= 0,
    ).length;
    const variantAggregationMismatchCount = variantProducts.filter((product) => {
      const activeVariantStock = product.variants.reduce((sum, variant) => {
        if (!variant.isActive) {
          return sum;
        }
        return sum + variant.stockMil;
      }, 0);
      return activeVariantStock != product.stockMil;
    }).length;

    const activeCustomers = customers.filter((customer) => customer.isActive);
    const customersWithoutPhone = activeCustomers.filter((customer) => {
      return normalizePhone(customer.phone) == null;
    }).length;
    const duplicatePhoneConflictCount = countDuplicateMembers(
      activeCustomers.map((customer) => normalizePhone(customer.phone)),
    );
    const duplicateNameConflictCount = countDuplicateMembers(
      activeCustomers.map((customer) => normalizeLabel(customer.name)),
    );

    const alerts = this.buildAlerts({
      profile,
      productsWithoutCategory,
      productsWithBlankVariantSku,
      productsBelowMarginPolicy,
      variantAggregationMismatchCount,
      duplicatePhoneConflictCount,
      duplicateNameConflictCount,
    });

    return {
      company,
      profile: this.toProfileDto(profile),
      capabilities: {
        remoteImageMirrorAvailable: REMOTE_IMAGE_GOVERNANCE_AVAILABLE,
        localStockTelemetryAvailable: LOCAL_STOCK_TELEMETRY_AVAILABLE,
        futurePromotionEngineReady: FUTURE_PROMOTION_ENGINE_READY,
      },
      truthRules: [
        {
          domain: 'catalog',
          operationalSource:
            'SQLite local no app Tatuzin continua sendo a fonte operacional do catalogo que a venda usa.',
          cloudSource:
            'O backend consolida espelho remoto, politica de catalogo, status governado e alertas administrativos por empresa.',
          conflictPolicy:
            'Drift de categoria, variante, preco ou status gera alerta administrativo; a venda local segue com o catalogo conhecido.',
          offlineBehavior:
            'Falta de sincronizacao nao bloqueia leitura do catalogo nem atendimento no PDV.',
        },
        {
          domain: 'stock',
          operationalSource:
            'O estoque operacional conhecido continua no app local e pode seguir trabalhando offline.',
          cloudSource:
            'O backend enxerga apenas o estoque consolidado que ja chegou pelo espelho remoto por empresa.',
          conflictPolicy:
            'Divergencia entre agregacao cloud e variantes gera alerta; reconciliacao fina com snapshot local fica para fase futura.',
          offlineBehavior:
            'Ajustes e venda local nao esperam confirmacao do cloud para acontecer.',
        },
        {
          domain: 'customers',
          operationalSource:
            'O app preserva snapshot local leve para consulta, fiado e contexto util a venda.',
          cloudSource:
            'O customer master oficial e gerido no backend com CRM, politica de conflito e leitura administrativa.',
          conflictPolicy:
            'Conflitos de identidade ou contato sobem como alerta administrativo; anotacao operacional simples segue permitida conforme politica.',
          offlineBehavior:
            'Ausencia de sync nao impede consultar cliente local nem concluir venda.',
        },
      ],
      catalog: {
        totalProducts: products.length,
        activeProducts: activeProducts.length,
        activeCategories,
        variantProducts: variantProducts.length,
        productsWithoutCategory,
        productsWithBlankVariantSku,
        remoteImageMirrorAvailable: REMOTE_IMAGE_GOVERNANCE_AVAILABLE,
        imageGovernanceStatus: REMOTE_IMAGE_GOVERNANCE_AVAILABLE
          ? 'mirrored'
          : 'not_mirrored_to_cloud',
        governanceReadiness:
          activeProducts.length == 0
            ? 'not_seeded'
            : productsWithoutCategory > 0 || productsWithBlankVariantSku > 0
            ? 'needs_attention'
            : 'governed_ready',
      },
      pricing: {
        pricedProductsCount: activeProducts.filter((product) => product.salePriceCents > 0)
          .length,
        productsBelowMarginPolicy,
        lowestMarginBasisPoints:
          marginBasisPoints.length == 0
            ? null
            : marginBasisPoints.reduce((min, current) => current < min ? current : min),
        minMarginBasisPoints: profile.minMarginBasisPoints,
        maxOfflineDiscountBasisPoints: profile.maxOfflineDiscountBasisPoints,
        allowOfflinePriceOverride: profile.allowOfflinePriceOverride,
        policyMode: profile.pricePolicyMode.toLowerCase(),
      },
      stock: {
        totalCloudStockMil,
        productsWithoutCloudStock,
        variantAggregationMismatchCount,
        divergenceAlertThresholdMil: profile.stockDivergenceAlertThresholdMil,
        localTelemetryAvailable: LOCAL_STOCK_TELEMETRY_AVAILABLE,
        reconciliationReadiness: LOCAL_STOCK_TELEMETRY_AVAILABLE
          ? 'ready_for_snapshot_reconciliation'
          : 'requires_future_local_snapshot',
      },
      customers: {
        totalCustomers: customers.length,
        activeCustomers: activeCustomers.length,
        customersWithoutPhone,
        duplicatePhoneConflictCount,
        duplicateNameConflictCount,
        crmEnrichedCustomersCount,
        masterMode: profile.customerMasterMode.toLowerCase(),
      },
      alerts,
    };
  }

  async updateProfile(input: HybridGovernanceProfileUpdateInput) {
    await this.ensureProfile(input.companyId);

    const profile = await prisma.hybridGovernanceProfile.update({
      where: {
        companyId: input.companyId,
      },
      data: {
        ...(input.requireCategoryForGovernedCatalog == undefined
          ? {}
          : {
              requireCategoryForGovernedCatalog:
                input.requireCategoryForGovernedCatalog,
            }),
        ...(input.requireVariantSku == undefined
          ? {}
          : {
              requireVariantSku: input.requireVariantSku,
            }),
        ...(input.requireRemoteImageForGovernedCatalog == undefined
          ? {}
          : {
              requireRemoteImageForGovernedCatalog:
                input.requireRemoteImageForGovernedCatalog,
            }),
        ...(input.allowOfflinePriceOverride == undefined
          ? {}
          : {
              allowOfflinePriceOverride: input.allowOfflinePriceOverride,
            }),
        ...(input.allowLocalCatalogDeactivation == undefined
          ? {}
          : {
              allowLocalCatalogDeactivation: input.allowLocalCatalogDeactivation,
            }),
        ...(input.minMarginBasisPoints == undefined
          ? {}
          : {
              minMarginBasisPoints: input.minMarginBasisPoints,
            }),
        ...(input.maxOfflineDiscountBasisPoints == undefined
          ? {}
          : {
              maxOfflineDiscountBasisPoints:
                input.maxOfflineDiscountBasisPoints,
            }),
        ...(input.pricePolicyMode == undefined
          ? {}
          : {
              pricePolicyMode: mapPricePolicyMode(input.pricePolicyMode),
            }),
        ...(input.stockDivergenceAlertThresholdMil == undefined
          ? {}
          : {
              stockDivergenceAlertThresholdMil:
                input.stockDivergenceAlertThresholdMil,
            }),
        ...(input.allowOfflineStockAdjustments == undefined
          ? {}
          : {
              allowOfflineStockAdjustments: input.allowOfflineStockAdjustments,
            }),
        ...(input.requireStockReconciliationReview == undefined
          ? {}
          : {
              requireStockReconciliationReview:
                input.requireStockReconciliationReview,
            }),
        ...(input.customerMasterMode == undefined
          ? {}
          : {
              customerMasterMode: mapCustomerMasterMode(
                input.customerMasterMode,
              ),
            }),
        ...(input.allowOperationalCustomerNotes == undefined
          ? {}
          : {
              allowOperationalCustomerNotes: input.allowOperationalCustomerNotes,
            }),
        ...(input.allowOperationalCustomerAddressOverride == undefined
          ? {}
          : {
              allowOperationalCustomerAddressOverride:
                input.allowOperationalCustomerAddressOverride,
            }),
        ...(input.requireCustomerConflictReview == undefined
          ? {}
          : {
              requireCustomerConflictReview:
                input.requireCustomerConflictReview,
            }),
        ...(input.promotionMode == undefined
          ? {}
          : {
              promotionMode: mapPromotionMode(input.promotionMode),
            }),
        ...(input.allowPromotionStacking == undefined
          ? {}
          : {
              allowPromotionStacking: input.allowPromotionStacking,
            }),
        ...(input.requireGovernedPriceForPromotion == undefined
          ? {}
          : {
              requireGovernedPriceForPromotion:
                input.requireGovernedPriceForPromotion,
            }),
        ...(input.alertOnCatalogDrift == undefined
          ? {}
          : {
              alertOnCatalogDrift: input.alertOnCatalogDrift,
            }),
        ...(input.alertOnStockDivergence == undefined
          ? {}
          : {
              alertOnStockDivergence: input.alertOnStockDivergence,
            }),
        ...(input.alertOnCustomerConflict == undefined
          ? {}
          : {
              alertOnCustomerConflict: input.alertOnCustomerConflict,
            }),
      },
    });

    return {
      profile: this.toProfileDto(profile),
    };
  }

  private async ensureProfile(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true },
    });

    if (!company) {
      throw new AppError(
        'Empresa nao encontrada para a governanca hibrida.',
        404,
        'HYBRID_GOVERNANCE_COMPANY_NOT_FOUND',
      );
    }

    return prisma.hybridGovernanceProfile.upsert({
      where: {
        companyId,
      },
      update: {},
      create: {
        companyId,
      },
    });
  }

  private toProfileDto(profile: HybridGovernanceProfile) {
    return {
      requireCategoryForGovernedCatalog:
        profile.requireCategoryForGovernedCatalog,
      requireVariantSku: profile.requireVariantSku,
      requireRemoteImageForGovernedCatalog:
        profile.requireRemoteImageForGovernedCatalog,
      allowOfflinePriceOverride: profile.allowOfflinePriceOverride,
      allowLocalCatalogDeactivation: profile.allowLocalCatalogDeactivation,
      minMarginBasisPoints: profile.minMarginBasisPoints,
      maxOfflineDiscountBasisPoints: profile.maxOfflineDiscountBasisPoints,
      pricePolicyMode: profile.pricePolicyMode.toLowerCase(),
      stockDivergenceAlertThresholdMil:
        profile.stockDivergenceAlertThresholdMil,
      allowOfflineStockAdjustments: profile.allowOfflineStockAdjustments,
      requireStockReconciliationReview:
        profile.requireStockReconciliationReview,
      customerMasterMode: profile.customerMasterMode.toLowerCase(),
      allowOperationalCustomerNotes: profile.allowOperationalCustomerNotes,
      allowOperationalCustomerAddressOverride:
        profile.allowOperationalCustomerAddressOverride,
      requireCustomerConflictReview:
        profile.requireCustomerConflictReview,
      promotionMode: profile.promotionMode.toLowerCase(),
      allowPromotionStacking: profile.allowPromotionStacking,
      requireGovernedPriceForPromotion:
        profile.requireGovernedPriceForPromotion,
      alertOnCatalogDrift: profile.alertOnCatalogDrift,
      alertOnStockDivergence: profile.alertOnStockDivergence,
      alertOnCustomerConflict: profile.alertOnCustomerConflict,
      createdAt: profile.createdAt.toISOString(),
      updatedAt: profile.updatedAt.toISOString(),
    };
  }

  private buildAlerts(input: {
    profile: HybridGovernanceProfile;
    productsWithoutCategory: number;
    productsWithBlankVariantSku: number;
    productsBelowMarginPolicy: number;
    variantAggregationMismatchCount: number;
    duplicatePhoneConflictCount: number;
    duplicateNameConflictCount: number;
  }): GovernanceAlert[] {
    const alerts: GovernanceAlert[] = [];

    if (input.profile.alertOnCatalogDrift && input.productsWithoutCategory > 0) {
      alerts.push({
        code: 'catalog_missing_category',
        domain: 'catalog',
        severity: 'warning',
        title: 'Produtos ativos sem categoria remota governada',
        summary:
          'Existem produtos ativos no espelho remoto sem categoria, o que reduz a governanca administrativa do catalogo.',
        count: input.productsWithoutCategory,
      });
    }

    if (
      input.profile.alertOnCatalogDrift &&
      input.productsWithBlankVariantSku > 0
    ) {
      alerts.push({
        code: 'catalog_blank_variant_sku',
        domain: 'catalog',
        severity: 'warning',
        title: 'Variantes sem SKU governavel',
        summary:
          'Algumas variantes chegaram ao backend sem SKU utilizavel para governanca remota de catalogo.',
        count: input.productsWithBlankVariantSku,
      });
    }

    if (input.productsBelowMarginPolicy > 0) {
      alerts.push({
        code: 'pricing_below_policy_margin',
        domain: 'pricing',
        severity:
          input.profile.pricePolicyMode === HybridPricePolicyMode.GOVERNED
            ? 'critical'
            : 'warning',
        title: 'Produtos abaixo da politica minima de margem',
        summary:
          'A precificacao atual do espelho remoto indica itens abaixo da margem minima configurada para governanca.',
        count: input.productsBelowMarginPolicy,
      });
    }

    if (
      input.profile.alertOnStockDivergence &&
      input.variantAggregationMismatchCount > 0
    ) {
      alerts.push({
        code: 'stock_variant_aggregation_mismatch',
        domain: 'stock',
        severity: 'warning',
        title: 'Estoque cloud divergente das variantes',
        summary:
          'O estoque total consolidado do produto nao bate com a soma das variantes ativas espelhadas no backend.',
        count: input.variantAggregationMismatchCount,
      });
    }

    if (
      input.profile.alertOnCustomerConflict &&
      input.duplicatePhoneConflictCount + input.duplicateNameConflictCount > 0
    ) {
      alerts.push({
        code: 'customer_master_conflict',
        domain: 'customers',
        severity: input.profile.requireCustomerConflictReview
          ? 'critical'
          : 'warning',
        title: 'Clientes com potencial conflito de master',
        summary:
          'O backend encontrou duplicidade potencial de telefone ou nome no customer master por empresa.',
        count:
          input.duplicatePhoneConflictCount + input.duplicateNameConflictCount,
      });
    }

    alerts.push({
      code: 'platform_offline_sale_preserved',
      domain: 'platform',
      severity: 'info',
      title: 'Venda local continua offline-first',
      summary:
        'A governanca hibrida desta fase e apenas advisory/governada no cloud; a venda local nao depende do backend para acontecer.',
      count: 0,
    });

    alerts.push({
      code: 'platform_stock_snapshot_future_gap',
      domain: 'stock',
      severity: 'info',
      title: 'Reconciliacao fina de estoque depende de snapshot local futuro',
      summary:
        'O backend ainda nao recebe telemetria local de snapshot de estoque do app; hoje ele trabalha com o consolidado ja sincronizado.',
      count: 0,
    });

    alerts.push({
      code: 'catalog_remote_image_capability_gap',
      domain: 'catalog',
      severity: input.profile.requireRemoteImageForGovernedCatalog
        ? 'warning'
        : 'info',
      title: 'Governanca cloud de imagem ainda nao esta espelhada',
      summary:
        'As fotos do catalogo permanecem locais no app. O backend ainda nao valida imagem oficial por produto nesta fase.',
      count: 0,
    });

    alerts.push({
      code: 'promotion_preview_only',
      domain: 'platform',
      severity: 'info',
      title: 'Promocoes futuras seguem em modo de base tecnica',
      summary:
        'A governanca de promocoes foi preparada no perfil da empresa, mas a execucao cloud-first continua para a proxima fase.',
      count: 0,
    });

    return alerts;
  }
}

function normalizePhone(value: string | null) {
  if (value == null) {
    return null;
  }

  const digits = value.replace(/\D+/g, '');
  return digits.length == 0 ? null : digits;
}

function normalizeLabel(value: string) {
  return value.trim().toLowerCase().replace(/\s+/g, ' ');
}

function countDuplicateMembers(values: Array<string | null>) {
  const counts = new Map<string, number>();

  for (const value of values) {
    if (value == null) {
      continue;
    }
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }

  var duplicateMembers = 0;
  for (const count of counts.values()) {
    if (count > 1) {
      duplicateMembers += count;
    }
  }
  return duplicateMembers;
}

function resolveProductCost(product: {
  costPriceCents: number;
  manualCostCents: number;
}) {
  return Math.max(product.costPriceCents, product.manualCostCents);
}

function calculateMarginBasisPoints(
  salePriceCents: number,
  costCents: number,
) {
  if (salePriceCents <= 0) {
    return null;
  }

  return Math.round(((salePriceCents - costCents) / salePriceCents) * 10000);
}

function mapPricePolicyMode(value: 'advisory' | 'governed') {
  return value == 'governed'
    ? HybridPricePolicyMode.GOVERNED
    : HybridPricePolicyMode.ADVISORY;
}

function mapCustomerMasterMode(value: 'cloud_master' | 'hybrid_review') {
  return value == 'hybrid_review'
    ? HybridCustomerMasterMode.HYBRID_REVIEW
    : HybridCustomerMasterMode.CLOUD_MASTER;
}

function mapPromotionMode(value: 'manual_preview' | 'scheduled_review') {
  return value == 'scheduled_review'
    ? HybridPromotionMode.SCHEDULED_REVIEW
    : HybridPromotionMode.MANUAL_PREVIEW;
}
