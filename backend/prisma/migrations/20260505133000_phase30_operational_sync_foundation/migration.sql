-- CreateEnum
CREATE TYPE "SyncEventStatus" AS ENUM ('PENDING', 'ACCEPTED', 'DUPLICATE', 'REJECTED', 'CONFLICT', 'FAILED');

-- CreateEnum
CREATE TYPE "SyncConflictStatus" AS ENUM ('OPEN', 'RESOLVED', 'IGNORED');

-- CreateTable
CREATE TABLE "CompanySyncState" (
    "companyId" TEXT NOT NULL,
    "currentVersion" BIGINT NOT NULL DEFAULT 0,
    "serverFirstSnapshotVersion" BIGINT NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CompanySyncState_pkey" PRIMARY KEY ("companyId")
);

-- CreateTable
CREATE TABLE "SyncEvent" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "eventId" TEXT NOT NULL,
    "feature" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "operation" TEXT NOT NULL,
    "entityLocalId" TEXT,
    "entityServerId" TEXT,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "payload" JSONB NOT NULL,
    "status" "SyncEventStatus" NOT NULL DEFAULT 'PENDING',
    "serverVersion" BIGINT,
    "rejectionCode" TEXT,
    "rejectionMessage" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SyncEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SyncCheckpoint" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "feature" TEXT NOT NULL,
    "lastServerVersion" BIGINT NOT NULL DEFAULT 0,
    "lastPushedAt" TIMESTAMP(3),
    "lastPulledAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SyncCheckpoint_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SyncConflict" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "syncEventId" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "entityLocalId" TEXT,
    "entityServerId" TEXT,
    "code" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "status" "SyncConflictStatus" NOT NULL DEFAULT 'OPEN',
    "payload" JSONB,
    "resolution" JSONB,
    "resolvedAt" TIMESTAMP(3),
    "resolvedByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SyncConflict_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SyncIncident" (
    "id" TEXT NOT NULL,
    "companyId" TEXT,
    "deviceId" TEXT,
    "userId" TEXT,
    "syncEventId" TEXT,
    "code" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "severity" TEXT NOT NULL DEFAULT 'warn',
    "details" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SyncIncident_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SyncEvent_companyId_deviceId_eventId_key" ON "SyncEvent"("companyId", "deviceId", "eventId");

-- CreateIndex
CREATE INDEX "SyncEvent_companyId_serverVersion_idx" ON "SyncEvent"("companyId", "serverVersion");

-- CreateIndex
CREATE INDEX "SyncEvent_companyId_feature_serverVersion_idx" ON "SyncEvent"("companyId", "feature", "serverVersion");

-- CreateIndex
CREATE INDEX "SyncEvent_companyId_entity_idx" ON "SyncEvent"("companyId", "entity");

-- CreateIndex
CREATE INDEX "SyncEvent_status_idx" ON "SyncEvent"("status");

-- CreateIndex
CREATE UNIQUE INDEX "SyncCheckpoint_companyId_deviceId_feature_key" ON "SyncCheckpoint"("companyId", "deviceId", "feature");

-- CreateIndex
CREATE INDEX "SyncCheckpoint_companyId_deviceId_idx" ON "SyncCheckpoint"("companyId", "deviceId");

-- CreateIndex
CREATE INDEX "SyncCheckpoint_companyId_feature_idx" ON "SyncCheckpoint"("companyId", "feature");

-- CreateIndex
CREATE UNIQUE INDEX "SyncConflict_syncEventId_key" ON "SyncConflict"("syncEventId");

-- CreateIndex
CREATE INDEX "SyncConflict_companyId_status_idx" ON "SyncConflict"("companyId", "status");

-- CreateIndex
CREATE INDEX "SyncConflict_companyId_entity_idx" ON "SyncConflict"("companyId", "entity");

-- CreateIndex
CREATE INDEX "SyncConflict_deviceId_idx" ON "SyncConflict"("deviceId");

-- CreateIndex
CREATE INDEX "SyncIncident_companyId_createdAt_idx" ON "SyncIncident"("companyId", "createdAt");

-- CreateIndex
CREATE INDEX "SyncIncident_deviceId_createdAt_idx" ON "SyncIncident"("deviceId", "createdAt");

-- CreateIndex
CREATE INDEX "SyncIncident_code_idx" ON "SyncIncident"("code");

-- AddForeignKey
ALTER TABLE "CompanySyncState" ADD CONSTRAINT "CompanySyncState_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncEvent" ADD CONSTRAINT "SyncEvent_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncEvent" ADD CONSTRAINT "SyncEvent_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncEvent" ADD CONSTRAINT "SyncEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncCheckpoint" ADD CONSTRAINT "SyncCheckpoint_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncCheckpoint" ADD CONSTRAINT "SyncCheckpoint_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncConflict" ADD CONSTRAINT "SyncConflict_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncConflict" ADD CONSTRAINT "SyncConflict_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncConflict" ADD CONSTRAINT "SyncConflict_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncConflict" ADD CONSTRAINT "SyncConflict_syncEventId_fkey" FOREIGN KEY ("syncEventId") REFERENCES "SyncEvent"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncConflict" ADD CONSTRAINT "SyncConflict_resolvedByUserId_fkey" FOREIGN KEY ("resolvedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncIncident" ADD CONSTRAINT "SyncIncident_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncIncident" ADD CONSTRAINT "SyncIncident_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "CompanyDevice"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncIncident" ADD CONSTRAINT "SyncIncident_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncIncident" ADD CONSTRAINT "SyncIncident_syncEventId_fkey" FOREIGN KEY ("syncEventId") REFERENCES "SyncEvent"("id") ON DELETE SET NULL ON UPDATE CASCADE;
