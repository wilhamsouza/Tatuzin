import { LicenseStatus, Prisma, type BillingInvoice } from '@prisma/client';

import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type { AppContext } from '../app/app-context.types';
import {
  getPlanEntitlements,
  normalizePlan,
  type PlanKey,
} from '../plans/plan-catalog.service';
import type {
  BillingCancelInput,
  BillingChangePlanInput,
  BillingInvoicesQueryInput,
  BillingSubscribeInput,
} from './billing.schemas';
import { maskUrl, sanitizeForAdmin } from './billing-sanitizer';
import type {
  AdminBillingStatusDto,
  BillingActionResultDto,
  BillingInvoiceDto,
  BillingPaymentMethodDto,
  BillingStatusDto,
  MercadoPagoAuthorizedPaymentDetails,
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
    | 'ignored_missing_session'
    | 'invoice_reconciled';
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
    const refreshed = await this.refreshCompanyFromProvider(context.company.id);
    const status = await this.getStatusForContext(context);
    return mergeWarnings(status, refreshed.warnings);
  }

  async refreshCompanyFromProvider(
    companyId: string,
  ): Promise<AdminBillingStatusDto> {
    const warnings: string[] = [];
    const providerReference = await this.findRefreshProviderReference(
      companyId,
    );
    if (providerReference == null) {
      await this.applyScheduledTransitions(companyId);
      return this.getAdminStatus(companyId);
    }

    const details = await this.mercadoPagoService.getSubscription(
      providerReference,
    );
    await this.applyMercadoPagoDetails(details, {
      fallbackCompanyId: companyId,
    });
    await this.applyScheduledTransitions(companyId);
    try {
      const result = await this.reconcileInvoicesForSubscription(
        companyId,
        details.providerReference,
      );
      warnings.push(...result.warnings);
    } catch {
      warnings.push('INVOICE_RECONCILIATION_FAILED');
    }
    const status = await this.getAdminStatus(companyId);
    return mergeWarnings(status, warnings);
  }

  async listInvoices(context: AppContext, query: BillingInvoicesQueryInput) {
    this.assertOwner(context);
    const { skip, take } = toPaginationParams(query);
    const where = this.buildInvoiceWhere(context.company.id, query);
    const [items, total] = await prisma.$transaction([
      prisma.billingInvoice.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.billingInvoice.count({ where }),
    ]);

    return {
      items: items.map((invoice) => this.serializeInvoice(invoice)),
      page: query.page,
      pageSize: query.pageSize,
      total,
    };
  }

  async getInvoice(context: AppContext, invoiceId: string) {
    this.assertOwner(context);
    const invoice = await prisma.billingInvoice.findFirst({
      where: {
        id: invoiceId,
        companyId: context.company.id,
      },
    });
    if (invoice == null) {
      throw new AppError('Fatura nao encontrada.', 404, 'BILLING_INVOICE_NOT_FOUND');
    }
    return this.serializeInvoice(invoice);
  }

  async getPaymentMethod(
    context: AppContext,
  ): Promise<BillingPaymentMethodDto> {
    this.assertOwner(context);
    const license = await prisma.license.findUnique({
      where: { companyId: context.company.id },
      select: {
        providerSubscriptionId: true,
        nextPaymentDate: true,
        billingProvider: true,
      },
    });
    const providerSubscriptionId = license?.providerSubscriptionId ?? null;
    if (providerSubscriptionId == null) {
      return {
        provider: null,
        hasPaymentMethod: false,
        maskedProviderSubscriptionId: null,
      };
    }

    try {
      const details =
        await this.mercadoPagoService.getPreapproval(providerSubscriptionId);
      return {
        provider: BILLING_PROVIDER,
        hasPaymentMethod:
          details.paymentMethodId != null ||
          details.paymentMethodType != null ||
          details.lastFour != null,
        paymentMethodId: maskProviderSubscriptionId(details.paymentMethodId ?? null),
        paymentMethodType: details.paymentMethodType ?? null,
        lastFour: details.lastFour ?? null,
        status: details.status,
        nextPaymentDate:
          details.nextPaymentDate?.toISOString() ??
          license?.nextPaymentDate?.toISOString() ??
          null,
        maskedProviderSubscriptionId:
          maskProviderSubscriptionId(providerSubscriptionId),
      };
    } catch {
      return {
        provider: BILLING_PROVIDER,
        hasPaymentMethod: false,
        unavailable: true,
        message:
          'Nao foi possivel consultar o metodo de pagamento agora. Tente atualizar o status em instantes.',
        maskedProviderSubscriptionId:
          maskProviderSubscriptionId(providerSubscriptionId),
      };
    }
  }

  async cancelSubscription(
    context: AppContext,
    input: BillingCancelInput,
  ): Promise<BillingActionResultDto> {
    this.assertOwner(context);
    const license = await this.getRequiredLicense(context.company.id);
    const now = new Date();
    let providerCancelled = false;

    if (license.providerSubscriptionId != null) {
      try {
        const details = await this.mercadoPagoService.updatePreapproval(
          license.providerSubscriptionId,
          { status: 'cancelled' },
        );
        providerCancelled = true;
        await this.applyMercadoPagoDetails(details, {
          fallbackCompanyId: context.company.id,
        });
      } catch (error) {
        throw new AppError(
          'Nao foi possivel cancelar a assinatura no Mercado Pago agora.',
          error instanceof AppError ? error.statusCode : 502,
          error instanceof AppError ? error.code : 'MERCADO_PAGO_CANCEL_FAILED',
        );
      }
    }

    const current = await this.getRequiredLicense(context.company.id);
    const hasFuturePeriod =
      current.currentPeriodEnd != null && current.currentPeriodEnd > now;
    const shouldKeepAccess =
      input.effective === 'period_end' || hasFuturePeriod;

    if (shouldKeepAccess && hasFuturePeriod) {
      await prisma.license.update({
        where: { companyId: context.company.id },
        data: {
          cancelAtPeriodEnd: true,
          cancelRequestedAt: now,
          canceledAt: null,
          billingSubscriptionStatus:
            input.effective === 'now'
              ? 'CUSTOMER_CANCEL_NOW_PERIOD_ACTIVE'
              : 'CUSTOMER_CANCEL_PERIOD_END',
        },
      });
      return {
        status: await this.getStatusForContext(context),
        providerCancelled,
        effective: input.effective,
        message:
          'Cancelamento solicitado. O acesso pago sera mantido ate o fim do periodo vigente.',
      };
    }

    await this.downgradeToFree(context.company.id, {
      billingSubscriptionStatus: 'CUSTOMER_CANCELLED',
      canceledAt: now,
    });
    return {
      status: await this.getStatusForContext(context),
      providerCancelled,
      effective: input.effective,
      message:
        'Assinatura cancelada. Os dados foram preservados e os recursos pagos foram bloqueados.',
    };
  }

  async resumeSubscription(context: AppContext): Promise<BillingActionResultDto> {
    this.assertOwner(context);
    const license = await this.getRequiredLicense(context.company.id);
    if (license.providerSubscriptionId == null) {
      return {
        status: await this.getStatusForContext(context),
        requiresNewCheckout: true,
        message:
          'Nao ha assinatura vinculada para retomar. Inicie uma nova assinatura.',
      };
    }

    try {
      const details = await this.mercadoPagoService.updatePreapproval(
        license.providerSubscriptionId,
        { status: 'authorized' },
      );
      const providerStatus = normalizeProviderStatus(details.status);
      const currentPlan = normalizePlan(license.plan);
      if (isPaidActivationStatus(providerStatus) && currentPlan !== 'FREE') {
        await prisma.license.update({
          where: { companyId: context.company.id },
          data: {
            cancelAtPeriodEnd: false,
            cancelRequestedAt: null,
            canceledAt: null,
            billingSubscriptionStatus: providerStatus,
            nextPaymentDate: details.nextPaymentDate,
          },
        });
        return {
          status: await this.getStatusForContext(context),
          requiresNewCheckout: false,
          message: 'Assinatura retomada com seguranca.',
        };
      }

      return {
        status: await this.getStatusForContext(context),
        requiresNewCheckout: true,
        message:
          'Nao foi possivel retomar a assinatura existente. Inicie um novo checkout.',
      };
    } catch {
      return {
        status: await this.getStatusForContext(context),
        requiresNewCheckout: true,
        message:
          'Mercado Pago nao permitiu retomar esta assinatura. Inicie um novo checkout.',
      };
    }
  }

  async changePlan(
    context: AppContext,
    input: BillingChangePlanInput,
  ): Promise<BillingActionResultDto | SubscribeResultDto> {
    this.assertOwner(context);
    const requestedPlan = normalizePlan(input.plan);
    const license = await this.getRequiredLicense(context.company.id);
    const currentPlan = normalizePlan(license.plan);

    if (requestedPlan === currentPlan) {
      return {
        status: await this.getStatusForContext(context),
        pendingPlan: null,
        message: 'Este ja e o plano atual.',
      };
    }

    if (requestedPlan === 'FREE') {
      return this.cancelSubscription(context, { effective: 'period_end' });
    }

    if (currentPlan === 'FREE') {
      return this.subscribe(context, { plan: requestedPlan, billingCycle: MONTHLY });
    }

    if (currentPlan === 'BASIC' && requestedPlan === 'PRO') {
      await this.setPendingPlan(context.company.id, 'PRO');
      if (license.providerSubscriptionId != null) {
        try {
          await this.updateProviderPlanAmount(
            license.providerSubscriptionId,
            requestedPlan,
          );
          return {
            status: await this.getStatusForContext(context),
            pendingPlan: 'PRO',
            message:
              'Upgrade solicitado. O plano PRO sera liberado apos confirmacao do Mercado Pago.',
          };
        } catch {
          const checkout = await this.subscribe(context, {
            plan: 'PRO',
            billingCycle: MONTHLY,
          });
          return {
            ...checkout,
            status: await this.getStatusForContext(context),
          };
        }
      }
      const checkout = await this.subscribe(context, {
        plan: 'PRO',
        billingCycle: MONTHLY,
      });
      return {
        ...checkout,
        status: await this.getStatusForContext(context),
      };
    }

    if (currentPlan === 'PRO' && requestedPlan === 'BASIC') {
      await this.setPendingPlan(context.company.id, 'BASIC');
      if (license.providerSubscriptionId != null) {
        try {
          await this.updateProviderPlanAmount(
            license.providerSubscriptionId,
            requestedPlan,
          );
        } catch {
          // Keep the local pending downgrade; support can reconcile or force-plan if provider refuses.
        }
      }
      return {
        status: await this.getStatusForContext(context),
        pendingPlan: 'BASIC',
        message:
          'Downgrade para o plano Basico agendado para o fim do periodo vigente.',
      };
    }

    throw new AppError(
      'Troca de plano nao suportada nesta etapa.',
      422,
      'BILLING_PLAN_CHANGE_UNSUPPORTED',
    );
  }

  async reconcileInvoicesForCompany(companyId: string) {
    const providerReference = await this.findRefreshProviderReference(companyId);
    if (providerReference == null) {
      return { upserted: 0, skipped: 0, warnings: ['NO_PROVIDER_SUBSCRIPTION'] };
    }
    return this.reconcileInvoicesForSubscription(companyId, providerReference);
  }

  async reconcileInvoicesForSubscription(
    companyId: string,
    providerSubscriptionId: string,
  ) {
    const safeCompanyId = assertNonEmptyLocalId(companyId, 'companyId');
    const safeProviderSubscriptionId = assertNonEmptyLocalId(
      providerSubscriptionId,
      'providerSubscriptionId',
    );
    const isLinked = await this.isProviderReferenceLinkedToCompany(
      safeCompanyId,
      safeProviderSubscriptionId,
    );
    if (!isLinked) {
      return {
        upserted: 0,
        skipped: 0,
        warnings: ['PROVIDER_SUBSCRIPTION_NOT_LINKED_TO_COMPANY'],
      };
    }

    const authorizedPayments =
      await this.mercadoPagoService.searchAuthorizedPaymentsByPreapproval(
        safeProviderSubscriptionId,
        { limit: 50, offset: 0 },
      );
    const warnings: string[] = [];
    let upserted = 0;
    let skipped = 0;
    for (const authorizedPayment of authorizedPayments) {
      const result = await this.upsertBillingInvoiceFromAuthorizedPayment(
        companyId,
        authorizedPayment,
      );
      if (result.skipped) {
        skipped += 1;
      } else {
        upserted += 1;
      }
      warnings.push(...result.warnings);
    }
    return { upserted, skipped, warnings };
  }

  async upsertBillingInvoiceFromAuthorizedPayment(
    companyId: string,
    authorizedPayment: MercadoPagoAuthorizedPaymentDetails,
  ) {
    const safeCompanyId = assertNonEmptyLocalId(companyId, 'companyId');
    const providerInvoiceId = (
      authorizedPayment.providerInvoiceId ?? authorizedPayment.authorizedPaymentId
    )?.trim();
    if (providerInvoiceId == null || providerInvoiceId.length === 0) {
      return {
        skipped: true,
        invoice: null,
        warnings: ['BILLING_INVOICE_SKIPPED_MISSING_STABLE_ID'],
      };
    }

    const status = mapAuthorizedPaymentStatus(authorizedPayment.status);
    const plan = await this.inferInvoicePlan(
      safeCompanyId,
      authorizedPayment.providerSubscriptionId,
    );
    const payload = sanitizeForAdmin(
      authorizedPayment.rawPayload,
    ) as Prisma.InputJsonValue;
    const data = {
      companyId: safeCompanyId,
      provider: BILLING_PROVIDER,
      providerInvoiceId,
      providerSubscriptionId: authorizedPayment.providerSubscriptionId,
      plan,
      status,
      amountCents: authorizedPayment.amountCents,
      currency: authorizedPayment.currency ?? 'BRL',
      periodStart: authorizedPayment.periodStart,
      periodEnd: authorizedPayment.periodEnd,
      dueAt: authorizedPayment.dueAt,
      paidAt: authorizedPayment.paidAt,
      failedAt: authorizedPayment.failedAt,
      invoiceUrl: safePersistedInvoiceUrl(authorizedPayment.invoiceUrl),
      payload,
    };

    const existing = await prisma.billingInvoice.findFirst({
      where: {
        provider: BILLING_PROVIDER,
        providerInvoiceId,
      },
    });
    if (existing != null && existing.companyId !== safeCompanyId) {
      return {
        skipped: true,
        invoice: null,
        warnings: ['BILLING_INVOICE_PROVIDER_ID_CONFLICT'],
      };
    }
    const invoice =
      existing == null
        ? await prisma.billingInvoice.create({ data })
        : await prisma.billingInvoice.update({
            where: { id: existing.id },
            data,
          });

    return { skipped: false, invoice, warnings: [] as string[] };
  }

  async applyMercadoPagoDetails(
    details: MercadoPagoSubscriptionDetails,
    options: { fallbackCompanyId?: string } = {},
  ): Promise<ApplyProviderResult> {
    const providerStatus = normalizeProviderStatus(details.status);
    const session = await this.findCheckoutSession(details);
    const companyId =
      session?.companyId ??
      options.fallbackCompanyId ??
      (await this.resolveCompanyIdByProviderReference(details.providerReference));
    const currentLicense =
      companyId == null
        ? null
        : await prisma.license.findUnique({ where: { companyId } });
    const pendingPlan = normalizeNullablePlan(currentLicense?.pendingPlan);
    const sessionOrCurrentPlan =
      session == null
        ? await this.resolveCurrentPaidPlan(companyId)
        : normalizePlan(session.plan);
    const pendingUpgradeMatchesProviderAmount =
      pendingPlan === 'PRO' &&
      currentLicense != null &&
      normalizePlan(currentLicense.plan) === 'BASIC' &&
      details.amountCents === this.priceCentsFor('PRO');
    const plan = pendingUpgradeMatchesProviderAmount
      ? 'PRO'
      : sessionOrCurrentPlan;

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

      const shouldClearPendingPlan =
        pendingPlan == null ||
        session != null ||
        (pendingPlan === plan && pendingUpgradeMatchesProviderAmount);
      const shouldClearCancelState =
        session != null || currentLicense?.cancelAtPeriodEnd !== true;

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
            cancelAtPeriodEnd: shouldClearCancelState
              ? false
              : currentLicense?.cancelAtPeriodEnd ?? false,
            cancelRequestedAt: shouldClearCancelState
              ? null
              : currentLicense?.cancelRequestedAt ?? null,
            canceledAt: shouldClearCancelState
              ? null
              : currentLicense?.canceledAt ?? null,
            pendingPlan: shouldClearPendingPlan ? null : pendingPlan,
            pendingPlanRequestedAt: shouldClearPendingPlan
              ? null
              : currentLicense?.pendingPlanRequestedAt ?? null,
            billingSubscriptionStatus: providerStatus,
          },
        }),
      ]);

      return { action: 'activated', providerStatus, companyId, plan };
    }

    if (isDowngradeStatus(providerStatus)) {
      const effectivePeriodEnd =
        details.currentPeriodEnd ?? currentLicense?.currentPeriodEnd ?? null;
      if (effectivePeriodEnd != null && effectivePeriodEnd > new Date()) {
        await prisma.$transaction([
          ...(session == null
            ? []
            : [
                prisma.billingCheckoutSession.update({
                  where: { id: session.id },
                  data: {
                    status:
                      providerStatus === 'expired' ? 'EXPIRED' : 'CANCELLED',
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
              currentPeriodEnd: effectivePeriodEnd,
              nextPaymentDate: details.nextPaymentDate,
              cancelAtPeriodEnd: true,
              cancelRequestedAt: new Date(),
              billingSubscriptionStatus: providerStatus,
            },
            update: {
              expiresAt: null,
              syncEnabled: true,
              billingProvider: BILLING_PROVIDER,
              providerSubscriptionId: details.providerReference,
              currentPeriodStart:
                details.currentPeriodStart ??
                currentLicense?.currentPeriodStart ??
                null,
              currentPeriodEnd: effectivePeriodEnd,
              nextPaymentDate: details.nextPaymentDate,
              cancelAtPeriodEnd: true,
              cancelRequestedAt: new Date(),
              billingSubscriptionStatus: providerStatus,
            },
          }),
        ]);

        return { action: 'unchanged', providerStatus, companyId, plan };
      }

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

    if (isPausedStatus(providerStatus)) {
      await this.applyPausedSubscriptionStatus(companyId, details);
      if (session != null) {
        await prisma.billingCheckoutSession.update({
          where: { id: session.id },
          data: {
            status: 'PENDING',
            providerReference: details.providerReference,
          },
        });
      }
      return { action: 'unchanged', providerStatus, companyId, plan };
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

  async applyMercadoPagoAuthorizedPayment(
    details: MercadoPagoAuthorizedPaymentDetails,
  ): Promise<ApplyProviderResult> {
    const providerStatus = normalizeProviderStatus(details.status);
    const providerSubscriptionId = details.providerSubscriptionId?.trim();
    if (providerSubscriptionId == null || providerSubscriptionId.length === 0) {
      return {
        action: 'ignored_missing_session',
        providerStatus,
        companyId: null,
        plan: null,
      };
    }

    const target = await this.findCompanyForProviderSubscription(
      providerSubscriptionId,
    );
    if (target == null) {
      return {
        action: 'ignored_missing_session',
        providerStatus,
        companyId: null,
        plan: null,
      };
    }

    await this.upsertBillingInvoiceFromAuthorizedPayment(
      target.companyId,
      details,
    );

    const subscriptionDetails = await this.mercadoPagoService.getSubscription(
      providerSubscriptionId,
    );
    const subscriptionResult = await this.applyMercadoPagoDetails(
      subscriptionDetails,
      { fallbackCompanyId: target.companyId },
    );

    if (
      subscriptionResult.action === 'ignored_missing_session' ||
      subscriptionResult.action === 'ignored_unknown'
    ) {
      return {
        action: 'invoice_reconciled',
        providerStatus,
        companyId: target.companyId,
        plan: target.plan,
      };
    }

    return subscriptionResult;
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
      cancelAtPeriodEnd: license?.cancelAtPeriodEnd ?? false,
      cancelRequestedAt: license?.cancelRequestedAt?.toISOString() ?? null,
      canceledAt: license?.canceledAt?.toISOString() ?? null,
      pendingPlan: normalizeNullablePlan(license?.pendingPlan),
      pendingPlanRequestedAt:
        license?.pendingPlanRequestedAt?.toISOString() ?? null,
      billingSubscriptionStatus: license?.billingSubscriptionStatus ?? null,
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

  private buildInvoiceWhere(
    companyId: string,
    query: BillingInvoicesQueryInput,
  ): Prisma.BillingInvoiceWhereInput {
    return {
      companyId,
      ...(query.status == null ? {} : { status: query.status }),
      ...(query.from == null && query.to == null
        ? {}
        : {
            createdAt: {
              ...(query.from == null ? {} : { gte: query.from }),
              ...(query.to == null ? {} : { lte: query.to }),
            },
          }),
    };
  }

  private serializeInvoice(invoice: BillingInvoice): BillingInvoiceDto {
    return {
      id: invoice.id,
      provider: BILLING_PROVIDER,
      providerInvoiceId: invoice.providerInvoiceId,
      maskedProviderSubscriptionId: maskProviderSubscriptionId(
        invoice.providerSubscriptionId,
      ),
      plan: normalizeNullablePlan(invoice.plan),
      status: invoice.status,
      amountCents: invoice.amountCents,
      currency: invoice.currency,
      periodStart: invoice.periodStart?.toISOString() ?? null,
      periodEnd: invoice.periodEnd?.toISOString() ?? null,
      dueAt: invoice.dueAt?.toISOString() ?? null,
      paidAt: invoice.paidAt?.toISOString() ?? null,
      failedAt: invoice.failedAt?.toISOString() ?? null,
      invoiceUrl: safeInvoiceUrl(invoice.invoiceUrl),
      createdAt: invoice.createdAt.toISOString(),
      updatedAt: invoice.updatedAt.toISOString(),
    };
  }

  private async getRequiredLicense(companyId: string) {
    const license = await prisma.license.findUnique({ where: { companyId } });
    if (license == null) {
      throw new AppError('Licenca nao encontrada.', 404, 'LICENSE_NOT_FOUND');
    }
    return license;
  }

  private async setPendingPlan(companyId: string, pendingPlan: PaidPlanKey) {
    await prisma.license.update({
      where: { companyId },
      data: {
        pendingPlan,
        pendingPlanRequestedAt: new Date(),
      },
    });
  }

  private async updateProviderPlanAmount(
    providerSubscriptionId: string,
    plan: PaidPlanKey,
  ) {
    return this.mercadoPagoService.updatePreapproval(providerSubscriptionId, {
      reason: `Tatuzin ${plan}`,
      auto_recurring: {
        frequency: 1,
        frequency_type: 'months',
        transaction_amount: this.priceCentsFor(plan) / 100,
        currency_id: 'BRL',
      },
    });
  }

  private async inferInvoicePlan(
    companyId: string,
    providerSubscriptionId: string | null,
  ) {
    const license = await prisma.license.findUnique({
      where: { companyId },
      select: { plan: true },
    });
    const licensePlan = normalizePlan(license?.plan);
    if (licensePlan !== 'FREE') {
      return licensePlan;
    }

    if (providerSubscriptionId == null) {
      return null;
    }
    const session = await prisma.billingCheckoutSession.findFirst({
      where: {
        companyId,
        provider: BILLING_PROVIDER,
        providerReference: providerSubscriptionId,
      },
      orderBy: { updatedAt: 'desc' },
      select: { plan: true },
    });
    const sessionPlan = normalizePlan(session?.plan);
    return sessionPlan === 'FREE' ? null : sessionPlan;
  }

  private async isProviderReferenceLinkedToCompany(
    companyId: string,
    providerSubscriptionId: string,
  ) {
    const [license, session] = await prisma.$transaction([
      prisma.license.findFirst({
        where: {
          companyId,
          billingProvider: BILLING_PROVIDER,
          providerSubscriptionId,
        },
        select: { id: true },
      }),
      prisma.billingCheckoutSession.findFirst({
        where: {
          companyId,
          provider: BILLING_PROVIDER,
          providerReference: providerSubscriptionId,
        },
        select: { id: true },
      }),
    ]);
    return license != null || session != null;
  }

  private async applyScheduledTransitions(companyId: string) {
    const license = await prisma.license.findUnique({ where: { companyId } });
    if (license == null) {
      return;
    }
    const now = new Date();
    const periodEnded =
      license.currentPeriodEnd == null || license.currentPeriodEnd <= now;

    if (license.cancelAtPeriodEnd && periodEnded) {
      await this.downgradeToFree(companyId, {
        billingSubscriptionStatus:
          license.billingSubscriptionStatus ?? 'CANCELLED_PERIOD_ENDED',
        canceledAt: license.canceledAt ?? now,
      });
      return;
    }

    const currentPlan = normalizePlan(license.plan);
    const pendingPlan = normalizeNullablePlan(license.pendingPlan);
    if (
      currentPlan === 'PRO' &&
      pendingPlan === 'BASIC' &&
      periodEnded
    ) {
      await prisma.license.update({
        where: { companyId },
        data: {
          plan: 'BASIC',
          status: LicenseStatus.ACTIVE,
          expiresAt: null,
          syncEnabled: true,
          pendingPlan: null,
          pendingPlanRequestedAt: null,
          billingSubscriptionStatus: 'DOWNGRADE_EFFECTIVE',
        },
      });
    }
  }

  private async downgradeToFree(
    companyId: string,
    input: { billingSubscriptionStatus: string; canceledAt: Date },
  ) {
    await prisma.license.update({
      where: { companyId },
      data: {
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
        canceledAt: input.canceledAt,
        pendingPlan: null,
        pendingPlanRequestedAt: null,
        billingSubscriptionStatus: input.billingSubscriptionStatus,
      },
    });
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

  private async findCompanyForProviderSubscription(providerSubscriptionId: string) {
    const session = await prisma.billingCheckoutSession.findFirst({
      where: {
        provider: BILLING_PROVIDER,
        providerReference: providerSubscriptionId,
      },
      orderBy: { updatedAt: 'desc' },
      select: { companyId: true, plan: true },
    });
    if (session != null) {
      return {
        companyId: session.companyId,
        plan: normalizePlan(session.plan),
      };
    }

    const license = await prisma.license.findFirst({
      where: {
        billingProvider: BILLING_PROVIDER,
        providerSubscriptionId,
      },
      select: { companyId: true, plan: true },
    });
    if (license == null) {
      return null;
    }
    return {
      companyId: license.companyId,
      plan: normalizePlan(license.plan),
    };
  }

  private async applyPausedSubscriptionStatus(
    companyId: string,
    details: MercadoPagoSubscriptionDetails,
  ) {
    const license = await prisma.license.findUnique({
      where: { companyId },
      select: { currentPeriodEnd: true },
    });
    if (license == null) {
      return;
    }
    const currentPeriodEnd = details.currentPeriodEnd ?? license?.currentPeriodEnd ?? null;
    const hasFuturePeriod =
      currentPeriodEnd != null && currentPeriodEnd.getTime() > Date.now();

    await prisma.license.update({
      where: { companyId },
      data: {
        billingProvider: BILLING_PROVIDER,
        providerSubscriptionId: details.providerReference,
        ...(details.currentPeriodStart == null
          ? {}
          : { currentPeriodStart: details.currentPeriodStart }),
        ...(hasFuturePeriod ? { currentPeriodEnd } : {}),
        ...(details.nextPaymentDate == null
          ? {}
          : { nextPaymentDate: details.nextPaymentDate }),
        billingSubscriptionStatus: 'paused',
      },
    });
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

  private async resolveCompanyIdByProviderReference(
    providerReference: string | null | undefined,
  ) {
    if (providerReference == null || providerReference.trim().length === 0) {
      return null;
    }
    const license = await prisma.license.findFirst({
      where: {
        billingProvider: BILLING_PROVIDER,
        providerSubscriptionId: providerReference,
      },
      select: { companyId: true },
    });
    return license?.companyId ?? null;
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

function isPausedStatus(status: string) {
  return status === 'paused';
}

function isDowngradeStatus(status: string) {
  return status === 'cancelled' || status === 'canceled' || status === 'expired';
}

function mapAuthorizedPaymentStatus(status: string | null) {
  const normalized = normalizeProviderStatus(status);
  switch (normalized) {
    case 'processed':
      return 'processed';
    case 'paid':
    case 'approved':
    case 'accredited':
    case 'active':
    case 'authorized':
      return 'paid';
    case 'pending':
      return 'pending';
    case 'in_process':
      return 'in_process';
    case 'rejected':
    case 'failed':
      return 'failed';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'refunded':
    case 'charged_back':
      return 'refunded';
    default:
      return 'unknown';
  }
}

function normalizeNullablePlan(value: string | null | undefined) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  return normalizePlan(value);
}

function mergeWarnings<T extends { warnings?: string[] }>(
  value: T,
  warnings: string[] | undefined,
) {
  const uniqueWarnings = [...new Set(warnings ?? [])];
  return uniqueWarnings.length === 0
    ? value
    : { ...value, warnings: uniqueWarnings };
}

function safeInvoiceUrl(value: string | null) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  try {
    const parsed = new URL(value);
    if (
      (parsed.protocol === 'https:' || parsed.protocol === 'http:') &&
      parsed.username.length === 0 &&
      parsed.password.length === 0 &&
      parsed.search.length === 0 &&
      parsed.hash.length === 0
    ) {
      return parsed.toString();
    }
  } catch {
    return maskUrl(value);
  }
  return maskUrl(value);
}

function safePersistedInvoiceUrl(value: string | null) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  try {
    const parsed = new URL(value);
    if (
      (parsed.protocol === 'https:' || parsed.protocol === 'http:') &&
      parsed.username.length === 0 &&
      parsed.password.length === 0 &&
      parsed.search.length === 0 &&
      parsed.hash.length === 0
    ) {
      return parsed.toString();
    }
  } catch {
    return null;
  }
  return null;
}

function assertNonEmptyLocalId(value: string, field: string) {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new AppError('Identificador de billing invalido.', 400, 'BILLING_ID_INVALID', {
      field,
    });
  }
  return trimmed;
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

