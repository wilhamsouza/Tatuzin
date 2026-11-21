import { Router, type Request, type RequestHandler } from 'express';
import { requireAppContext } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { AppError } from '../../shared/http/app-error';
import { validateBody, validateQuery } from '../../shared/http/validate';
import { requireFeature } from '../../shared/http/feature-middleware';
import { requireAnyEmployeePermission, requireEmployeePermission } from '../employees/employee-permission-middleware';
import { hasEmployeePermission, roleFromMembershipRole } from '../employees/employee-permissions';
import { canViewSensitiveProductData } from '../products/product-access';
import * as schemas from './inventory.schemas';
import { InventoryService } from './inventory.service';
import { InventoryWorkspaceService } from './inventory-workspace.service';

const inventoryService = new InventoryService();
const workspace = new InventoryWorkspaceService();
export const inventoryRouter = Router();
export function inventoryWorkspaceEnabled(companyId: string) {
  const ids = (process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS ?? '').split(',').map(s => s.trim()).filter(Boolean);
  return ids.includes('*') || ids.includes(companyId);
}
const pilot: RequestHandler = (req, _res, next) => inventoryWorkspaceEnabled(req.auth!.companyId) ? next() : next(new AppError('A nova operação de estoque ainda não está habilitada nesta empresa.',403,'INVENTORY_WORKSPACE_DISABLED'));
const actor = (req: Request) => ({ id: req.appContext!.user.id, name: req.appContext!.user.name, role: req.appContext!.employee?.role ?? roleFromMembershipRole(req.appContext!.membership.role) });
const id = (req: Request) => String(req.params.id);
const productId = (req: Request) => String(req.params.productId);
function redact<T extends object>(req: Request, value: T): T {
  if (canViewSensitiveProductData(req.appContext!)) return value;
  const visit = (v: unknown): unknown => Array.isArray(v) ? v.map(visit) : v && typeof v === 'object' && !(v instanceof Date) ? Object.fromEntries(Object.entries(v).filter(([key]) => !['costCents','costPriceCents','inventoryCostValueCents'].includes(key)).map(([key, val]) => [key,visit(val)])) : v;
  return visit(value) as T;
}

