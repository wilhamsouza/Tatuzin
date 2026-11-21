import { prisma } from '../../database/prisma';
import { env } from '../../config/env';
import { AppError } from '../../shared/http/app-error';
import type { AppContext } from './app-context.types';

export type CompanyOnboardingProgress = {
  enabled: boolean;
  productReady: boolean;
  cashReady: boolean;
  completedAt: string | null;
};

export class CompanyOnboardingService {
  constructor(private readonly db = prisma,
    private readonly enabledFor = isCompanyOnboardingEnabled) {}

  async reconcile(context: AppContext): Promise<CompanyOnboardingProgress> {
    if (context.membership.role.trim().toUpperCase() !== 'OWNER') {
      throw new AppError('Somente o dono pode configurar a loja.', 403, 'ONBOARDING_FORBIDDEN');
    }
    const companyId = context.company.id;
    if (!this.enabledFor(companyId)) {
      return { enabled: false, productReady: false, cashReady: false, completedAt: null };
    }

    return this.db.$transaction(async (tx) => {
      const [company, product, cash, sale] = await Promise.all([
        tx.company.findUniqueOrThrow({ where: { id: companyId } }),
        tx.product.findFirst({ where: { companyId, isActive: true, deletedAt: null },
          orderBy: { createdAt: 'asc' }, select: { createdAt: true } }),
        tx.cashSession.findFirst({ where: { companyId, openedAt: { not: null } },
          orderBy: { openedAt: 'asc' }, select: { openedAt: true } }),
        tx.sale.findFirst({ where: { companyId, status: 'active' },
          orderBy: { soldAt: 'asc' }, select: { soldAt: true } }),
      ]);
      const saved = await tx.company.update({ where: { id: companyId }, data: {
        ...(company.onboardingProductAt == null && product ? { onboardingProductAt: product.createdAt } : {}),
        ...(company.onboardingCashAt == null && cash ? { onboardingCashAt: cash.openedAt } : {}),
        ...(company.onboardingCompletedAt == null && sale ? { onboardingCompletedAt: sale.soldAt } : {}),
      } });
      return {
        enabled: true,
        productReady: saved.onboardingProductAt != null || saved.onboardingCompletedAt != null,
        cashReady: saved.onboardingCashAt != null || saved.onboardingCompletedAt != null,
        completedAt: saved.onboardingCompletedAt?.toISOString() ?? null,
      };
    });
  }
}

export function isCompanyOnboardingEnabled(companyId: string) {
  return env.PRODUCT_ONBOARDING_ENABLED ||
    env.PRODUCT_ONBOARDING_COMPANY_IDS.split(',').map((id) => id.trim()).includes(companyId);
}

export function isCompanyExperienceEnabled(companyId: string) {
  return env.PRODUCT_EXPERIENCE_ENABLED ||
    env.PRODUCT_EXPERIENCE_COMPANY_IDS.split(',').map((id) => id.trim()).includes(companyId);
}
