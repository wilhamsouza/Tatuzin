import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { randomUUID } from 'node:crypto';
import { prisma } from '../../database/prisma';
import type { AppContext } from '../app/app-context.types';
import { CashDivergenceReviewService } from './cash-divergence-review.service';
const allowedDb = new URL(process.env.DATABASE_URL ?? 'postgresql://invalid/invalid');
if (allowedDb.hostname !== '127.0.0.1' || allowedDb.port !== '55442' || allowedDb.pathname !== '/tatuzin_cash_test') throw new Error('Cash integration requires explicit disposable DB 127.0.0.1:55442/tatuzin_cash_test');
const service = new CashDivergenceReviewService();
const suffix=randomUUID();let userId:string;let companyId:string;let sessionId:string;let context:AppContext;
before(async()=>{
 const user=await prisma.user.create({data:{email:`cash-review-${suffix}@test.invalid`,passwordHash:'test-only',name:'Review author'}});userId=user.id;
 const company=await prisma.company.create({data:{name:'Cash test',legalName:'Cash test',slug:`cash-review-${suffix}`}});companyId=company.id;
 const session=await prisma.cashSession.create({data:{companyId,userId,localUuid:suffix,status:'closed',openingBalanceCents:1000,expectedBalanceCents:1100,closingBalanceCents:1000,payload:{openingDetails:{version:2,countedAmountCents:1000,blindClosureEnabled:false,policyRevision:0},closingDetails:{version:2,sessionUuid:suffix,expectedBalanceCents:1100,countedBalanceCents:1000,differenceCents:-100,reason:'Counted shortage',blindClosureEnabled:false,policyRevision:0}}}});sessionId=session.id;
 context={company:{id:companyId},user:{id:userId,name:'Review author'},membership:{role:'OWNER',permissions:['reports.advanced','employees.manage']}} as AppContext;
});
after(async()=>{await prisma.company.deleteMany({where:{id:companyId}});await prisma.user.deleteMany({where:{id:userId}});await prisma.$disconnect();});
test('append review, idempotent replay, stale revision and original closure preserved',async()=>{
 const snapshot=await prisma.cashSession.findUniqueOrThrow({where:{id:sessionId}});
 assert.equal((await service.get(context,sessionId))?.revision,0);
 const request={requestId:randomUUID(),expectedRevision:0,status:'REVIEWED',justification:'Conferido com comprovantes'};
 const first=await service.append(context,sessionId,request);assert.equal(first.divergenceReview?.revision,1);
 assert.deepEqual(await service.append(context,sessionId,request),first);
 await assert.rejects(service.append(context,sessionId,{...request,requestId:randomUUID()}),{code:'CASH_REVIEW_REVISION_CONFLICT'});
 await assert.rejects(service.append(context,sessionId,{...request,justification:'changed'}),{code:'CASH_REVIEW_REQUEST_CONFLICT'});
 const second=await service.append(context,sessionId,{...request,requestId:randomUUID(),expectedRevision:1,status:'PENDING',justification:'Reaberto para verificacao'});
 assert.equal(second.divergenceReview?.comments.length,2);assert.equal(second.divergenceReview?.revision,2);
 assert.deepEqual((await prisma.cashSession.findUniqueOrThrow({where:{id:sessionId}})).payload,snapshot.payload);
});
test('tenant, report permission, manager role and manage permission gates',async()=>{
 await assert.rejects(service.get({...context,company:{...context.company,id:randomUUID()}},sessionId),{code:'OWNER_CASH_SESSION_NOT_FOUND'});
 for(const patch of [{membership:{role:'OWNER',permissions:[]}}, {membership:{role:'ADMIN',permissions:['reports.advanced']}}, {employee:{role:'CASHIER'},membership:{role:'ADMIN',permissions:['reports.advanced','employees.manage']}}]) {
 await assert.rejects(service.append({...context,...patch} as AppContext,sessionId,{requestId:randomUUID(),expectedRevision:2,status:'REVIEWED',justification:'test'}),{code:'CASH_REVIEW_FORBIDDEN'}); }
});
test('concurrent same revision accepts exactly one append',async()=>{
 const results=await Promise.allSettled([1,2].map(i=>service.append(context,sessionId,{requestId:randomUUID(),expectedRevision:2,status:'REVIEWED',justification:`Reviewer ${i}`})));
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.equal((await service.get(context,sessionId))?.comments.length,3);
});

