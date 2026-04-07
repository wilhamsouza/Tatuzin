-- CreateEnum
CREATE TYPE "LicenseStatus" AS ENUM ('TRIAL', 'ACTIVE', 'SUSPENDED', 'EXPIRED');

-- AlterTable
ALTER TABLE "User"
ADD COLUMN "isPlatformAdmin" BOOLEAN NOT NULL DEFAULT FALSE;

-- CreateTable
CREATE TABLE "License" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "plan" TEXT NOT NULL,
  "status" "LicenseStatus" NOT NULL DEFAULT 'TRIAL',
  "startsAt" TIMESTAMP(3) NOT NULL,
  "expiresAt" TIMESTAMP(3),
  "maxDevices" INTEGER,
  "syncEnabled" BOOLEAN NOT NULL DEFAULT TRUE,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "License_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdminAuditLog" (
  "id" TEXT NOT NULL,
  "actorUserId" TEXT NOT NULL,
  "targetCompanyId" TEXT,
  "action" TEXT NOT NULL,
  "details" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "AdminAuditLog_pkey" PRIMARY KEY ("id")
);

-- Backfill existing companies with a non-breaking cloud license.
INSERT INTO "License" (
  "id",
  "companyId",
  "plan",
  "status",
  "startsAt",
  "expiresAt",
  "maxDevices",
  "syncEnabled",
  "createdAt",
  "updatedAt"
)
SELECT
  'lic_' || md5("Company"."id" || ':license'),
  "Company"."id",
  'legacy',
  'ACTIVE'::"LicenseStatus",
  CURRENT_TIMESTAMP,
  NULL,
  NULL,
  TRUE,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "Company"
WHERE NOT EXISTS (
  SELECT 1
  FROM "License"
  WHERE "License"."companyId" = "Company"."id"
);

-- Promote existing owner users to platform admins to preserve current operability.
UPDATE "User"
SET "isPlatformAdmin" = TRUE
WHERE "id" IN (
  SELECT DISTINCT "userId"
  FROM "Membership"
  WHERE "role" = 'OWNER'
);

-- CreateIndex
CREATE UNIQUE INDEX "License_companyId_key" ON "License"("companyId");

-- CreateIndex
CREATE INDEX "License_status_idx" ON "License"("status");

-- CreateIndex
CREATE INDEX "License_syncEnabled_idx" ON "License"("syncEnabled");

-- CreateIndex
CREATE INDEX "License_expiresAt_idx" ON "License"("expiresAt");

-- CreateIndex
CREATE INDEX "AdminAuditLog_createdAt_idx" ON "AdminAuditLog"("createdAt");

-- CreateIndex
CREATE INDEX "AdminAuditLog_action_idx" ON "AdminAuditLog"("action");

-- CreateIndex
CREATE INDEX "AdminAuditLog_targetCompanyId_idx" ON "AdminAuditLog"("targetCompanyId");

-- AddForeignKey
ALTER TABLE "License"
ADD CONSTRAINT "License_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdminAuditLog"
ADD CONSTRAINT "AdminAuditLog_actorUserId_fkey"
FOREIGN KEY ("actorUserId") REFERENCES "User"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdminAuditLog"
ADD CONSTRAINT "AdminAuditLog_targetCompanyId_fkey"
FOREIGN KEY ("targetCompanyId") REFERENCES "Company"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
