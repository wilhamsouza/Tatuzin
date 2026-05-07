-- Billing foundation for Tatuzin SaaS subscriptions.
ALTER TABLE "License" ADD COLUMN "billingProvider" TEXT;
ALTER TABLE "License" ADD COLUMN "providerSubscriptionId" TEXT;
ALTER TABLE "License" ADD COLUMN "currentPeriodStart" TIMESTAMP(3);
ALTER TABLE "License" ADD COLUMN "currentPeriodEnd" TIMESTAMP(3);
ALTER TABLE "License" ADD COLUMN "nextPaymentDate" TIMESTAMP(3);

CREATE TABLE "BillingCheckoutSession" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "plan" TEXT NOT NULL,
  "billingCycle" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "provider" TEXT NOT NULL,
  "providerReference" TEXT,
  "checkoutUrl" TEXT,
  "sandboxCheckoutUrl" TEXT,
  "expiresAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "BillingCheckoutSession_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "BillingProviderEvent" (
  "id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "providerEventId" TEXT,
  "dedupeKey" TEXT NOT NULL,
  "payload" JSONB NOT NULL,
  "status" TEXT NOT NULL,
  "processedAt" TIMESTAMP(3),
  "errorMessage" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "BillingProviderEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "License_billingProvider_idx" ON "License"("billingProvider");
CREATE INDEX "License_providerSubscriptionId_idx" ON "License"("providerSubscriptionId");
CREATE INDEX "BillingCheckoutSession_companyId_idx" ON "BillingCheckoutSession"("companyId");
CREATE INDEX "BillingCheckoutSession_userId_idx" ON "BillingCheckoutSession"("userId");
CREATE INDEX "BillingCheckoutSession_status_idx" ON "BillingCheckoutSession"("status");
CREATE INDEX "BillingCheckoutSession_provider_providerReference_idx" ON "BillingCheckoutSession"("provider", "providerReference");
CREATE UNIQUE INDEX "BillingProviderEvent_provider_dedupeKey_key" ON "BillingProviderEvent"("provider", "dedupeKey");
CREATE INDEX "BillingProviderEvent_providerEventId_idx" ON "BillingProviderEvent"("providerEventId");
CREATE INDEX "BillingProviderEvent_status_idx" ON "BillingProviderEvent"("status");
CREATE INDEX "BillingProviderEvent_createdAt_idx" ON "BillingProviderEvent"("createdAt");

ALTER TABLE "BillingCheckoutSession" ADD CONSTRAINT "BillingCheckoutSession_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BillingCheckoutSession" ADD CONSTRAINT "BillingCheckoutSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