test('physical device opens serialize; one operator may hold independent devices; late ledger leaves closure frozen',async()=>{
 const {CashSessionMaterializer}=await import('../sync/materializers/cash-session.materializer');
 const {CashMovementMaterializer}=await import('../sync/materializers/cash-movement.materializer');
 const devices=await Promise.all([0,1].map(n=>prisma.companyDevice.create({data:{companyId,userId,clientInstanceId:`${suffix}-${n}`,status:'ACTIVE'}})));
 const openedAt=new Date(Date.now()-60000).toISOString();const closedAt=new Date().toISOString();
 const makeInput=(tx:any,deviceId:string,uuid:string,status='open')=>({tx,context:{...context,membership:{...context.membership,permissions:["*"]},device:{id:deviceId}},event:{operation:'upsert',entity:'cashSession',entityLocalId:uuid,occurredAt:openedAt},payload:{uuid,status,openedAt,openingDetails:{version:2,countedAmountCents:1000,blindClosureEnabled:false,policyRevision:0}}}) as any;
 const firstUuid=randomUUID();
 const concurrent=await Promise.all([firstUuid,randomUUID()].map(uuid=>prisma.$transaction(tx=>new CashSessionMaterializer().materialize(makeInput(tx,devices[0].id,uuid)))));
 assert.equal(concurrent.filter(x=>x.outcome==='accepted').length,1);assert.equal(concurrent.filter(x=>x.outcome==='conflict').length,1);
 const active=await prisma.cashSession.findFirstOrThrow({where:{companyId,deviceId:devices[0].id,status:'open'}});
 const secondUuid=randomUUID();assert.equal((await prisma.$transaction(tx=>new CashSessionMaterializer().materialize(makeInput(tx,devices[1].id,secondUuid)))).outcome,'accepted');
 const closeInput=(tx:any)=>{const input=makeInput(tx,devices[0].id,active.localUuid,'closed');input.payload.closedAt=closedAt;input.payload.closingDetails={version:2,sessionUuid:active.localUuid,expectedBalanceCents:1000,countedBalanceCents:1000,differenceCents:0,blindClosureEnabled:false,policyRevision:0};return input;};
 assert.equal((await prisma.$transaction(tx=>new CashSessionMaterializer().materialize(closeInput(tx)))).outcome,'accepted');
 const closed=await prisma.cashSession.findUniqueOrThrow({where:{id:active.id}});
 const movement=(tx:any,occurredAt:string)=>({tx,context:{...context,device:{id:devices[0].id}},event:{operation:'create',entity:'cashMovement',entityLocalId:randomUUID(),occurredAt},payload:{cashSessionUuid:active.localUuid,amountCents:50,eventType:'venda',paymentMethod:'pix',createdAt:occurredAt}}) as any;
 const allowedContext={...context,membership:{...context.membership,permissions:['*']}};
 const late=await prisma.$transaction(tx=>{const input=movement(tx,new Date(Date.now()-30000).toISOString());input.context={...allowedContext,device:{id:devices[0].id}};return new CashMovementMaterializer().materialize(input);});
 assert.equal(late.outcome,'accepted');
 const tooLate=await prisma.$transaction(tx=>{const input=movement(tx,new Date(Date.now()+60000).toISOString());input.context={...allowedContext,device:{id:devices[0].id}};return new CashMovementMaterializer().materialize(input);});
 assert.equal(tooLate.outcome,'conflict');
 assert.deepEqual((await prisma.cashSession.findUniqueOrThrow({where:{id:active.id}})).payload,closed.payload);
});

test('company policy revision increments only when policy changes; existing session snapshot stays unchanged',async()=>{
 const {CompanySettingsService}=await import('../app/company-settings.service');
 const settings=new CompanySettingsService();
 const original=(await prisma.cashSession.findUniqueOrThrow({where:{id:sessionId}})).payload;
 const initial=await settings.getReceiptSettings(context);assert.equal(initial.company.cashBlindClosureEnabled,false);assert.equal(initial.company.cashPolicyRevision,0);
 const enabled=await settings.updateReceiptSettings(context,{cashBlindClosureEnabled:true});assert.equal(enabled.company.cashPolicyRevision,1);
 const replays=await Promise.all([0,1].map(()=>settings.updateReceiptSettings(context,{cashBlindClosureEnabled:true})));
 assert.ok(replays.every(x=>x.company.cashPolicyRevision===1));
 assert.equal((await settings.updateReceiptSettings(context,{cashBlindClosureEnabled:false})).company.cashPolicyRevision,2);
 assert.deepEqual((await prisma.cashSession.findUniqueOrThrow({where:{id:sessionId}})).payload,original);
});

