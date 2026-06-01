CREATE TABLE "AdminUserPermission" (
    "id" TEXT NOT NULL,
    "actorUserId" TEXT NOT NULL,
    "permissionKey" TEXT NOT NULL,
    "scope" TEXT NOT NULL DEFAULT 'platform',
    "scopeId" TEXT NOT NULL DEFAULT '*',
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdminUserPermission_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AdminUserPermission_actorUserId_permissionKey_scope_scopeId_key"
    ON "AdminUserPermission"("actorUserId", "permissionKey", "scope", "scopeId");

CREATE INDEX "AdminUserPermission_actorUserId_isActive_idx"
    ON "AdminUserPermission"("actorUserId", "isActive");

CREATE INDEX "AdminUserPermission_permissionKey_idx"
    ON "AdminUserPermission"("permissionKey");

CREATE INDEX "AdminUserPermission_scope_scopeId_idx"
    ON "AdminUserPermission"("scope", "scopeId");

ALTER TABLE "AdminUserPermission"
    ADD CONSTRAINT "AdminUserPermission_actorUserId_fkey"
    FOREIGN KEY ("actorUserId") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