inventoryRouter.get('/health', (_req, res) => res.json({ok:true,feature:'inventory',timestamp:new Date().toISOString()}));
inventoryRouter.use(requireAppContext);
inventoryRouter.get('/capabilities', (req,res) => {
  const context=req.appContext!; const enabled=inventoryWorkspaceEnabled(context.company.id);
  const permission=(key:'products.read'|'products.write'|'stock.adjust'|'reports.advanced')=>hasEmployeePermission(context.membership.permissions,key);
  const canRead=permission('stock.adjust')||permission('reports.advanced');
  res.json({enabled,canRead,canAdjust:enabled&&permission('stock.adjust')&&context.features.inventoryAdvanced,canCount:enabled&&permission('stock.adjust')&&context.features.inventoryAdvanced,canInitializeStock:enabled&&permission('products.write')&&permission('stock.adjust')&&context.features.inventoryBasic,canWriteProducts:permission('products.write'),canReadProducts:permission('products.read')||permission('products.write'),canViewCosts:canViewSensitiveProductData(context),canTransferCounts:['OWNER','MANAGER'].includes(actor(req).role),onlineConfirmationRequired:true});
});
inventoryRouter.use(requireAnyEmployeePermission(['stock.adjust','reports.advanced']));
inventoryRouter.get('/summary',validateQuery(schemas.inventorySummaryQuerySchema),asyncHandler(async(req,res)=>res.json(redact(req,{summary:await inventoryService.summaryForCompany(req.auth!.companyId)}))));
inventoryRouter.get('/',validateQuery(schemas.inventoryListQuerySchema),asyncHandler(async(req,res)=>{
  const query=req.query as unknown as schemas.InventoryListQueryInput;
  const result=await inventoryService.listForCompany(req.auth!.companyId,query);
  res.json(redact(req,{items:result.items,pagination:{page:query.page,pageSize:query.pageSize,total:result.total,totalPages:Math.ceil(result.total/query.pageSize)},updatedAt:new Date().toISOString(),source:'server'}));
}));
inventoryRouter.get('/items/:productId',validateQuery(schemas.inventoryTargetQuerySchema),asyncHandler(async(req,res)=>res.json(redact(req,{item:await workspace.item(req.auth!.companyId,productId(req),req.query.productVariantId as string|undefined)}))));
const settingsHandlers=[pilot,requireFeature('inventoryAdvanced'),requireEmployeePermission('stock.adjust'),validateQuery(schemas.inventoryTargetQuerySchema),validateBody(schemas.inventorySettingsSchema),asyncHandler(async(req,res)=>res.json(await workspace.settings(req.auth!.companyId,actor(req),productId(req),(req.query.productVariantId as string|undefined)??null,req.body)))];
inventoryRouter.patch('/items/:productId',...settingsHandlers);
inventoryRouter.patch('/items/:productId/settings',...settingsHandlers);
inventoryRouter.get('/movements',validateQuery(schemas.inventoryMovementsQuerySchema),asyncHandler(async(req,res)=>res.json(await workspace.movements(req.auth!.companyId,req.query as unknown as schemas.InventoryMovementsQuery))));
inventoryRouter.post('/initial-balances',pilot,requireFeature('inventoryBasic'),requireEmployeePermission('products.write'),requireEmployeePermission('stock.adjust'),validateBody(schemas.inventoryAdjustmentSchema.refine(input=>input.quantityDeltaMil>0,{message:'O saldo inicial deve ser positivo.',path:['quantityDeltaMil']})),asyncHandler(async(req,res)=>res.json(await workspace.adjust(req.auth!.companyId,actor(req),req.body,true))));
inventoryRouter.post('/adjustments',pilot,requireFeature('inventoryAdvanced'),requireEmployeePermission('stock.adjust'),validateBody(schemas.inventoryAdjustmentSchema),asyncHandler(async(req,res)=>res.json(await workspace.adjust(req.auth!.companyId,actor(req),req.body))));
inventoryRouter.get('/count-assignees',pilot,requireFeature('inventoryAdvanced'),asyncHandler(async(req,res)=>res.json(await workspace.assignees(req.auth!.companyId))));
inventoryRouter.get('/counts',pilot,requireFeature('inventoryAdvanced'),validateQuery(schemas.inventoryCountListSchema),asyncHandler(async(req,res)=>res.json(await workspace.counts(req.auth!.companyId,req.query as unknown as schemas.InventoryCountListQuery))));
inventoryRouter.post('/counts',pilot,requireFeature('inventoryAdvanced'),requireEmployeePermission('stock.adjust'),validateBody(schemas.inventoryCountCreateSchema),asyncHandler(async(req,res)=>res.status(201).json(await workspace.createCount(req.auth!.companyId,actor(req),req.body))));
inventoryRouter.get('/counts/:id',pilot,requireFeature('inventoryAdvanced'),asyncHandler(async(req,res)=>res.json(await workspace.detail(req.auth!.companyId,id(req)))));
inventoryRouter.patch('/counts/:id',pilot,requireFeature('inventoryAdvanced'),requireEmployeePermission('stock.adjust'),validateBody(schemas.inventoryCountUpdateSchema),asyncHandler(async(req,res)=>res.json(await workspace.updateCount(req.auth!.companyId,actor(req),id(req),req.body))));
inventoryRouter.put('/counts/:id/items',pilot,requireFeature('inventoryAdvanced'),requireEmployeePermission('stock.adjust'),validateBody(schemas.inventoryCountItemsSchema),asyncHandler(async(req,res)=>res.json(await workspace.putCountItems(req.auth!.companyId,actor(req),id(req),req.body))));
for(const action of ['review','apply','cancel'] as const) inventoryRouter.post('/counts/:id/'+action,pilot,requireFeature('inventoryAdvanced'),requireEmployeePermission('stock.adjust'),validateBody(schemas.inventoryCountActionSchema),asyncHandler(async(req,res)=>res.json(await workspace.countAction(req.auth!.companyId,actor(req),id(req),action,req.body))));