test('owner summary counts all filtered sessions beyond pagination and former 250-row limit',async()=>{
 const {OwnerReportingService}=await import('../owner/owner-reporting.service');
 await prisma.cashSession.createMany({data:Array.from({length:251},(_,n)=>({companyId,userId,localUuid:`summary-${suffix}-${n}`,status:n%2===0?'closed':'open',openingBalanceCents:100,expectedBalanceCents:100,closingBalanceCents:n%2===0?110:900,notes:'summary-regression'}))});
 const reports=new OwnerReportingService();
 const result=await reports.listCashSessions(context,{status:'all',search:'summary-regression',page:1,pageSize:1});
 assert.equal(result.summary.totalSessions,251);
 assert.equal(result.summary.closedSessions,126);
 assert.equal(result.summary.openSessions,125);
 assert.equal(result.summary.totalDifferenceCents,1260);
 const closed=await reports.listCashSessions(context,{status:'closed',search:'summary-regression',page:2,pageSize:1});
 assert.equal(closed.summary.totalSessions,126);assert.equal(closed.summary.openSessions,0);assert.equal(closed.summary.totalDifferenceCents,1260);
});

test('synced automatic opening confirms initial float exactly once under concurrent updates',async()=>{
 const {CashSessionMaterializer}=await import('../sync/materializers/cash-session.materializer');
 const device=await prisma.companyDevice.create({data:{companyId,userId,clientInstanceId:`confirm-${suffix}`,status:'ACTIVE'}});
 const uuid=randomUUID();const openedAt=new Date().toISOString();
 const eventContext={...context,membership:{...context.membership,permissions:['*']},device:{id:device.id}};
 const materialize=(count:number,pending:boolean)=>prisma.$transaction(tx=>new CashSessionMaterializer().materialize({tx,context:eventContext,event:{operation:'upsert',entity:'cashSession',entityLocalId:uuid,occurredAt:openedAt},payload:{uuid,status:'open',openedAt,openingBalanceCents:count,awaitingInitialFloatConfirmation:pending,openingDetails:{version:2,countedAmountCents:count,denominations:count===0?[]:[{valueCents:count,quantity:1}],blindClosureEnabled:false,policyRevision:2}}} as any));
 assert.equal((await materialize(0,true)).outcome,'accepted');
 const {OwnerReportingService}=await import('../owner/owner-reporting.service');
 const reports=new OwnerReportingService();
 const provisional=await prisma.cashSession.findUniqueOrThrow({where:{companyId_localUuid:{companyId,localUuid:uuid}}});
 assert.equal((await reports.getCashSessionDetail(context,provisional.id)).openingAwaitingConfirmation,true);
 const outcomes=await Promise.all([1000,2000].map(count=>materialize(count,false)));
 assert.equal(outcomes.filter(x=>x.outcome==='accepted').length,1);assert.equal(outcomes.filter(x=>x.outcome==='conflict').length,1);
 const row=await prisma.cashSession.findUniqueOrThrow({where:{companyId_localUuid:{companyId,localUuid:uuid}}});
 assert.ok([1000,2000].includes(row.openingBalanceCents));
 assert.equal((row.payload as any).awaitingInitialFloatConfirmation,false);
 assert.equal((await reports.getCashSessionDetail(context,row.id)).openingAwaitingConfirmation,false);
 assert.equal((row.payload as any).openingDetails.policyRevision,2);
 assert.equal((await materialize(3000,false)).outcome,'conflict');
 assert.equal((await materialize(0,true)).outcome,'conflict');
 assert.equal((await materialize(row.openingBalanceCents,false)).outcome,'accepted');
 assert.equal((await prisma.cashSession.findUniqueOrThrow({where:{id:row.id}})).openingBalanceCents,row.openingBalanceCents);
});
