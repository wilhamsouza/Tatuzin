import assert from 'node:assert/strict';
import { after,before,beforeEach,describe,it } from 'node:test';
import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import jwt from 'jsonwebtoken';
import { createApp } from '../../app';
import { prisma } from '../../database/prisma';
import { env } from '../../config/env';
import { assertSafeIntegrationTestDatabaseUrl } from '../../shared/testing/integration-prisma';

const run=`admin-platform-${randomUUID()}`;let server:Server;let base='';
const companyIds:string[]=[];const actorIds:string[]=[];
const reads=['admin.overview.read','admin.companies.read','admin.support.read','admin.sync.read','admin.billing.read','admin.devices.read','admin.usage.read','admin.audit.read'];
async function company(){const row=await prisma.company.create({data:{name:'Platform fixture',legalName:'Platform fixture',slug:`${run}-${randomUUID()}`}});companyIds.push(row.id);return row;}
async function actor(companyId:string,keys=reads,scopeId?:string){const u=await prisma.user.create({data:{name:'Admin fixture',email:`${run}-${randomUUID()}@test.invalid`,passwordHash:'unused',isPlatformAdmin:true}});actorIds.push(u.id);const m=await prisma.membership.create({data:{userId:u.id,companyId,role:'OWNER'}});for(const key of keys)await prisma.adminUserPermission.create({data:{actorUserId:u.id,permissionKey:key,scope:scopeId?'company':'platform',scopeId:scopeId??'*'}});return{id:u.id,token:jwt.sign({sub:u.id,companyId,membershipId:m.id,membershipRole:'OWNER',isPlatformAdmin:true,email:u.email},env.JWT_SECRET,{expiresIn:'15m'})};}
async function req(method:string,path:string,token?:string,body?:unknown){const r=await fetch(base+path,{method,headers:{...(token?{Authorization:`Bearer ${token}`} :{}),...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined});return{status:r.status,data:await r.json() as any};}
async function cleanup(){await prisma.billingAdminAuditLog.deleteMany({where:{actorUserId:{in:actorIds}}});await prisma.billingInvoice.deleteMany({where:{companyId:{in:companyIds}}});await prisma.supportActionExecution.deleteMany({where:{actorUserId:{in:actorIds}}});await prisma.adminAuditLog.deleteMany({where:{actorUserId:{in:actorIds}}});await prisma.company.deleteMany({where:{id:{in:companyIds}}});await prisma.user.deleteMany({where:{id:{in:actorIds}}});companyIds.length=0;actorIds.length=0;}
describe('admin platform contracts and controlled actions',()=>{
 before(async()=>{assertSafeIntegrationTestDatabaseUrl(process.env.DATABASE_URL??'');await prisma.$connect();server=createApp().listen(0);base=`http://127.0.0.1:${(server.address() as AddressInfo).port}/api/admin`;});
 beforeEach(cleanup);after(async()=>{try{await cleanup();}finally{if(server)await new Promise<void>(r=>server.close(()=>r()));await prisma.$disconnect();}});
 it('requires authentication and explicit reads; unavailable sections do not hide permitted data',async()=>{
  const c=await company();const a=await actor(c.id,['admin.overview.read','admin.companies.read'],c.id);assert.equal((await req('GET','/overview')).status,401);const result=await req('GET','/overview',a.token);assert.equal(result.status,200);assert.equal(result.data.companies.total,1);assert.equal(result.data.billing.available,false);assert.equal(result.data.billing.reason,'FORBIDDEN');assert.equal((await req('GET','/usage',a.token)).status,403);
 });
 it('aggregates beyond a page and separates paid invoices from ERP sales',async()=>{
  const c=await company();const a=await actor(c.id);const today=new Date().toISOString().slice(0,10);const now=new Date();
  await prisma.billingInvoice.createMany({data:[{companyId:c.id,provider:'test',status:'PAID',currency:'BRL',amountCents:1250,paidAt:now},{companyId:c.id,provider:'test',status:'PENDING',currency:'BRL',amountCents:99900,dueAt:new Date(Date.now()-86400000)},{companyId:c.id,provider:'test',status:'PAID',currency:'USD',amountCents:70000,paidAt:now}]});
  await prisma.sale.create({data:{companyId:c.id,localUuid:randomUUID(),paymentType:'cash',paymentMethod:'pix',totalAmountCents:999999,totalCostCents:1,soldAt:now}});
  const extra=Array.from({length:105},()=>({id:randomUUID(),name:'Paged company',legalName:'Paged company',slug:`${run}-${randomUUID()}`}));companyIds.push(...extra.map(c=>c.id));await prisma.company.createMany({data:extra});
  const response=await req('GET',`/overview?startDate=${today}&endDate=${today}`,a.token);assert.equal(response.status,200);assert.ok(response.data.companies.total>=106);assert.equal(response.data.billing.paidAmountCents,1250);assert.equal(response.data.billing.overdueCount,1);assert.equal(response.data.billing.series[0].amountCents,1250);
  assert.equal((await req('GET','/overview?startDate=2026-02-30',a.token)).status,422);
 });
 it('search and invoices restrict company scopes and capabilities never imply writes',async()=>{
  const c=await company(),other=await company();const a=await actor(c.id,reads,c.id);
  const search=await req('GET','/search?q=&pageSize=1',a.token);assert.equal(search.data.total,1);assert.equal(search.data.groups[0].items[0].companyId,c.id);assert.ok(!JSON.stringify(search.data).includes(other.id));
  const list=await req('GET','/platform-companies?pageSize=1',a.token);assert.equal(list.status,200);assert.equal(list.data.pagination.total,1);assert.equal(list.data.items[0].id,c.id);assert.equal((await req('GET',`/devices?companyId=${other.id}`,a.token)).status,403);
  assert.equal((await req('POST',`/companies/${c.id}/billing/force-plan`,a.token,{plan:'PRO',reason:'Não liberar alterações excepcionais'})).status,403);
  const cap=await req('GET','/capabilities',a.token);assert.equal(cap.data.experienceEnabled,false);assert.equal(cap.data.actions.find((r:any)=>r.key==='license.extend').allowed,false);
  assert.equal((await req('GET',`/companies/${other.id}`,a.token)).status,403);
 });
 it('retries a confirmed extension without duplicating effects and consumes its preview once',async()=>{
  const c=await company();const a=await actor(c.id,[...reads,'support.license.update']);await prisma.license.create({data:{companyId:c.id,plan:'PRO',status:'EXPIRED',startsAt:new Date(Date.now()-86400000*30),expiresAt:new Date(Date.now()-86400000),syncEnabled:true}});
  const preview=await req('POST','/operations/preview',a.token,{action:'license.extend',companyId:c.id,reason:'Restabelecer acesso durante atendimento',days:2});assert.equal(preview.status,200);assert.equal(preview.data.allowed,true);
  const body={previewId:preview.data.previewId,confirmationText:preview.data.expectedConfirmationText,idempotencyKey:randomUUID()};
  const first=await req('POST','/operations/execute',a.token,body);assert.equal(first.status,200);const after=await prisma.license.findUniqueOrThrow({where:{companyId:c.id}});
  assert.equal((await req('POST','/operations/execute',a.token,body)).status,200);
  assert.equal((await req('POST','/operations/execute',a.token,{...body,idempotencyKey:randomUUID()})).status,409);
  assert.equal((await prisma.license.findUniqueOrThrow({where:{companyId:c.id}})).expiresAt?.toISOString(),after.expiresAt?.toISOString());
  assert.equal(await prisma.supportActionExecution.count({where:{actorUserId:a.id,status:'SUCCEEDED'}}),1);
 });
 it('rejects stale previews and another administrator cannot reuse them',async()=>{
  const c=await company();const a=await actor(c.id,[...reads,'support.license.update']);const b=await actor(c.id,[...reads,'support.license.update']);await prisma.license.create({data:{companyId:c.id,plan:'PRO',status:'ACTIVE',startsAt:new Date(),syncEnabled:true}});
  const p=await req('POST','/operations/preview',a.token,{action:'license.suspend',companyId:c.id,reason:'Investigar acesso durante atendimento'});assert.equal(p.status,200);
  const body={previewId:p.data.previewId,confirmationText:p.data.expectedConfirmationText,idempotencyKey:randomUUID()};assert.equal((await req('POST','/operations/execute',b.token,body)).status,404);
  await prisma.license.update({where:{companyId:c.id},data:{maxDevices:7}});assert.equal((await req('POST','/operations/execute',a.token,body)).status,409);assert.equal((await prisma.license.findUniqueOrThrow({where:{companyId:c.id}})).status,'ACTIVE');
 });
 it('template grants are audited, scoped, explicit and cannot self-grant',async()=>{
  const c=await company();const a=await actor(c.id,[...reads,'admin-permissions.manage']);const b=await actor(c.id,[]);
  const body={adminUserId:b.id,reason:'Delegar atendimento à equipe interna',scope:'company',scopeId:c.id,confirmationText:'APLICAR_PERFIL'};
  assert.equal((await req('POST','/permission-templates/support/apply',a.token,{...body,adminUserId:a.id})).status,403);
  assert.equal((await req('POST','/permission-templates/support/apply',a.token,body)).status,200);
  assert.ok(await prisma.adminUserPermission.findFirst({where:{actorUserId:b.id,permissionKey:'admin.support.manage',scope:'company',scopeId:c.id}}));
  assert.equal(await prisma.adminAuditLog.count({where:{actorUserId:a.id,action:'admin.platform.permission-template.applied'}}),1);
 });
});
