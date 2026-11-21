import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import jwt from 'jsonwebtoken';
import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const prefix = 'owner-stock-pilot-' + randomUUID();
let server: Server;
let base: string;
let originalPilot: string | undefined;
type Json = Record<string, any>;

async function tenant() {
  const company = await prisma.company.create({data:{name:'Owner stock fixture',legalName:'Owner stock fixture',slug:prefix+'-'+randomUUID()}});
  const user = await prisma.user.create({data:{email:prefix+'-'+randomUUID()+'@test.invalid',name:'Stock owner',passwordHash:'isolated-test-only'}});
  const membership = await prisma.membership.create({data:{companyId:company.id,userId:user.id,role:'OWNER'}});
  await prisma.license.create({data:{companyId:company.id,plan:'PRO',status:'ACTIVE',startsAt:new Date(),expiresAt:new Date(Date.now()+86400000*30),syncEnabled:true}});
  const clientInstanceId = randomUUID();
  await prisma.companyDevice.create({data:{companyId:company.id,userId:user.id,clientInstanceId,status:'ACTIVE',approvedAt:new Date(),platform:'test',appVersion:'owner-stock-pilot-test'}});
  const token = jwt.sign({sub:user.id,companyId:company.id,membershipId:membership.id,membershipRole:'OWNER',email:user.email,isPlatformAdmin:false,clientInstanceId},env.JWT_SECRET,{expiresIn:'15m'});
  return {companyId:company.id,token};
}

function product(companyId:string,name:string,stockMil:number,minimumStockMil=0,costPriceCents=1000,unitMeasure='un',isActive=true) {
  return prisma.product.create({data:{companyId,localUuid:randomUUID(),name,stockMil,minimumStockMil,costPriceCents,salePriceCents:5000,unitMeasure,isActive}});
}
async function dataset(companyId:string) {
  const low = await product(companyId,'Abaixo do mínimo',5000,7000,1000);
  const noMinimum = await product(companyId,'Sem mínimo configurado',500,0,2000);
  const equal = await product(companyId,'No mínimo exato',1000,1000,500);
  const zero = await product(companyId,'Sem saldo',0,1000,400);
  const weight = await product(companyId,'Produto por peso',750,1000,2000,'kg');
  const parent = await product(companyId,'Modelo com grade',50000,90000,300);
  const variant = await prisma.productVariant.create({data:{productId:parent.id,sku:randomUUID(),colorLabel:'Preto',sizeLabel:'M',stockMil:2000,minimumStockMil:3000}});
  await prisma.productVariant.create({data:{productId:parent.id,sku:randomUUID(),colorLabel:'Branco',sizeLabel:'G',stockMil:0,minimumStockMil:5000,isActive:false}});
  await product(companyId,'Produto inativo',0,1000,90000,'un',false);
  return {low,noMinimum,equal,zero,weight,parent,variant};
}
async function get(path:string,token:string) {
  const response=await fetch(base+path,{headers:{Authorization:'Bearer '+token}});
  const body=await response.json() as Json;
  assert.equal(response.status,200,`${path}: ${response.status} ${body.code??''}`);
  return body;
}

