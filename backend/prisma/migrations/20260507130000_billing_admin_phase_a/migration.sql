-- Billing admin Phase A: admin audit, invoice base, and local subscription flags.
ALTER TABLE "License" ADD COLUMN "cancelAtPeriodEnd" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "License" ADD COLUMN "cancelRequestedAt" TIMESTAMP(3);
ALTER TABLE "License" ADD COLUMN "canceledAt" TIMESTAMP(3);
ALTER TABLE "License" ADD COLUMN "pendingPlan" TEXT;
ALTER TABLE "License" ADD COLUMN "pendingPlanRequestedAt" TIMESTAMP(3);
ALTER TABLE "License" ADD COLUMN "billingSubscriptionStatus" TEXT;

ALTER TABLE "BillingProviderEvent" ADD COLUMN "companyId" TEXT;

CREATE TABLE "BillingInvoice" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "providerInvoiceId" TEXT,
  "providerSubscriptionId" TEXT,
  "plan" TEXT,
  "status" TEXT NOT NULL,
  "amountCents" INTEGER NOT NULL DEFAULT 0,
  "currency" TEXT NOT NULL DEFAULT 'BRL',
  "periodStart" TIMESTAMP(3),
  "periodEnd" TIMESTAMP(3),
  "dueAt" TIMESTAMP(3),
  "paidAt" TIMESTAMP(3),
  "failedAt" TIMESTAMP(3),
  "invoiceUrl" TEXT,
  "payload" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "BillingInvoice_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "BillingAdminAuditLog" (
  "id" TEXT NOT NULL,
  "actorUserId" TEXT NOT NULL,
  "companyId" TEXT,
  "action" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "before" JSONB,
  "after" JSONB,
  "metadata" JSONB,
  "ipAddress" TEXT,
  "userAgent" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "BillingAdminAuditLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "BillingProviderEvent_companyId_idx" ON "BillingProviderEvent"("companyId");
CREATE INDEX "BillingInvoice_companyId_idx" ON "BillingInvoice"("companyId");
CREATE INDEX "BillingInvoice_status_idx" ON "BillingInvoice"("status");
CREATE INDEX "BillingInvoice_dueAt_idx" ON "BillingInvoice"("dueAt");
CREATE INDEX "BillingInvoice_providerSubscriptionId_idx" ON "BillingInvoice"("providerSubscriptionId");
CREATE UNIQUE INDEX "BillingInvoice_provider_providerInvoiceId_key" ON "BillingInvoice"("provider", "providerInvoiceId") WHERE "providerInvoiceId" IS NOT NULL;
CREATE INDEX "BillingAdminAuditLog_companyId_idx" ON "BillingAdminAuditLog"("companyId");
CREATE INDEX "BillingAdminAuditLog_actorUserId_idx" ON "BillingAdminAuditLog"("actorUserId");
CREATE INDEX "BillingAdminAuditLog_action_idx" ON "BillingAdminAuditLog"("action");
CREATE INDEX "BillingAdminAuditLog_createdAt_idx" ON "BillingAdminAuditLog"("createdAt");

ALTER TABLE "BillingProviderEvent" ADD CONSTRAINT "BillingProviderEvent_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BillingInvoice" ADD CONSTRAINT "BillingInvoice_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BillingAdminAuditLog" ADD CONSTRAINT "BillingAdminAuditLog_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "BillingAdminAuditLog" ADD CONSTRAINT "BillingAdminAuditLog_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE SET NULL ON UPDATE CASCADE;
