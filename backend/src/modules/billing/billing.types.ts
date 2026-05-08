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
  cancelAtPeriodEnd: boolean;
  cancelRequestedAt: string | null;
  canceledAt: string | null;
  pendingPlan: PlanKey | null;
  pendingPlanRequestedAt: string | null;
  billingSubscriptionStatus: string | null;
  provider: BillingProvider | null;
  hasProviderSubscription: boolean;
  maskedProviderSubscriptionId?: string | null;
  canManageBilling: boolean;
  nextPaymentDate: string | null;
  limits: PlanLimits;
  features: Record<FeatureKey, boolean>;
  warnings?: string[];
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

export type BillingInvoiceDto = {
  id: string;
  provider: BillingProvider;
  providerInvoiceId: string | null;
  maskedProviderSubscriptionId: string | null;
  plan: PlanKey | null;
  status: string;
  amountCents: number;
  currency: string;
  periodStart: string | null;
  periodEnd: string | null;
  dueAt: string | null;
  paidAt: string | null;
  failedAt: string | null;
  invoiceUrl: string | null;
  createdAt: string;
  updatedAt: string;
};

export type BillingPaymentMethodDto = {
  provider: BillingProvider | null;
  hasPaymentMethod: boolean;
  unavailable?: boolean;
  message?: string;
  paymentMethodId?: string | null;
  paymentMethodType?: string | null;
  lastFour?: string | null;
  status?: string | null;
  nextPaymentDate?: string | null;
  maskedProviderSubscriptionId?: string | null;
};

export type BillingActionResultDto = {
  status: BillingStatusDto;
  providerCancelled?: boolean;
  effective?: 'period_end' | 'now';
  requiresNewCheckout?: boolean;
  message: string;
  checkoutUrl?: string | null;
  checkoutSessionId?: string | null;
  pendingPlan?: PlanKey | null;
};

export type MercadoPagoPreapprovalCreateInput = {
  plan: PaidPlanKey;
  priceCents: number;
  checkoutSessionId: string;
  payerEmail: string;
  backUrl: string;
  notificationUrl: string | null;
};

export type MercadoPagoPreapprovalUpdateInput = {
  reason?: string;
  status?: string;
  auto_recurring?: {
    frequency: 1;
    frequency_type: 'months';
    transaction_amount: number;
    currency_id: 'BRL';
  };
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
  amountCents?: number | null;
  paymentMethodId?: string | null;
  paymentMethodType?: string | null;
  lastFour?: string | null;
  rawPayload?: Record<string, unknown> | null;
};

export type MercadoPagoAuthorizedPaymentDetails = {
  providerInvoiceId: string | null;
  providerSubscriptionId: string | null;
  status: string | null;
  amountCents: number;
  currency: string | null;
  periodStart: Date | null;
  periodEnd: Date | null;
  dueAt: Date | null;
  paidAt: Date | null;
  failedAt: Date | null;
  invoiceUrl: string | null;
  rawPayload: Record<string, unknown>;
};

export type MercadoPagoWebhookContext = {
  body: Record<string, unknown>;
  query: Record<string, unknown>;
  headers: Record<string, string | undefined>;
};
