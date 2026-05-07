import { LicenseStatus } from '@prisma/client';

import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { AppContext } from '../app/app-context.types';
import {
  getPlanEntitlements,
  normalizePlan,
  type PlanKey,
} from '../plans/plan-catalog.service';
import type { BillingSubscribeInput } from './billing.schemas';
import type {
  AdminBillingStatusDto,
  BillingStatusDto,
  MercadoPagoSubscriptionDetails,
  PaidPlanKey,
  PublicBillingPlan,
  SubscribeResultDto,
} from './billing.types';
import { MercadoPagoService } from './mercado-pago.service';

const BILLING_PROVIDER = 'mercadopago';
const MONTHLY = 'monthly';
const CHECKOUT_TTL_MS = 30 * 60 * 1000;

type ApplyProviderResult = {
  action:
    | 'activated'
    | 'downgraded'
    | 'unchanged'
    | 'ignored_unknown'
    | 'ignored_missing_session';
  providerStatus: string;
  companyId: string | null;
  plan: PlanKey | null;
};

export class BillingService {
  constructor(private readonly mercadoPagoService = new MercadoPagoService()) {}

  listPlans(): PublicBillingPlan[] {
    return [
      {
        key: 'FREE',
        name: 'Free',
        priceCents: 0,
        currency: 'BRL',
        billingCycle: 'free',
        description: 'Comece vendendo no PDV com um dispositivo.',
        featuresSummary: [
          'PDV, caixa e produtos',
          'Clientes basicos e fiado no checkout',
          'Relatorio diario simples',
        ],
      },
      {
        key: 'BASIC',
        name: 'Basico',
        priceCents: env.BILLING_BASIC_PRICE_CENTS,
        currency: 'BRL',
        billingCycle: 'monthly',
        description: 'Gestao individual completa para operar a loja.',
        featuresSummary: [
          'Fiado completo',
          'Insumos, custos, fornecedores e compras',
          'Estoque avancado e relatorios basicos',
        ],
      },
      {
        key: 'PRO',
        name: 'Pro',
        priceCents: env.BILLING_PRO_PRICE_CENTS,
        currency: 'BRL',
        billingCycle: 'monthly',
        description: 'Equipe, dispositivos e relatorios avancados.',
        featuresSummary: [
          'Multi-dispositivo',
          'Funcionarios, permissoes e comissoes',
          'Relatorios avancados',
        ],
      },
    ];
  }

  async getStatusForContext(context: AppContext): Promise<BillingStatusDto> {
    return this.getStatusForCompany({
      companyId: context.company.id,
      canManageBilling: context.membership.role === 'OWNER',
      includeProviderSubscriptionId: false,
    });
  }

  async getAdminStatus(companyId: string): Promise<AdminBillingStatusDto> {
    return this.getStatusForCompany({
      companyId,
      canManageBilling: true,
      includeProviderSubscriptionId: true,
    }) as Promise<AdminBillingStatusDto>;
  }

  async subscribe(
    context: AppContext,
    input: BillingSubscribeInput,
  ): Promise<SubscribeResultDto> {
    this.assertOwner(context);
    const plan = normalizePlan(input.plan) as PaidPlanKey;

    const currentPlan = normalizePlan(context.license.plan);
    if (
      currentPlan === plan &&
      context.license.status === LicenseStatus.ACTIVE
    ) {
      return {
        checkoutUrl: null,
        provider: null,
        plan,
        checkoutSessionId: null,
        expiresAt: null,
        status: await this.getStatusForContext(context),
      };
    }

    const expiresAt = new Date(Date.now() + CHECKOUT_TTL_MS);
    const checkoutSession = await prisma.billingCheckoutSession.create({
      data: {
        companyId: context.company.id,
        userId: context.user.id,
        plan,
        billingCycle: input.billingCycle ?? MONTHLY,
        status: 'PENDING',
        provider: BILLING_PROVIDER,
        expiresAt,
      },
    });

    try {
      const priceCents = this.priceCentsFor(plan);
      const preapproval = await this.mercadoPagoService.createPreapproval({
        plan,
        priceCents,
        checkoutSessionId: checkoutSession.id,
        payerEmail: context.user.email,
        backUrl: buildAppBackUrl(),
        notificationUrl: buildWebhookUrl(),
      });
      const checkoutUrl = preapproval.initPoint ?? preapproval.sandboxInitPoint;
      if (checkoutUrl == null) {
        throw new AppError(
          'Mercado Pago nao retornou uma URL de checkout.',
          502,
          'MERCADO_PAGO_CHECKOUT_URL_MISSING',
        );
      }

      const updated = await prisma.billingCheckoutSession.update({
        where: { id: checkoutSession.id },
        data: {
          providerReference: preapproval.id,
          checkoutUrl: preapproval.initPoint,
          sandboxCheckoutUrl: preapproval.sandboxInitPoint,
        },
      });

      return {
        checkoutUrl,
        provider: BILLING_PROVIDER,
        plan,
        checkoutSessionId: updated.id,
        expiresAt: updated.expiresAt?.toISOString() ?? null,
      };
    } catch (error) {
      await prisma.billingCheckoutSession.update({
        where: { id: checkoutSession.id },
        data: { status: 'CANCELLED' },
      });
      throw error;
    }
  }

