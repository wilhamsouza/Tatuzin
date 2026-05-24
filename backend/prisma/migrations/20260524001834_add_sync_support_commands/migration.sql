-- CreateEnum
CREATE TYPE "SyncSupportCommandStatus" AS ENUM ('PENDING', 'RUNNING', 'SUCCEEDED', 'FAILED', 'EXPIRED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "SyncSupportCommandType" AS ENUM ('RETRY_FAILED_SYNC_EVENTS', 'REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS', 'CLEAR_RESOLVED_CONFLICT_CACHE', 'FORCE_SYNC_PULL', 'REFRESH_SYNC_STATUS');

-- CreateTable
CREATE TABLE "SyncSupportCommand" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "actorUserId" TEXT NOT NULL,
    "command" "SyncSupportCommandType" NOT NULL,
    "status" "SyncSupportCommandStatus" NOT NULL DEFAULT 'PENDING',
    "reason" TEXT NOT NULL,
    "confirmationText" TEXT,
    "dryRunResult" JSONB,
    "payload" JSONB,
    "result" JSONB,
    "errorMessage" TEXT,
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "pickedUpAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SyncSupportCommand_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeviceSyncDiagnostic" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "userId" TEXT,
    "clientInstanceId" TEXT,
    "appVersion" TEXT,
    "localSchemaVersion" TEXT,
    "pendingCount" INTEGER NOT NULL DEFAULT 0,
    "failedCount" INTEGER NOT NULL DEFAULT 0,
    "openConflictCount" INTEGER NOT NULL DEFAULT 0,
    "resolvedConflictCount" INTEGER NOT NULL DEFAULT 0,
    "ignoredConflictCount" INTEGER NOT NULL DEFAULT 0,
    "lastLocalError" TEXT,
    "lastLocalErrorCode" TEXT,
    "lastLocalErrorEntity" TEXT,
    "lastPushAt" TIMESTAMP(3),
    "lastPullAt" TIMESTAMP(3),
    "lastSuccessfulSyncAt" TIMESTAMP(3),
    "safeDetails" JSONB,
    "reportedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeviceSyncDiagnostic_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "SyncSupportCommand_companyId_deviceId_status_idx" ON "SyncSupportCommand"("companyId", "deviceId", "status");

-- CreateIndex
CREATE INDEX "SyncSupportCommand_companyId_status_idx" ON "SyncSupportCommand"("companyId", "status");

-- CreateIndex
CREATE INDEX "SyncSupportCommand_deviceId_status_idx" ON "SyncSupportCommand"("deviceId", "status");

-- CreateIndex
CREATE INDEX "SyncSupportCommand_expiresAt_idx" ON "SyncSupportCommand"("expiresAt");

-- CreateIndex
CREATE INDEX "SyncSupportCommand_requestedAt_idx" ON "SyncSupportCommand"("requestedAt");

-- CreateIndex
CREATE UNIQUE INDEX "CompanyDevice_companyId_id_key" ON "CompanyDevice"("companyId", "id");

-- CreateIndex
CREATE INDEX "DeviceSyncDiagnostic_companyId_reportedAt_idx" ON "DeviceSyncDiagnostic"("companyId", "reportedAt");

-- CreateIndex
CREATE INDEX "DeviceSyncDiagnostic_deviceId_idx" ON "DeviceSyncDiagnostic"("deviceId");

-- CreateIndex
CREATE UNIQUE INDEX "DeviceSyncDiagnostic_companyId_deviceId_key" ON "DeviceSyncDiagnostic"("companyId", "deviceId");

-- AddForeignKey
ALTER TABLE "SyncSupportCommand" ADD CONSTRAINT "SyncSupportCommand_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncSupportCommand" ADD CONSTRAINT "SyncSupportCommand_companyId_deviceId_fkey" FOREIGN KEY ("companyId", "deviceId") REFERENCES "CompanyDevice"("companyId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncSupportCommand" ADD CONSTRAINT "SyncSupportCommand_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceSyncDiagnostic" ADD CONSTRAINT "DeviceSyncDiagnostic_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceSyncDiagnostic" ADD CONSTRAINT "DeviceSyncDiagnostic_companyId_deviceId_fkey" FOREIGN KEY ("companyId", "deviceId") REFERENCES "CompanyDevice"("companyId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceSyncDiagnostic" ADD CONSTRAINT "DeviceSyncDiagnostic_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- RenameIndex
ALTER INDEX "AnalyticsCustomerDailySnapshot_companyId_snapshotDate_customerK" RENAME TO "AnalyticsCustomerDailySnapshot_companyId_snapshotDate_custo_key";

-- RenameIndex
ALTER INDEX "AnalyticsProductDailySnapshot_companyId_snapshotDate_productKey" RENAME TO "AnalyticsProductDailySnapshot_companyId_snapshotDate_produc_key";
