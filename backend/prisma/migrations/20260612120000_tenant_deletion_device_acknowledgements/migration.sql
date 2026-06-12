ALTER TYPE "TenantDeletionAuditEventType"
ADD VALUE IF NOT EXISTS 'DEVICE_ACKNOWLEDGED';

CREATE TABLE "TenantDeletionDeviceAcknowledgement" (
  "id" TEXT NOT NULL,
  "tenantDeletionRequestId" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "clientInstanceId" TEXT NOT NULL,
  "deviceLabel" TEXT,
  "platform" TEXT,
  "appVersion" TEXT,
  "acknowledgedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "source" TEXT NOT NULL,
  "metadataJson" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "TenantDeletionDeviceAcknowledgement_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "TenantDeletionDeviceAcknowledgement_tenantDeletionRequestId_clientInstanceId_key"
ON "TenantDeletionDeviceAcknowledgement"("tenantDeletionRequestId", "clientInstanceId");

CREATE INDEX "TenantDeletionDeviceAcknowledgement_companyId_acknowledgedAt_idx"
ON "TenantDeletionDeviceAcknowledgement"("companyId", "acknowledgedAt");

CREATE INDEX "TenantDeletionDeviceAcknowledgement_tenantDeletionRequestId_acknowledgedAt_idx"
ON "TenantDeletionDeviceAcknowledgement"("tenantDeletionRequestId", "acknowledgedAt");

ALTER TABLE "TenantDeletionDeviceAcknowledgement"
ADD CONSTRAINT "TenantDeletionDeviceAcknowledgement_tenantDeletionRequestId_fkey"
FOREIGN KEY ("tenantDeletionRequestId") REFERENCES "TenantDeletionRequest"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "TenantDeletionDeviceAcknowledgement"
ADD CONSTRAINT "TenantDeletionDeviceAcknowledgement_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;
