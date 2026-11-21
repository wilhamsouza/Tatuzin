import { Prisma } from '@prisma/client';
import { prisma } from '../../database/prisma';
import { toPaginationParams } from '../../shared/http/pagination';
import type { InventoryListQueryInput } from './inventory.schemas';
import { inventoryItemsSql, type WorkspaceItem } from './inventory-items';

export class InventoryService {
  async listForCompany(companyId: string, query: InventoryListQueryInput) {
    const {skip,take}=toPaginationParams(query);
    const search=query.query.trim();
    const where=Prisma.sql`WHERE (${query.filter}='all' OR status=${query.filter}) AND (${query.productId??null}::text IS NULL OR "productId"=${query.productId??null}) AND (${query.productVariantId??null}::text IS NULL OR "productVariantId"=${query.productVariantId??null}) AND (${search}='' OR concat_ws(' ',name,"variantName",sku,"unitMeasure") ILIKE ${'%'+search+'%'})`;
    const [items, count] = await prisma.$transaction([
      prisma.$queryRaw<WorkspaceItem[]>`${inventoryItemsSql(companyId)} SELECT * FROM items ${where} ORDER BY name,"productId","productVariantId" NULLS FIRST LIMIT ${take} OFFSET ${skip}`,
      prisma.$queryRaw<Array<{total:number}>>`${inventoryItemsSql(companyId)} SELECT COUNT(*)::integer AS total FROM items ${where}`,
    ]);
    return {items,total:count[0]?.total ?? 0};
  }

  async summaryForCompany(companyId: string) {
    const [summary]=await prisma.$queryRaw<Array<Record<string,number>>>`${inventoryItemsSql(companyId)} SELECT
      COUNT(*)::integer AS "totalItemsCount",
      COUNT(*) FILTER(WHERE status='active')::integer AS "activeItemsCount",
      COUNT(*) FILTER(WHERE status='zeroed')::integer AS "zeroedItemsCount",
      COUNT(*) FILTER(WHERE status='belowMinimum')::integer AS "belowMinimumItemsCount",
      COALESCE(SUM(ROUND("currentStockMil"::numeric*"costPriceCents"/1000)),0)::double precision AS "inventoryCostValueCents",
      COALESCE(SUM(ROUND("currentStockMil"::numeric*"salePriceCents"/1000)),0)::double precision AS "inventorySaleValueCents"
      FROM items`;
    return {...summary, divergenceItemsCount:null, updatedAt:new Date().toISOString(), source:'server'};
  }
}
