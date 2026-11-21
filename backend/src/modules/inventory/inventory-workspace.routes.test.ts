import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, it } from 'node:test';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import jwt from 'jsonwebtoken';
import { createApp } from '../../app';
import { prisma } from '../../database/prisma';
import { env } from '../../config/env';
import { setInventoryContext } from './inventory-context';

const runId='inventory-workspace-'+randomUUID();
let server:Server;let base:string;let priorPilot:string|undefined;
type Payload=Record<string,any>;
async function request(method:string,path:string,token:string,body?:unknown) {
  const res=await fetch(base+path,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
  return {status:res.status,data:await res.json() as Payload};
}
async function fixture(role='OWNER',permissions?:string[],plan='PRO') {
  const company=await prisma.company.create({data:{name:'Estoque de teste',legalName:'Estoque Teste',slug:runId+'-'+randomUUID()}});
  await prisma.license.create({data:{companyId:company.id,plan,status:'ACTIVE',startsAt:new Date(),syncEnabled:true,expiresAt:new Date(Date.now()+86400000*30)}});
  const identity=await member(company.id,role,permissions);
  const product=await prisma.product.create({data:{companyId:company.id,localUuid:randomUUID(),name:'Camiseta de teste',barcode:randomUUID(),salePriceCents:5000,costPriceCents:2000,stockMil:5000}});
  return {company,product,...identity};
}
async function member(companyId:string,role='OWNER',permissions?:string[]) {
  const user=await prisma.user.create({data:{email:runId+'-'+randomUUID()+'@test.invalid',name:role+' Teste',passwordHash:'test-only'}});
  const membership=await prisma.membership.create({data:{companyId,userId:user.id,role:role==='OWNER'?'OWNER':role==='MANAGER'?'ADMIN':'OPERATOR'}});
  if(role!=='OWNER') await prisma.employeeProfile.create({data:{companyId,userId:user.id,membershipId:membership.id,name:user.name,role,status:'ACTIVE',...(permissions?{permissions}: {})}});
  const clientInstanceId=runId+'-'+randomUUID();
  await prisma.companyDevice.create({data:{companyId,userId:user.id,clientInstanceId,status:'ACTIVE',approvedAt:new Date(),platform:'test',appVersion:'inventory-workspace-test'}});
  const token=jwt.sign({sub:user.id,companyId,membershipId:membership.id,membershipRole:membership.role,email:user.email,isPlatformAdmin:false,clientInstanceId},env.JWT_SECRET,{expiresIn:'15m'});
  return {user,token};
}
const key=()=>randomUUID();

describe('inventory workspace transactional contracts',()=>{
  before(async()=>{
    await prisma.$connect();priorPilot=process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS;process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS='*';
    server=createApp().listen(0);base='http://127.0.0.1:'+(server.address() as AddressInfo).port+'/api/inventory';
  });
  after(async()=>{
    if(priorPilot===undefined)delete process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS;else process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS=priorPilot;
    await prisma.company.deleteMany({where:{slug:{startsWith:runId}}});
    await prisma.user.deleteMany({where:{email:{startsWith:runId}}});
    await new Promise<void>((resolve,reject)=>server.close(e=>e?reject(e):resolve()));await prisma.$disconnect();
  });

  it('adjusts once under concurrent retry, audits and rejects changed payload/revision',async()=>{
    const f=await fixture();
    const input={requestId:key(),productId:f.product.id,expectedRevision:0,quantityDeltaMil:-1000,reason:'Avaria identificada'};
    const [a,b]=await Promise.all([request('POST','/adjustments',f.token,input),request('POST','/adjustments',f.token,input)]);
    assert.equal(a.status,200,JSON.stringify(a.data));assert.equal(b.status,200,JSON.stringify(b.data));assert.deepEqual(a.data,b.data);
    assert.equal(a.data.item.currentStockMil,4000);assert.equal(a.data.item.stockRevision,1);assert.equal(a.data.movement.actorUserId,f.user.id);
    assert.equal(await prisma.inventoryMovement.count({where:{companyId:f.company.id,origin:'manual_adjustment'}}),1);
    assert.equal(await prisma.inventoryAuditEvent.count({where:{companyId:f.company.id,operation:'ADJUST'}}),1);
    assert.equal((await request('POST','/adjustments',f.token,{...input,quantityDeltaMil:-2000})).status,409);
    const stale=await request('POST','/adjustments',f.token,{...input,requestId:key()});assert.equal(stale.status,409);assert.equal(stale.data.code,'INVENTORY_STOCK_REVISION_CONFLICT');
    assert.equal((await request('POST','/adjustments',f.token,{...input,requestId:key(),expectedRevision:1,quantityDeltaMil:-5000})).status,422);
    assert.equal((await prisma.product.findUniqueOrThrow({where:{id:f.product.id}})).stockMil,4000);
  });

  it('requires all count items, detects stock changes, applies once and freezes history',async()=>{
    const f=await fixture();
    const created=await request('POST','/counts',f.token,{requestId:key(),name:'Conferência semanal',productIds:[f.product.id]});
    assert.equal(created.status,201,JSON.stringify(created.data));const id=created.data.session.id;
    assert.equal(created.data.items[0].countedStockMil,null);
    assert.equal((await request('POST','/counts/'+id+'/review',f.token,{requestId:key(),expectedRevision:0})).status,422);
    let changed=await request('PUT','/counts/'+id+'/items',f.token,{expectedRevision:0,items:[{productId:f.product.id,countedStockMil:3000,expectedStockRevision:0}]});
    assert.equal(changed.status,200,JSON.stringify(changed.data));assert.equal(changed.data.session.revision,1);
    assert.equal((await request('PUT','/counts/'+id+'/items',f.token,{expectedRevision:0,items:[{productId:f.product.id,countedStockMil:1000,expectedStockRevision:0}]})).status,409);
    assert.equal((await request('POST','/counts/'+id+'/review',f.token,{requestId:key(),expectedRevision:1})).status,200);
    await prisma.product.update({where:{id:f.product.id},data:{stockMil:{decrement:1000}}});
    const detail=await request('GET','/counts/'+id,f.token);assert.equal(detail.data.items[0].isStale,true);
    const blocked=await request('POST','/counts/'+id+'/apply',f.token,{requestId:key(),expectedRevision:2});assert.equal(blocked.status,409);assert.equal(blocked.data.code,'INVENTORY_STOCK_REVISION_CONFLICT');
    assert.equal((await prisma.product.findUniqueOrThrow({where:{id:f.product.id}})).stockMil,4000);
    changed=await request('PUT','/counts/'+id+'/items',f.token,{expectedRevision:2,items:[{productId:f.product.id,countedStockMil:3000,expectedStockRevision:1}]});assert.equal(changed.status,200);
    assert.equal((await request('POST','/counts/'+id+'/review',f.token,{requestId:key(),expectedRevision:3})).status,200);
    const input={requestId:key(),expectedRevision:4};
    const first=await request('POST','/counts/'+id+'/apply',f.token,input);const retried=await request('POST','/counts/'+id+'/apply',f.token,input);
    assert.equal(first.status,200,JSON.stringify(first.data));assert.deepEqual(first.data,retried.data);assert.equal(first.data.session.status,'APPLIED');assert.equal(first.data.items[0].isStale,false);
    assert.equal((await prisma.product.findUniqueOrThrow({where:{id:f.product.id}})).stockMil,3000);
    assert.equal(await prisma.inventoryMovement.count({where:{companyId:f.company.id,referenceId:id,origin:'inventory_count'}}),1);
    assert.equal((await request('PUT','/counts/'+id+'/items',f.token,{expectedRevision:5,items:[{productId:f.product.id,countedStockMil:0,expectedStockRevision:2}]})).status,409);
  });

  it('supports explicit removal, zero counts and preserves cancel history',async()=>{
    const f=await fixture();let r=await request('POST','/counts',f.token,{requestId:key(),name:'Zero',productIds:[f.product.id]});const id=r.data.session.id;
    r=await request('PUT','/counts/'+id+'/items',f.token,{expectedRevision:0,items:[{productId:f.product.id,remove:true}]});assert.equal(r.status,200,JSON.stringify(r.data));assert.equal(r.data.items.length,0);
    r=await request('PUT','/counts/'+id+'/items',f.token,{expectedRevision:1,items:[{productId:f.product.id,countedStockMil:0,expectedStockRevision:0}]});assert.equal(r.data.items[0].countedStockMil,0);
    const cancel={requestId:key(),expectedRevision:2};r=await request('POST','/counts/'+id+'/cancel',f.token,cancel);assert.equal(r.status,200);assert.equal(r.data.session.status,'CANCELED');assert.equal(r.data.items.length,1);
    assert.deepEqual((await request('POST','/counts/'+id+'/cancel',f.token,cancel)).data,r.data);
    assert.equal((await prisma.product.findUniqueOrThrow({where:{id:f.product.id}})).stockMil,5000);
  });

  it('isolates company items, movements and counts and rejects companyId input',async()=>{
    const a=await fixture(),b=await fixture();
    const created=await request('POST','/counts',a.token,{requestId:key(),name:'Empresa A'});
    assert.equal((await request('GET','/counts/'+created.data.session.id,b.token)).status,404);
    assert.equal((await request('GET','/items/'+a.product.id,b.token)).status,404);
    assert.equal((await request('POST','/adjustments',b.token,{requestId:key(),productId:a.product.id,expectedRevision:0,quantityDeltaMil:1000,reason:'Teste de isolamento'})).status,404);
    assert.equal((await request('GET','/?companyId='+a.company.id,b.token)).status,422);
    const movements=await request('GET','/movements?productId='+a.product.id,b.token);assert.equal(movements.data.items.length,0);
  });

  it('enforces read/write grants, advanced plan and pilot in backend',async()=>{
    const f=await fixture('READ_ONLY',['reports.advanced']);const cap=await request('GET','/capabilities',f.token);assert.equal(cap.status,200);assert.equal(cap.data.canRead,true);assert.equal(cap.data.canAdjust,false);assert.equal(cap.data.canWriteProducts,false);
    assert.equal((await request('GET','/',f.token)).status,200);
    assert.equal((await request('POST','/counts',f.token,{requestId:key(),name:'Não autorizado'})).status,403);
    const catalog=await fixture('READ_ONLY',['products.read']);assert.equal((await request('GET','/',catalog.token)).status,403);assert.equal((await request('GET','/capabilities',catalog.token)).data.canReadProducts,true);
    const free=await fixture('OWNER',undefined,'FREE');assert.equal((await request('POST','/counts',free.token,{requestId:key(),name:'Plano gratuito'})).status,403);
    const basic=await fixture('OWNER',undefined,'BASIC');assert.equal((await request('POST','/counts',basic.token,{requestId:key(),name:'Plano básico'})).status,201);
    process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS='';
    try {assert.equal((await request('POST','/adjustments',f.token,{requestId:key(),productId:f.product.id,expectedRevision:0,quantityDeltaMil:1000,reason:'Piloto desligado'})).status,403);assert.equal((await request('GET','/capabilities',f.token)).data.enabled,false);}
    finally {process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS='*';}
  });

  it('transfers only to eligible company users and rejects former owner writes',async()=>{
    const f=await fixture();const operator=await member(f.company.id,'STOCK_OPERATOR');const viewer=await member(f.company.id,'READ_ONLY');
    const choices=await request('GET','/count-assignees',f.token);assert.equal(choices.status,200,JSON.stringify(choices.data));assert(choices.data.items.some((r:Payload)=>r.userId===operator.user.id));assert(!choices.data.items.some((r:Payload)=>r.userId===viewer.user.id));
    const create=await request('POST','/counts',f.token,{requestId:key(),name:'Transferência'});const id=create.data.session.id;
    assert.equal((await request('PATCH','/counts/'+id,f.token,{expectedRevision:0,assigneeUserId:viewer.user.id})).status,422);
    const transferred=await request('PATCH','/counts/'+id,f.token,{expectedRevision:0,assigneeUserId:operator.user.id});assert.equal(transferred.status,200,JSON.stringify(transferred.data));
    assert.equal((await request('PATCH','/counts/'+id,f.token,{expectedRevision:1,name:'Mudança antiga'})).status,403);
    assert.equal((await request('PATCH','/counts/'+id,operator.token,{expectedRevision:1,name:'Responsável atual'})).status,200);
    assert.equal((await request('PATCH','/counts/'+id,operator.token,{expectedRevision:2,assigneeUserId:f.user.id})).status,403);
    assert.equal(await prisma.inventoryAuditEvent.count({where:{companyId:f.company.id,entityId:id,operation:'COUNT_UPDATE'}}),2);
  });

  it('records variant mutations once, skips aggregate parent and keeps flat legacy SKUs',async()=>{
    const f=await fixture();
    const parent=await prisma.product.create({data:{companyId:f.company.id,localUuid:key(),name:'Modelo',catalogType:'variant',salePriceCents:1000}});
    const variant=await prisma.productVariant.create({data:{productId:parent.id,sku:key(),colorLabel:'Preto',sizeLabel:'M',stockMil:2000}});
    const r=await request('POST','/adjustments',f.token,{requestId:key(),productId:parent.id,productVariantId:variant.id,expectedRevision:0,quantityDeltaMil:1000,reason:'Reposição manual'});
    assert.equal(r.status,200,JSON.stringify(r.data));assert.equal(r.data.item.currentStockMil,3000);
    assert.equal((await prisma.product.findUniqueOrThrow({where:{id:parent.id}})).stockMil,3000);
    assert.equal(await prisma.inventoryMovement.count({where:{companyId:f.company.id,origin:'manual_adjustment',productId:parent.id}}),1);
    assert.equal((await prisma.productVariant.findUniqueOrThrow({where:{id:variant.id}})).stockRevision,1);
    const flat=await prisma.product.create({data:{companyId:f.company.id,localUuid:key(),name:'SKU legado',catalogType:'variant',modelName:'Legado',variantLabel:'M',salePriceCents:1000,stockMil:2000}});
    await prisma.$transaction(async tx=>{await setInventoryContext(tx,{actorUserId:f.user.id,type:'SALE_OUT',origin:'sync:stockDeduction',referenceId:'sale-test'});await tx.product.update({where:{id:flat.id},data:{stockMil:{decrement:1000}}});});
    const history=await request('GET','/movements?productId='+flat.id,f.token);assert.equal(history.status,200);const sale=history.data.items.find((m:Payload)=>m.type==='SALE_OUT');assert(sale);assert.equal(sale.responsibleName,f.user.name);assert.equal(sale.actorName,f.user.name);
    await assert.rejects(prisma.inventoryMovement.update({where:{id:sale.id},data:{notes:'Reescrever histórico'}}),/immutable/);
  });

  it('initializes FREE items once without opening generic advanced adjustments',async()=>{
    const f=await fixture('OWNER',undefined,'FREE');
    const product=await prisma.product.create({data:{companyId:f.company.id,localUuid:key(),name:'Produto novo',salePriceCents:1000,stockMil:0}});
    const cap=await request('GET','/capabilities',f.token);assert.equal(cap.data.canInitializeStock,true);assert.equal(cap.data.canAdjust,false);
    const input={requestId:key(),productId:product.id,expectedRevision:0,quantityDeltaMil:3000,reason:'Saldo inicial conferido'};
    const first=await request('POST','/initial-balances',f.token,input);assert.equal(first.status,200,JSON.stringify(first.data));assert.equal(first.data.item.currentStockMil,3000);
    assert.deepEqual((await request('POST','/initial-balances',f.token,input)).data,first.data);
    assert.equal(await prisma.inventoryMovement.count({where:{companyId:f.company.id,origin:'initial_balance',productId:product.id}}),1);
    assert.equal((await request('POST','/initial-balances',f.token,{...input,requestId:key(),expectedRevision:1})).status,409);
    assert.equal((await request('POST','/initial-balances',f.token,{...input,requestId:key(),productId:f.product.id})).status,409);
    assert.equal((await request('POST','/adjustments',f.token,{...input,requestId:key(),expectedRevision:1})).status,403);
    const reserved=await prisma.product.create({data:{companyId:f.company.id,localUuid:key(),name:'Produto reservado',salePriceCents:1000}});
    await prisma.stockReservation.create({data:{companyId:f.company.id,productId:reserved.id,quantityMil:1000,localUuid:key(),status:'active'}});
    assert.equal((await request('POST','/initial-balances',f.token,{...input,requestId:key(),productId:reserved.id})).status,409);
    const changed=await prisma.product.create({data:{companyId:f.company.id,localUuid:key(),name:'Produto já configurado',salePriceCents:1000}});
    await prisma.product.update({where:{id:changed.id},data:{minimumStockMil:1000}});
    assert.equal((await request('POST','/initial-balances',f.token,{...input,requestId:key(),productId:changed.id,expectedRevision:1})).status,409);
  });

  it('persists minimums with revision and filters server pages by product',async()=>{
    const f=await fixture();const r=await request('PATCH','/items/'+f.product.id+'/settings',f.token,{expectedRevision:0,minimumStockMil:6000,reorderPointMil:8000});assert.equal(r.status,200,JSON.stringify(r.data));assert.equal(r.data.item.stockRevision,1);assert.equal(r.data.item.status,'belowMinimum');
    const filtered=await request('GET','/?filter=belowMinimum&productId='+f.product.id+'&pageSize=1',f.token);assert.equal(filtered.status,200);assert.equal(filtered.data.pagination.total,1);assert.equal(filtered.data.items[0].minimumStockMil,6000);
    assert.equal((await request('PATCH','/items/'+f.product.id+'/settings',f.token,{expectedRevision:0,minimumStockMil:1000})).status,409);
    await prisma.stockReservation.create({data:{companyId:f.company.id,productId:f.product.id,quantityMil:2000,localUuid:key(),status:'active'}});
    const detail=await request('GET','/items/'+f.product.id,f.token);assert.equal(detail.data.item.reservedStockMil,2000);assert.equal(detail.data.item.availableStockMil,3000);
  });
});
