-- Additive migration: old clients can continue reading. Keep these columns and
-- tables when rolling an application release back; do not replay old adjustments.
ALTER TABLE "Product" ADD COLUMN "catalogRevision" INTEGER NOT NULL DEFAULT 0,
 ADD COLUMN "stockRevision" INTEGER NOT NULL DEFAULT 0,
 ADD COLUMN "minimumStockMil" INTEGER NOT NULL DEFAULT 0,
 ADD COLUMN "reorderPointMil" INTEGER;
ALTER TABLE "ProductVariant" ADD COLUMN "stockRevision" INTEGER NOT NULL DEFAULT 0,
 ADD COLUMN "minimumStockMil" INTEGER NOT NULL DEFAULT 0,
 ADD COLUMN "reorderPointMil" INTEGER;
CREATE TABLE "InventoryMovement" (
 "id" TEXT NOT NULL DEFAULT gen_random_uuid()::text PRIMARY KEY,
 "companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE,
 "productId" TEXT NOT NULL, "productVariantId" TEXT,
 "productName" TEXT NOT NULL, "sku" TEXT, "unitMeasure" TEXT NOT NULL,
 "quantityDeltaMil" INTEGER NOT NULL, "stockBeforeMil" INTEGER NOT NULL,
 "stockAfterMil" INTEGER NOT NULL, "stockRevision" INTEGER NOT NULL,
 "type" TEXT NOT NULL, "origin" TEXT NOT NULL, "referenceId" TEXT,
 "actorUserId" TEXT, "actorName" TEXT, "reason" TEXT, "notes" TEXT,
 "operationId" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "InventoryMovement_delta_check" CHECK ("quantityDeltaMil" <> 0 AND "stockAfterMil"-"stockBeforeMil"="quantityDeltaMil")
);
CREATE INDEX "InventoryMovement_companyId_createdAt_id_idx" ON "InventoryMovement"("companyId","createdAt","id");
CREATE INDEX "InventoryMovement_companyId_productId_productVariantId_creat_idx" ON "InventoryMovement"("companyId","productId","productVariantId","createdAt");
CREATE INDEX "InventoryMovement_companyId_operationId_idx" ON "InventoryMovement"("companyId","operationId");
CREATE TABLE "InventoryCount" (
 "id" TEXT NOT NULL PRIMARY KEY,
 "companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE,
 "name" TEXT NOT NULL,"status" TEXT NOT NULL DEFAULT 'OPEN',"revision" INTEGER NOT NULL DEFAULT 0,
 "assigneeUserId" TEXT NOT NULL,"createdByUserId" TEXT NOT NULL,"requestId" TEXT NOT NULL,
 "appliedAt" TIMESTAMP(3),"canceledAt" TIMESTAMP(3),
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "InventoryCount_status_check" CHECK ("status" IN ('OPEN','COUNTING','REVIEWED','APPLIED','CANCELED'))
);
CREATE UNIQUE INDEX "InventoryCount_companyId_requestId_key" ON "InventoryCount"("companyId","requestId");
CREATE INDEX "InventoryCount_companyId_updatedAt_id_idx" ON "InventoryCount"("companyId","updatedAt","id");
CREATE TABLE "InventoryCountItem" (
 "id" TEXT NOT NULL PRIMARY KEY,"countId" TEXT NOT NULL REFERENCES "InventoryCount"("id") ON DELETE CASCADE,
 "productId" TEXT NOT NULL,"productVariantId" TEXT,"targetKey" TEXT NOT NULL,
 "productName" TEXT NOT NULL,"sku" TEXT,"unitMeasure" TEXT NOT NULL,
 "countedStockMil" INTEGER,"referenceStockMil" INTEGER NOT NULL,"expectedStockRevision" INTEGER NOT NULL,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "InventoryCountItem_quantity_check" CHECK ("countedStockMil" IS NULL OR "countedStockMil">=0)
);
CREATE UNIQUE INDEX "InventoryCountItem_countId_targetKey_key" ON "InventoryCountItem"("countId","targetKey");
CREATE TABLE "InventoryOperation" (
 "id" TEXT NOT NULL PRIMARY KEY,"companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE,
 "requestId" TEXT NOT NULL,"actorUserId" TEXT NOT NULL,"type" TEXT NOT NULL,"fingerprint" TEXT NOT NULL,
 "response" JSONB NOT NULL,"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX "InventoryOperation_companyId_requestId_key" ON "InventoryOperation"("companyId","requestId");
CREATE TABLE "InventoryAuditEvent" (
 "id" TEXT NOT NULL PRIMARY KEY,"companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE,
 "actorUserId" TEXT NOT NULL,"actorName" TEXT NOT NULL,"operation" TEXT NOT NULL,"entityId" TEXT NOT NULL,
 "before" JSONB,"after" JSONB,"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "InventoryAuditEvent_companyId_entityId_createdAt_idx" ON "InventoryAuditEvent"("companyId","entityId","createdAt");

-- Every writer, including older sale/purchase materializers, advances revision.
-- The ledger observes the committed mutation; it never changes quantity itself.
CREATE FUNCTION inventory_stock_revision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW."stockMil" IS DISTINCT FROM OLD."stockMil" OR NEW."minimumStockMil" IS DISTINCT FROM OLD."minimumStockMil" OR NEW."reorderPointMil" IS DISTINCT FROM OLD."reorderPointMil" THEN
  NEW."stockRevision" := OLD."stockRevision" + 1;
 ELSE NEW."stockRevision" := OLD."stockRevision";
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER "Product_stock_revision" BEFORE UPDATE ON "Product" FOR EACH ROW EXECUTE FUNCTION inventory_stock_revision();
CREATE TRIGGER "ProductVariant_stock_revision" BEFORE UPDATE ON "ProductVariant" FOR EACH ROW EXECUTE FUNCTION inventory_stock_revision();
CREATE FUNCTION inventory_stock_ledger() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p "Product"%ROWTYPE; before_stock INTEGER; delta INTEGER; variant_id TEXT; row_sku TEXT; movement_type TEXT;
BEGIN
 before_stock := CASE WHEN TG_OP='INSERT' THEN 0 ELSE OLD."stockMil" END;
 delta := NEW."stockMil" - before_stock;
 IF delta=0 THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='ProductVariant' THEN
  SELECT * INTO p FROM "Product" WHERE "id"=NEW."productId";
  variant_id:=NEW."id"; row_sku:=NEW."sku";
 ELSE
  SELECT * INTO p FROM "Product" WHERE "id"=NEW."id";
  IF current_setting('tatuzin.inventory_skip_parent',true)='true' OR EXISTS(SELECT 1 FROM "ProductVariant" WHERE "productId"=p."id") THEN RETURN NEW; END IF;
  variant_id:=NULL; row_sku:=p."barcode";
 END IF;
 movement_type:=COALESCE(NULLIF(current_setting('tatuzin.inventory_type',true),''), CASE WHEN TG_OP='INSERT' THEN 'INITIAL' ELSE 'STOCK_CHANGE' END);
 INSERT INTO "InventoryMovement"("companyId","productId","productVariantId","productName","sku","unitMeasure","quantityDeltaMil","stockBeforeMil","stockAfterMil","stockRevision","type","origin","referenceId","actorUserId","actorName","reason","notes","operationId")
 VALUES(p."companyId",p."id",variant_id,p."name",row_sku,p."unitMeasure",delta,before_stock,NEW."stockMil",NEW."stockRevision",movement_type,
 COALESCE(NULLIF(current_setting('tatuzin.inventory_origin',true),''),'legacy'),
 NULLIF(current_setting('tatuzin.inventory_reference',true),''),NULLIF(current_setting('tatuzin.inventory_actor',true),''),NULLIF(current_setting('tatuzin.inventory_actor_name',true),''),
 NULLIF(current_setting('tatuzin.inventory_reason',true),''),NULLIF(current_setting('tatuzin.inventory_notes',true),''),NULLIF(current_setting('tatuzin.inventory_operation',true),''));
 RETURN NEW;
END $$;
CREATE TRIGGER "Product_stock_ledger" AFTER INSERT OR UPDATE ON "Product" FOR EACH ROW EXECUTE FUNCTION inventory_stock_ledger();
CREATE TRIGGER "ProductVariant_stock_ledger" AFTER INSERT OR UPDATE ON "ProductVariant" FOR EACH ROW EXECUTE FUNCTION inventory_stock_ledger();
-- Append-only via normal writes. Cascades during explicit tenant lifecycle
-- deletion are allowed; that workflow retains its independent authorization.
CREATE FUNCTION inventory_immutable_record() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' AND pg_trigger_depth()>1 THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'Inventory history is immutable';
END $$;
CREATE TRIGGER "InventoryMovement_immutable" BEFORE UPDATE OR DELETE ON "InventoryMovement" FOR EACH ROW EXECUTE FUNCTION inventory_immutable_record();
CREATE TRIGGER "InventoryAuditEvent_immutable" BEFORE UPDATE OR DELETE ON "InventoryAuditEvent" FOR EACH ROW EXECUTE FUNCTION inventory_immutable_record();