describe('owner stock pilot uses configured operational SKU minimums',()=>{
  before(async()=>{
    await prisma.$connect();originalPilot=process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS;
    server=createApp().listen(0);base='http://127.0.0.1:'+(server.address() as AddressInfo).port+'/api';
  });
  after(async()=>{
    if(originalPilot===undefined)delete process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS;else process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS=originalPilot;
    await prisma.company.deleteMany({where:{slug:{startsWith:prefix}}});
    await prisma.user.deleteMany({where:{email:{startsWith:prefix}}});
    await new Promise<void>((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
    await prisma.$disconnect();
  });

  it('aligns pilot summary, dashboard and products report with central SKU alerts',async()=>{
    const f=await tenant();const items=await dataset(f.companyId);
    process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS='  '+f.companyId+' , ';
    const [summary,central,dashboard,report]=await Promise.all([
      get('/owner/stock/summary?limit=10',f.token),
      get('/inventory?filter=belowMinimum&pageSize=100',f.token),
      get('/owner/dashboard/business',f.token),
      get('/owner/reports/products?limit=10',f.token),
    ]);
    assert.equal(summary.lowStockThresholdMil,null);
    assert.equal(summary.lowStockRule,'per_item_minimum');
    assert.equal(summary.totalProducts,6); // Active operational SKUs, never aggregate parent.
    assert.equal(summary.lowStockCount,3);
    assert.equal(summary.outOfStockCount,1);
    assert.deepEqual(new Set(summary.itemsLowStock.map((r:Json)=>r.id)),new Set([items.low.id,items.weight.id,items.variant.id]));
    assert.deepEqual(new Set(summary.itemsLowStock.map((r:Json)=>r.id)),new Set(central.items.map((r:Json)=>r.id)));
    assert.equal(summary.lowStockCount,central.pagination.total);
    assert.equal(summary.itemsLowStock.find((r:Json)=>r.id===items.weight.id).unitMeasure,'kg');
    assert.equal(summary.itemsLowStock.find((r:Json)=>r.id===items.variant.id).minimumStockMil,3000);
    assert.equal(summary.totalEstimatedCostCents,8600); // Existing cents-per-unit math, including 0.750 kg.
    assert.equal(summary.itemsOutOfStock[0].id,items.zero.id);
    assert.equal(dashboard.products.total,summary.totalProducts);
    assert.equal(dashboard.products.lowStock,summary.lowStockCount);
    assert.equal(dashboard.products.outOfStock,summary.outOfStockCount);
    assert.deepEqual(report.stockSummary,{totalProducts:6,lowStockCount:3,outOfStockCount:1,totalEstimatedCostCents:8600});
    const limited=await get('/owner/stock/summary?limit=2',f.token);
    assert.equal(limited.lowStockCount,3);assert.equal(limited.itemsLowStock.length,2);
    assert.equal(limited.totalEstimatedCostCents,8600);
  });

  it('treats zero minimum as unconfigured and exact minimum as sufficient under wildcard pilot',async()=>{
    const f=await tenant();
    await product(f.companyId,'Pouco saldo sem mínimo',500,0);
    await product(f.companyId,'No mínimo',1000,1000);
    const zero=await product(f.companyId,'Zero com mínimo',0,5000);
    await product(f.companyId,'Inativo',0,5000,1000,'un',false);
    process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS=' * ';
    const summary=await get('/owner/stock/summary?limit=10',f.token);
    assert.equal(summary.totalProducts,3);assert.equal(summary.lowStockCount,0);
    assert.equal(summary.outOfStockCount,1);assert.equal(summary.itemsOutOfStock[0].id,zero.id);
    assert.deepEqual(summary.itemsLowStock,[]);assert.equal(summary.lowStockThresholdMil,null);
    const central=await get('/inventory?filter=belowMinimum',f.token);assert.equal(central.pagination.total,0);
  });

  it('preserves legacy definitions outside the company allowlist and when pilot is off',async()=>{
    const f=await tenant();const rows=await dataset(f.companyId);
    process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS=randomUUID();
    const summary=await get('/owner/stock/summary?limit=10',f.token);
    assert.equal(summary.lowStockThresholdMil,1000);
    assert.equal(summary.lowStockRule,undefined);
    assert.equal(summary.totalProducts,6);assert.equal(summary.lowStockCount,3);assert.equal(summary.outOfStockCount,1);
    assert.deepEqual(new Set(summary.itemsLowStock.map((r:Json)=>r.id)),new Set([rows.noMinimum.id,rows.equal.id,rows.weight.id]));
    assert.equal(summary.totalEstimatedCostCents,8600);
    assert.equal(summary.itemsLowStock[0].minimumStockMil,undefined);
    process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS='';
    assert.deepEqual(await get('/owner/stock/summary?limit=10',f.token),summary);
  });

  it('preserves negative-stock cost handling and tenant isolation for pilot reports',async()=>{
    const a=await tenant(),b=await tenant();
    await product(a.companyId,'Saldo negativo antigo',-1000,0,2000);
    const fractional=await product(a.companyId,'Produto fracionado',125,1000,1500,'kg');
    await product(b.companyId,'Outro tenant',0,9000,90000);
    process.env.INVENTORY_WORKSPACE_PILOT_COMPANY_IDS=a.companyId;
    const summary=await get('/owner/stock/summary?limit=10&companyId='+b.companyId,a.token);
    assert.equal(summary.totalProducts,2);assert.equal(summary.lowStockCount,1);assert.equal(summary.outOfStockCount,1);
    assert.equal(summary.totalEstimatedCostCents,188); // Existing rounding and negative-value clamp unchanged.
    assert.equal(summary.itemsLowStock[0].id,fractional.id);
    assert(!JSON.stringify(summary).includes('Outro tenant'));
  });
});
