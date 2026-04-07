-- CreateEnum
CREATE TYPE "SessionClientType" AS ENUM ('MOBILE_APP', 'ADMIN_WEB', 'UNKNOWN');

-- CreateTable
CREATE TABLE "DeviceSession" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "membershipId" TEXT NOT NULL,
    "clientType" "SessionClientType" NOT NULL DEFAULT 'MOBILE_APP',
    "clientInstanceId" TEXT NOT NULL,
    "deviceLabel" TEXT,
    "platform" TEXT,
    "appVersion" TEXT,
    "refreshTokenHash" TEXT NOT NULL,
    "refreshTokenExpiresAt" TIMESTAMP(3) NOT NULL,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastRefreshedAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "revokedReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeviceSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SessionAuditLog" (
    "id" TEXT NOT NULL,
    "deviceSessionId" TEXT,
    "actorUserId" TEXT,
    "subjectUserId" TEXT,
    "companyId" TEXT,
    "action" TEXT NOT NULL,
    "details" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SessionAuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DeviceSession_refreshTokenHash_key" ON "DeviceSession"("refreshTokenHash");

-- CreateIndex
CREATE INDEX "DeviceSession_companyId_clientType_revokedAt_idx" ON "DeviceSession"("companyId", "clientType", "revokedAt");

-- CreateIndex
CREATE INDEX "DeviceSession_companyId_clientType_clientInstanceId_idx" ON "DeviceSession"("companyId", "clientType", "clientInstanceId");

-- CreateIndex
CREATE INDEX "DeviceSession_userId_companyId_revokedAt_idx" ON "DeviceSession"("userId", "companyId", "revokedAt");

-- CreateIndex
CREATE INDEX "DeviceSession_refreshTokenExpiresAt_idx" ON "DeviceSession"("refreshTokenExpiresAt");

-- CreateIndex
CREATE INDEX "DeviceSession_lastSeenAt_idx" ON "DeviceSession"("lastSeenAt");

-- CreateIndex
CREATE INDEX "SessionAuditLog_createdAt_idx" ON "SessionAuditLog"("createdAt");

-- CreateIndex
CREATE INDEX "SessionAuditLog_action_idx" ON "SessionAuditLog"("action");

-- CreateIndex
CREATE INDEX "SessionAuditLog_companyId_idx" ON "SessionAuditLog"("companyId");

-- CreateIndex
CREATE INDEX "SessionAuditLog_deviceSessionId_idx" ON "SessionAuditLog"("deviceSessionId");

-- CreateIndex
CREATE INDEX "SessionAuditLog_actorUserId_idx" ON "SessionAuditLog"("actorUserId");

-- CreateIndex
CREATE INDEX "SessionAuditLog_subjectUserId_idx" ON "SessionAuditLog"("subjectUserId");

-- AddForeignKey
ALTER TABLE "DeviceSession" ADD CONSTRAINT "DeviceSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceSession" ADD CONSTRAINT "DeviceSession_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceSession" ADD CONSTRAINT "DeviceSession_membershipId_fkey" FOREIGN KEY ("membershipId") REFERENCES "Membership"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SessionAuditLog" ADD CONSTRAINT "SessionAuditLog_deviceSessionId_fkey" FOREIGN KEY ("deviceSessionId") REFERENCES "DeviceSession"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SessionAuditLog" ADD CONSTRAINT "SessionAuditLog_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SessionAuditLog" ADD CONSTRAINT "SessionAuditLog_subjectUserId_fkey" FOREIGN KEY ("subjectUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SessionAuditLog" ADD CONSTRAINT "SessionAuditLog_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE SET NULL ON UPDATE CASCADE;
