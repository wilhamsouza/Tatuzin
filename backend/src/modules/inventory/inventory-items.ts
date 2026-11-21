import { Prisma } from '@prisma/client';

export type WorkspaceItem = {
  id: string; productId: string; productVariantId: string | null; name: string;
  productName: string; variantName: string | null; sku: string | null;
  unitMeasure: string; currentStockMil: number; minimumStockMil: number;
  reorderPointMil: number | null; stockRevision: number;
  costPriceCents: number; costCents: number; salePriceCents: number;
  isActive: boolean; updatedAt: Date; reservedStockMil: number; availableStockMil: number;
  status: 'active' | 'zeroed' | 'belowMinimum' | 'inactive';
};
// One row per operational SKU. Aggregate Product.stockMil is not another SKU.
export function inventoryItemsSql(companyId: string) {
  return Prisma.sql`WITH raw_items AS (
    SELECT p.id AS "productId", NULL::text AS "productVariantId", p.name,
      NULL::text AS "variantName", p.barcode AS sku, p."unitMeasure", p."stockMil" AS "currentStockMil",
      p."minimumStockMil", p."reorderPointMil", p."stockRevision", p."costPriceCents", p."salePriceCents", p."isActive", p."updatedAt"
    FROM "Product" p WHERE p."companyId"=${companyId} AND p."deletedAt" IS NULL
      AND NOT EXISTS(SELECT 1 FROM "ProductVariant" v WHERE v."productId"=p.id)
    UNION ALL
    SELECT p.id, v.id, p.name, concat_ws(' / ',NULLIF(v."colorLabel",''),NULLIF(v."sizeLabel",'')),
      COALESCE(NULLIF(v.sku,''),p.barcode),p."unitMeasure",v."stockMil",v."minimumStockMil",v."reorderPointMil",v."stockRevision",
      p."costPriceCents", p."salePriceCents"+v."priceAdditionalCents",p."isActive" AND v."isActive",GREATEST(p."updatedAt",v."updatedAt")
    FROM "ProductVariant" v JOIN "Product" p ON p.id=v."productId"
    WHERE p."companyId"=${companyId} AND p."deletedAt" IS NULL
  ), reservations AS (
    SELECT "productId","productVariantId",SUM("quantityMil")::integer AS reserved
    FROM "StockReservation" WHERE "companyId"=${companyId} AND status='active'
    GROUP BY "productId","productVariantId"
  ), items AS (
    SELECT COALESCE(i."productVariantId",i."productId") AS id,i.*,i.name AS "productName",i."costPriceCents" AS "costCents",
      COALESCE(r.reserved,0) AS "reservedStockMil",i."currentStockMil"-COALESCE(r.reserved,0) AS "availableStockMil",
      CASE WHEN NOT i."isActive" THEN 'inactive' WHEN i."currentStockMil"<=0 THEN 'zeroed'
        WHEN i."minimumStockMil">0 AND i."currentStockMil"<i."minimumStockMil" THEN 'belowMinimum' ELSE 'active' END AS status
    FROM raw_items i LEFT JOIN reservations r ON r."productId"=i."productId" AND r."productVariantId" IS NOT DISTINCT FROM i."productVariantId"
  )`;
}
