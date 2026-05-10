-- Fase C1: PRO employee profiles and permission foundation.
CREATE TABLE "EmployeeProfile" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "userId" TEXT,
  "membershipId" TEXT,
  "name" TEXT NOT NULL,
  "email" TEXT,
  "emailNormalized" TEXT,
  "phone" TEXT,
  "role" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "permissions" JSONB,
  "invitedAt" TIMESTAMP(3),
  "inviteTokenHash" TEXT,
  "inviteExpiresAt" TIMESTAMP(3),
  "acceptedAt" TIMESTAMP(3),
  "disabledAt" TIMESTAMP(3),
  "createdByUserId" TEXT,
  "updatedByUserId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "EmployeeProfile_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "EmployeeProfile_companyId_membershipId_key"
  ON "EmployeeProfile"("companyId", "membershipId");

CREATE UNIQUE INDEX "EmployeeProfile_companyId_emailNormalized_key"
  ON "EmployeeProfile"("companyId", "emailNormalized")
  WHERE "emailNormalized" IS NOT NULL;

CREATE INDEX "EmployeeProfile_companyId_idx"
  ON "EmployeeProfile"("companyId");

CREATE INDEX "EmployeeProfile_companyId_status_idx"
  ON "EmployeeProfile"("companyId", "status");

CREATE INDEX "EmployeeProfile_companyId_role_idx"
  ON "EmployeeProfile"("companyId", "role");

CREATE INDEX "EmployeeProfile_companyId_userId_idx"
  ON "EmployeeProfile"("companyId", "userId");

CREATE INDEX "EmployeeProfile_companyId_membershipId_idx"
  ON "EmployeeProfile"("companyId", "membershipId");

ALTER TABLE "EmployeeProfile"
  ADD CONSTRAINT "EmployeeProfile_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Company"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "EmployeeProfile"
  ADD CONSTRAINT "EmployeeProfile_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "EmployeeProfile"
  ADD CONSTRAINT "EmployeeProfile_membershipId_fkey"
  FOREIGN KEY ("membershipId") REFERENCES "Membership"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "EmployeeProfile"
  ADD CONSTRAINT "EmployeeProfile_createdByUserId_fkey"
  FOREIGN KEY ("createdByUserId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "EmployeeProfile"
  ADD CONSTRAINT "EmployeeProfile_updatedByUserId_fkey"
  FOREIGN KEY ("updatedByUserId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