  async refresh(context: AppContext): Promise<BillingStatusDto> {
    this.assertOwner(context);
    await this.refreshCompanyFromProvider(context.company.id);
    return this.getStatusForContext(context);
  }

  async refreshCompanyFromProvider(
    companyId: string,
  ): Promise<AdminBillingStatusDto> {
    const providerReference = await this.findRefreshProviderReference(
      companyId,
    );
    if (providerReference == null) {
      return this.getAdminStatus(companyId);
    }

    const details = await this.mercadoPagoService.getSubscription(
      providerReference,
    );
    await this.applyMercadoPagoDetails(details, {
      fallbackCompanyId: companyId,
    });
    return this.getAdminStatus(companyId);
  }

  async applyMercadoPagoDetails(
    details: MercadoPagoSubscriptionDetails,
    options: { fallbackCompanyId?: string } = {},
  ): Promise<ApplyProviderResult> {
    const providerStatus = normalizeProviderStatus(details.status);
    const session = await this.findCheckoutSession(details);
    const companyId = session?.companyId ?? options.fallbackCompanyId ?? null;
    const plan =
      session == null
        ? await this.resolveCurrentPaidPlan(companyId)
        : normalizePlan(session.plan);

    if (companyId == null || plan == null) {
      return {
        action: 'ignored_missing_session',
        providerStatus,
        companyId,
        plan,
      };
    }

    if (isPaidActivationStatus(providerStatus)) {
      if (plan === 'FREE') {
        return {
          action: 'ignored_unknown',
          providerStatus,
          companyId,
          plan,
        };
      }

      await prisma.$transaction([
        ...(session == null
          ? []
          : [
              prisma.billingCheckoutSession.update({
                where: { id: session.id },
                data: {
                  status: 'COMPLETED',
                  providerReference: details.providerReference,
                },
              }),
            ]),
        prisma.license.upsert({
          where: { companyId },
          create: {
            companyId,
            plan,
            status: LicenseStatus.ACTIVE,
            startsAt: new Date(),
            expiresAt: null,
            syncEnabled: true,
            billingProvider: BILLING_PROVIDER,
            providerSubscriptionId: details.providerReference,
            currentPeriodStart: details.currentPeriodStart,
            currentPeriodEnd: details.currentPeriodEnd,
            nextPaymentDate: details.nextPaymentDate,
            billingSubscriptionStatus: providerStatus,
          },
          update: {
            plan,
            status: LicenseStatus.ACTIVE,
            expiresAt: null,
            syncEnabled: true,
            billingProvider: BILLING_PROVIDER,
            providerSubscriptionId: details.providerReference,
            currentPeriodStart: details.currentPeriodStart,
            currentPeriodEnd: details.currentPeriodEnd,
            nextPaymentDate: details.nextPaymentDate,
            cancelAtPeriodEnd: false,
            cancelRequestedAt: null,
            canceledAt: null,
            pendingPlan: null,
            pendingPlanRequestedAt: null,
            billingSubscriptionStatus: providerStatus,
          },
        }),
      ]);

      return { action: 'activated', providerStatus, companyId, plan };
    }

    if (isDowngradeStatus(providerStatus)) {
      await prisma.$transaction([
        ...(session == null
          ? []
          : [
              prisma.billingCheckoutSession.update({
                where: { id: session.id },
                data: {
                  status: providerStatus === 'expired' ? 'EXPIRED' : 'CANCELLED',
                  providerReference: details.providerReference,
                },
              }),
            ]),
        prisma.license.upsert({
          where: { companyId },
          create: {
            companyId,
            plan: 'FREE',
            status: LicenseStatus.ACTIVE,
            startsAt: new Date(),
            expiresAt: null,
            syncEnabled: true,
            billingProvider: null,
            providerSubscriptionId: null,
            currentPeriodStart: null,
            currentPeriodEnd: null,
            nextPaymentDate: null,
            canceledAt: new Date(),
            billingSubscriptionStatus: providerStatus,
          },
          update: {
            plan: 'FREE',
            status: LicenseStatus.ACTIVE,
            expiresAt: null,
            syncEnabled: true,
            billingProvider: null,
            providerSubscriptionId: null,
            currentPeriodStart: null,
            currentPeriodEnd: null,
            nextPaymentDate: null,
            cancelAtPeriodEnd: false,
            cancelRequestedAt: null,
            canceledAt: new Date(),
            pendingPlan: null,
            pendingPlanRequestedAt: null,
            billingSubscriptionStatus: providerStatus,
          },
        }),
      ]);

      return { action: 'downgraded', providerStatus, companyId, plan: 'FREE' };
    }

    if (isNeutralStatus(providerStatus)) {
      if (session != null) {
        await prisma.billingCheckoutSession.update({
          where: { id: session.id },
          data: {
            status: providerStatus === 'rejected' ? 'REJECTED' : 'PENDING',
            providerReference: details.providerReference,
          },
        });
      }
      return { action: 'unchanged', providerStatus, companyId, plan };
    }

    return { action: 'ignored_unknown', providerStatus, companyId, plan };
  }

