import type { FeatureKey, PlanKey, PlanLimits } from '../plans/plan-catalog.service';

export type BillingCycle = 'free' | 'monthly';
export type BillingProvider = 'mercadopago';
export type PaidPlanKey = Exclude<PlanKey, 'FREE'>;

export type PublicBillingPlan = {
  key: PlanKey;
  name: string;
  priceCents: number;
  currency: 'BRL';
  billingCycle: BillingCycle;
  description: string;
  featuresSummary: string[];
};

export type BillingStatusDto = {
  companyId: string;
  plan: PlanKey;
  status: string;
  currentPeriodStart: string | null;
  currentPeriodEnd: string | null;
  expiresAt: string | null;
  provider: BillingProvider | null;
  hasProviderSubscription: boolean;
  maskedProviderSubscriptionId?: string | null;
  canManageBilling: boolean;
  nextPaymentDate: string | null;
  limits: PlanLimits;
  features: Record<FeatureKey, boolean>;
};

export type AdminBillingStatusDto = BillingStatusDto & {
  providerSubscriptionId: string | null;
};

export type SubscribeResultDto = {
  checkoutUrl: string | null;
  provider: BillingProvider | null;
  plan: PaidPlanKey;
  checkoutSessionId: string | null;
  expiresAt: string | null;
  status?: BillingStatusDto;
};

export type MercadoPagoPreapprovalCreateInput = {
  plan: PaidPlanKey;
  priceCents: number;
  checkoutSessionId: string;
  payerEmail: string;
  backUrl: string;
  notificationUrl: string | null;
};

export type MercadoPagoPreapprovalResult = {
  id: string;
  initPoint: string | null;
  sandboxInitPoint: string | null;
  status: string | null;
};

export type MercadoPagoSubscriptionDetails = {
  providerReference: string;
  status: string | null;
  externalReference: string | null;
  currentPeriodStart: Date | null;
  currentPeriodEnd: Date | null;
  nextPaymentDate: Date | null;
};

export type MercadoPagoWebhookContext = {
  body: Record<string, unknown>;
  query: Record<string, unknown>;
  headers: Record<string, string | undefined>;
};
