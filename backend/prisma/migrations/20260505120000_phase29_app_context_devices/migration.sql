-- CreateEnum
CREATE TYPE "CompanyDeviceStatus" AS ENUM ('PENDING', 'ACTIVE', 'BLOCKED', 'REVOKED');

-- CreateTable
CREATE TABLE "CompanyDevice" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "clientInstanceId" TEXT NOT NULL,
    "deviceLabel" TEXT,
    "platform" TEXT,
    "appVersion" TEXT,
    "status" "CompanyDeviceStatus" NOT NULL DEFAULT 'PENDING',
    "approvedAt" TIMESTAMP(3),
    "approvedByUserId" TEXT,
    "lastSeenAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "revokedReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CompanyDevice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CompanyDevice_companyId_clientInstanceId_key" ON "CompanyDevice"("companyId", "clientInstanceId");

-- CreateIndex
CREATE INDEX "CompanyDevice_companyId_idx" ON "CompanyDevice"("companyId");

-- CreateIndex
CREATE INDEX "CompanyDevice_userId_idx" ON "CompanyDevice"("userId");

-- CreateIndex
CREATE INDEX "CompanyDevice_status_idx" ON "CompanyDevice"("status");

-- AddForeignKey
ALTER TABLE "CompanyDevice" ADD CONSTRAINT "CompanyDevice_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CompanyDevice" ADD CONSTRAINT "CompanyDevice_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