  private async getStatusForCompany(input: {
    companyId: string;
    canManageBilling: boolean;
    includeProviderSubscriptionId: boolean;
  }): Promise<BillingStatusDto | AdminBillingStatusDto> {
    const license = await prisma.license.findUnique({
      where: { companyId: input.companyId },
    });
    const entitlements = getPlanEntitlements(license?.plan ?? 'FREE');
    const providerSubscriptionId = license?.providerSubscriptionId ?? null;
    const base: BillingStatusDto = {
      companyId: input.companyId,
      plan: entitlements.plan,
      status: (license?.status ?? LicenseStatus.ACTIVE).toString(),
      currentPeriodStart: license?.currentPeriodStart?.toISOString() ?? null,
      currentPeriodEnd: license?.currentPeriodEnd?.toISOString() ?? null,
      expiresAt: license?.expiresAt?.toISOString() ?? null,
      provider:
        license?.billingProvider === BILLING_PROVIDER ? BILLING_PROVIDER : null,
      hasProviderSubscription: providerSubscriptionId != null,
      maskedProviderSubscriptionId:
        maskProviderSubscriptionId(providerSubscriptionId),
      canManageBilling: input.canManageBilling,
      nextPaymentDate: license?.nextPaymentDate?.toISOString() ?? null,
      features: entitlements.features,
      limits: entitlements.limits,
    };

    if (!input.includeProviderSubscriptionId) {
      return base;
    }

    return {
      ...base,
      providerSubscriptionId,
    };
  }

  private assertOwner(context: AppContext) {
    if (context.membership.role !== 'OWNER') {
      throw new AppError(
        'Apenas o owner da empresa pode gerenciar assinatura.',
        403,
        'BILLING_OWNER_REQUIRED',
      );
    }
  }

  private priceCentsFor(plan: PaidPlanKey) {
    return plan === 'PRO'
      ? env.BILLING_PRO_PRICE_CENTS
      : env.BILLING_BASIC_PRICE_CENTS;
  }

  private async findRefreshProviderReference(companyId: string) {
    const license = await prisma.license.findUnique({
      where: { companyId },
      select: { providerSubscriptionId: true },
    });
    if (license?.providerSubscriptionId != null) {
      return license.providerSubscriptionId;
    }

    const session = await prisma.billingCheckoutSession.findFirst({
      where: {
        companyId,
        provider: BILLING_PROVIDER,
        providerReference: { not: null },
        status: { in: ['PENDING', 'COMPLETED'] },
      },
      orderBy: { updatedAt: 'desc' },
    });
    return session?.providerReference ?? null;
  }

  private async findCheckoutSession(details: MercadoPagoSubscriptionDetails) {
    if (details.externalReference != null) {
      const session = await prisma.billingCheckoutSession.findUnique({
        where: { id: details.externalReference },
      });
      if (session != null) {
        return session;
      }
    }

    return prisma.billingCheckoutSession.findFirst({
      where: {
        provider: BILLING_PROVIDER,
        providerReference: details.providerReference,
      },
      orderBy: { updatedAt: 'desc' },
    });
  }

  private async resolveCurrentPaidPlan(companyId: string | null) {
    if (companyId == null) {
      return null;
    }
    const license = await prisma.license.findUnique({
      where: { companyId },
      select: { plan: true },
    });
    const plan = normalizePlan(license?.plan);
    return plan === 'FREE' ? null : plan;
  }
}

function normalizeProviderStatus(status: string | null) {
  const normalized = status?.trim().toLowerCase();
  return normalized == null || normalized.length === 0 ? 'unknown' : normalized;
}

function isPaidActivationStatus(status: string) {
  return status === 'active' || status === 'authorized' || status === 'approved';
}

function isNeutralStatus(status: string) {
  return (
    status === 'pending' || status === 'in_process' || status === 'rejected'
  );
}

function isDowngradeStatus(status: string) {
  return status === 'cancelled' || status === 'canceled' || status === 'expired';
}

function buildAppBackUrl() {
  const baseUrl = env.APP_PUBLIC_URL ?? 'http://localhost:3000';
  return `${baseUrl.replace(/\/+$/, '')}/conta/assinatura`;
}

function buildWebhookUrl() {
  if (env.API_PUBLIC_URL == null) {
    return null;
  }
  return `${env.API_PUBLIC_URL.replace(/\/+$/, '')}/api/webhooks/mercadopago`;
}

function maskProviderSubscriptionId(value: string | null) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length <= 8) {
    return '****';
  }
  return `${trimmed.slice(0, 4)}...${trimmed.slice(-4)}`;
}
