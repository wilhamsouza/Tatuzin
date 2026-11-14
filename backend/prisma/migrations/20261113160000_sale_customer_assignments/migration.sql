ALTER TABLE "Sale" ADD COLUMN "sellerUserId" TEXT,
  ADD COLUMN "customerAssignmentRevision" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "customerAssignmentLocked" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "creditUsedCents" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "creditGeneratedCents" INTEGER NOT NULL DEFAULT 0;

UPDATE "Sale" s SET "sellerUserId" = e."userId",
  "creditUsedCents" = CASE WHEN e.payload->>'creditUsedCents' ~ '^[0-9]+$'
    THEN LEAST((e.payload->>'creditUsedCents')::numeric,2147483647)::int ELSE 0 END,
  "creditGeneratedCents" = CASE WHEN e.payload->>'creditGeneratedCents' ~ '^[0-9]+$'
    THEN LEAST((e.payload->>'creditGeneratedCents')::numeric,2147483647)::int ELSE 0 END
FROM (SELECT DISTINCT ON ("companyId", "entityServerId") * FROM "SyncEvent"
  WHERE entity = 'sale' AND status = 'ACCEPTED' AND operation IN ('create','append','upsert')
  ORDER BY "companyId", "entityServerId", "createdAt") e
WHERE e."companyId" = s."companyId" AND e."entityServerId" = s.id;

CREATE TABLE "SaleCustomerAssignment" (
  id TEXT PRIMARY KEY, "companyId" TEXT NOT NULL, "saleId" TEXT NOT NULL,
  "previousCustomerId" TEXT, "customerId" TEXT NOT NULL, revision INTEGER NOT NULL,
  "actorUserId" TEXT NOT NULL, "deviceId" TEXT NOT NULL,
  "occurredAt" TIMESTAMP(3) NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SaleCustomerAssignment_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX "SaleCustomerAssignment_saleId_revision_key" ON "SaleCustomerAssignment"("saleId", revision);
CREATE INDEX "SaleCustomerAssignment_companyId_saleId_idx" ON "SaleCustomerAssignment"("companyId", "saleId");
