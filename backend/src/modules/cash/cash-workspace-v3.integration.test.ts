import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {before,beforeEach,after,test} from 'node:test';
import {prisma} from '../../database/prisma';
import type {AppContext} from '../app/app-context.types';
import {CashWorkspaceService} from './cash-workspace.service';
import {SyncMaterializerService} from '../sync/materializers/sync-materializer.service';
const database=new URL(process.env.DATABASE_URL??'postgresql://invalid/invalid');
if(database.hostname!=='127.0.0.1'||database.port!=='55442'||database.pathname!=='/tatuzin_cash_test')throw new Error('V3 Cash tests require explicit disposable DB55442');
const service=new CashWorkspaceService();const materializer=new SyncMaterializerService();
let companyId:string;let userId:string;let otherId:string;let a:AppContext;let b:AppContext;let c:AppContext;let other:AppContext;
before(async()=>{
 const suffix=randomUUID();const company=await prisma.company.create({data:{name:'V3 Cash test',legalName:'V3 test',slug:`v3-${suffix}`}});companyId=company.id;
 const users=await Promise.all([0,1].map(n=>prisma.user.create({data:{name:`Employee ${n}`,email:`v3-${suffix}-${n}@test.invalid`,passwordHash:'test-only'}})));userId=users[0].id;otherId=users[1].id;
 const devices=await Promise.all([0,1,2,3].map(n=>prisma.companyDevice.create({data:{companyId,userId:n===3?otherId:userId,clientInstanceId:`v3-${suffix}-${n}`,status:'ACTIVE',deviceLabel:`Device ${n}`}})));
 const ctx=(n:number,user:string)=>({company:{id:companyId},user:{id:user,name:`Employee ${user}`},membership:{role:'OWNER',permissions:['*']},device:{id:devices[n].id}}) as AppContext;
 a=ctx(0,userId);b=ctx(1,userId);c=ctx(2,userId);other=ctx(3,otherId);
});
beforeEach(async()=>{await prisma.cashSession.deleteMany({where:{companyId}});await prisma.company.update({where:{id:companyId},data:{cashBlindClosureEnabled:false,cashPolicyRevision:0}});});
after(async()=>{await prisma.company.deleteMany({where:{id:companyId}});await prisma.user.deleteMany({where:{id:{in:[userId,otherId]}}});await prisma.$disconnect();});
async function open(context=a,count=1000){return (await service.open(context,{requestId:randomUUID(),openingBalanceCents:count})).session!;}
async function push(context:AppContext,uuid:string,entity:string,payload:Record<string,unknown>,localUuid=randomUUID()){
 return prisma.$transaction(tx=>materializer.materialize({tx,context,event:{eventId:randomUUID(),entity,operation:'create',entityLocalId:localUuid,occurredAt:new Date().toISOString()},payload:{cashWorkspaceVersion:3,cashSessionUuid:uuid,uuid:entity==='cashSession'?uuid:localUuid,...payload}} as any));
}
const ack=(context:AppContext,session:any)=>service.acknowledge(context,session.uuid,session.closureRequest.requestId,{generation:session.closureRequest.generation,revision:session.closureRequest.revision,drained:true});

test('one employee cash across concurrent devices, first float only, retry no duplicate participant',async()=>{
 const requestId=randomUUID();const first=await service.open(a,{requestId,openingBalanceCents:1000});
 const replay=await service.open(a,{requestId,openingBalanceCents:1000});assert.equal(replay.session!.id,first.session!.id);
 await assert.rejects(service.open(a,{requestId,openingBalanceCents:2000}),{code:'CASH_REQUEST_CONFLICT'});
 const joined=await service.open(b,{requestId:randomUUID(),openingBalanceCents:9999});assert.equal(joined.session!.id,first.session!.id);assert.equal(joined.session!.openingBalanceCents,1000);assert.equal(joined.session!.participants.length,2);
 assert.equal((await service.join(b,first.session!.uuid,{requestId:randomUUID()})).session!.participants.length,2);
 const independent=await open(other,200);assert.notEqual(independent.id,first.session!.id);
 const report=await service.ownerWorkspace(a);assert.equal(report.employees.length,2);assert.equal(report.summary.totalExpectedBalanceCents,1200);
});
test('participant and trusted employee/tenant gates apply to all V3 writes; no client total overwrite',async()=>{
 const session=await open();
 assert.equal((await push(c,session.uuid,'cashMovement',{amountCents:100,eventType:'venda',paymentMethod:'dinheiro'})).outcome,'rejected');
 assert.equal((await push(other,session.uuid,'cashMovement',{amountCents:100,eventType:'venda',paymentMethod:'dinheiro'})).outcome,'rejected');
 await assert.rejects(service.join(other,session.uuid,{requestId:randomUUID()}),{code:'CASH_WORKSPACE_ACTOR_MISMATCH'});
 await assert.rejects(service.join({...a,company:{...a.company,id:randomUUID()}},session.uuid,{requestId:randomUUID()}),{code:'CASH_WORKSPACE_NOT_FOUND'});
 assert.equal((await push(a,session.uuid,'cashSession',{openingBalanceCents:99999,status:'open'})).outcome,'duplicate');
 assert.equal((await service.get(a)).session!.openingBalanceCents,1000);
 assert.equal((await push(a,session.uuid,'sale',{paymentType:'avista',paymentMethod:'pix',totalAmountCents:500})).outcome,'accepted');
 const sale=await prisma.sale.findFirstOrThrow({where:{cashSessionId:session.id}});
 const payment=await prisma.$transaction(tx=>materializer.materialize({tx,context:other,event:{eventId:randomUUID(),entity:'payment',operation:'create',entityLocalId:randomUUID(),occurredAt:new Date().toISOString()},payload:{saleUuid:sale.localUuid,amountCents:100}} as any));
 assert.equal(payment.outcome,'rejected');
 assert.equal((await service.get(a)).session!.revision,1);
});
test('real signed/positive cash withdrawal payloads and Pix do not duplicate float or invent fiado face value',async()=>{
 const session=await open();
 for(const data of [{eventType:'venda',amountCents:100,paymentMethod:'dinheiro'},{eventType:'venda',amountCents:500,paymentMethod:'pix'},{eventType:'recebimento_fiado',amountCents:60,paymentMethod:'dinheiro'},{eventType:'sangria',amountCents:-101,paymentMethod:'dinheiro'},{eventType:'cash_withdrawal',amountCents:30,paymentMethod:'dinheiro'},{eventType:'sangria',amountCents:-200,paymentMethod:'pix'},{eventType:'suprimento',amountCents:50,paymentMethod:'dinheiro'}])assert.equal((await push(a,session.uuid,'cashMovement',data)).outcome,'accepted');
 assert.equal((await service.get(a)).session!.expectedBalanceCents,1079);
});
test('all registered participants ack same revision; late movement invalidates, review/reconfirm then final freeze',async()=>{
 let session=await open();await service.join(b,session.uuid,{requestId:randomUUID()});
 const movementUuid=randomUUID();assert.equal((await push(a,session.uuid,'cashMovement',{eventType:'venda',amountCents:100,paymentMethod:'dinheiro'},movementUuid)).outcome,'accepted');
 session=(await service.get(a)).session!;
 session=(await service.requestClosure(a,session.uuid,{requestId:randomUUID(),expectedRevision:session.revision,countedBalanceCents:1100,localExpectedBalanceCents:1100})).session!;
 const originalId=session.closureRequest!.requestId;const originalGeneration=session.closureRequest!.generation;
 assert.equal((await ack(a,session)).session!.status,'PENDING_SYNC');
 assert.equal((await push(b,session.uuid,'cashMovement',{eventType:'venda',amountCents:20,paymentMethod:'dinheiro'})).outcome,'accepted');
 const updated=(await service.get(a)).session!;assert.equal(updated.status,'REVIEW_REQUIRED');assert.ok(updated.closureRequest!.generation>originalGeneration);
 await assert.rejects(ack(b,session),{code:'CASH_CLOSURE_GENERATION_CONFLICT'});
 session=(await service.requestClosure(a,session.uuid,{requestId:randomUUID(),expectedRevision:updated.revision,countedBalanceCents:1120,localExpectedBalanceCents:1120,notes:'Conferencia final do aparelho A',denominations:[{valueCents:1000,quantity:1}],coinsCents:120},originalId)).session!;
 assert.equal(session.closingDetails,null);
 assert.equal((await ack(a,session)).session!.status,'PENDING_SYNC');
 session=(await ack(b,session)).session!;assert.equal(session.status,'CLOSED');assert.equal(session.closureRequest!.expectedBalanceCents,1120);
 assert.deepEqual(session.closingDetails,{version:2,sessionUuid:session.uuid,expectedBalanceCents:1120,countedBalanceCents:1120,differenceCents:0,blindClosureEnabled:false,policyRevision:0,notes:'Conferencia final do aparelho A',denominations:[{valueCents:1000,quantity:1}],coinsCents:120});
 assert.deepEqual((await service.get(b)).session!.closingDetails,session.closingDetails);
 const frozen=await prisma.cashSession.findUniqueOrThrow({where:{id:session.id}});
 assert.equal((await push(a,session.uuid,'cashMovement',{eventType:'venda',amountCents:100,paymentMethod:'dinheiro'},movementUuid)).outcome,'duplicate');
 assert.equal((await push(a,session.uuid,'cashMovement',{eventType:'venda',amountCents:999,paymentMethod:'dinheiro'})).outcome,'rejected');
 assert.equal((await push(a,session.uuid,'cashSession',{status:'closed',expectedBalanceCents:99999})).outcome,'rejected');
 assert.deepEqual((await prisma.cashSession.findUniqueOrThrow({where:{id:session.id}})).payload,frozen.payload);
 assert.equal((await ack(b,session)).session!.status,'CLOSED');
 const next=await open(a,5);assert.notEqual(next.id,session.id);assert.equal(next.openingBalanceCents,5);
});
test('blind request omits expected without oracle, read manager sees it; final count only after drain',async()=>{
 await prisma.company.update({where:{id:companyId},data:{cashBlindClosureEnabled:true,cashPolicyRevision:1}});
 let session=await open();assert.equal(session.expectedBalanceCents,null);
 const input={requestId:randomUUID(),expectedRevision:session.revision,countedBalanceCents:900,reason:'Contagem cega'};
 session=(await service.requestClosure(a,session.uuid,input)).session!;assert.equal(session.status,'PENDING_SYNC');assert.equal(session.closureRequest!.differenceCents,null);assert.equal(session.closureRequest!.expectedBalanceCents,null);
 const owner=await service.ownerWorkspace({...a,membership:{...a.membership,role:'ADMIN',permissions:['reports.advanced']}});assert.equal(owner.employees[0].expectedBalanceCents,1000);assert.equal(owner.employees[0].canReview,false);
 assert.equal((await service.requestClosure(a,session.uuid,input)).session!.closureRequest!.requestId,input.requestId);
 await assert.rejects(service.requestClosure(a,session.uuid,{...input,countedBalanceCents:1}),{code:'CASH_REQUEST_CONFLICT'});
 session=(await ack(a,session)).session!;assert.equal(session.status,'CLOSED');assert.equal(session.closureRequest!.differenceCents,-100);
});
test('stale offline request becomes review required; new participant invalidates ack generation; legacy remains separate',async()=>{
 let session=await open();const oldRevision=session.revision;
 assert.equal((await push(a,session.uuid,'cashMovement',{eventType:'venda',amountCents:10,paymentMethod:'dinheiro'})).outcome,'accepted');
 session=(await service.requestClosure(a,session.uuid,{requestId:randomUUID(),expectedRevision:oldRevision,countedBalanceCents:1000,localExpectedBalanceCents:1000})).session!;assert.equal(session.status,'REVIEW_REQUIRED');
 await assert.rejects(ack(a,session),{code:'CASH_CLOSURE_REVIEW_REQUIRED'});
 const beforeGeneration=session.closureRequest!.generation;await service.join(b,session.uuid,{requestId:randomUUID()});assert.ok((await service.get(a)).session!.closureRequest!.generation>beforeGeneration);
 await prisma.cashSession.create({data:{companyId,userId,localUuid:randomUUID(),status:'open',openingBalanceCents:777}});
 const current=await service.get(a);assert.equal(current.legacySessionsPresent,true);assert.equal(current.session!.openingBalanceCents,1000);assert.equal((await service.ownerWorkspace(a)).summary.legacySessions,1);
});

test('GET does not invent device participation; explicit join proves currentDeviceJoined',async()=>{
 const first=await open();assert.equal(first.currentDeviceJoined,true);
 const remote=(await service.get(c)).session!;assert.equal(remote.uuid,first.uuid);assert.equal(remote.currentDeviceJoined,false);
 const joined=(await service.join(c,first.uuid,{requestId:randomUUID()})).session!;assert.equal(joined.currentDeviceJoined,true);
});
test('owner V3 financial bypass returns409 and action DTO denies; ordinary reports still read real amount',async()=>{
 const {OwnerReportingService}=await import('../owner/owner-reporting.service');const reports=new OwnerReportingService();
 const session=await open();await push(a,session.uuid,'sale',{paymentType:'avista',paymentMethod:'dinheiro',totalAmountCents:500});
 const sale=await prisma.sale.findFirstOrThrow({where:{cashSessionId:session.id}});
 const detail=await reports.getCashSessionDetail(a,session.id);assert.equal(detail.cashWorkspaceVersion,3);assert.equal(detail.canReview,false);assert.equal(detail.sales.items[0].canCancel,false);assert.equal(detail.sales.items[0].canReturn,false);assert.equal(detail.sales.items[0].actionUnavailableReason,'CASH_V3_REFUND_REQUIRES_OPERATOR_APP');
 await assert.rejects(reports.cancelCashSessionSale(a,session.id,sale.id,{reason:'Cancel request'}),{code:'CASH_V3_REFUND_REQUIRES_OPERATOR_APP',statusCode:409});
 await assert.rejects(reports.registerSaleReturn(a,session.id,sale.id,{reason:'Return request',returnToStock:false,items:[]}),{code:'CASH_V3_REFUND_REQUIRES_OPERATOR_APP',statusCode:409});
});
test('shared physical device pending events from another trusted user do not block own closure',async()=>{
 const ownOther={...other,device:a.device};let session=await open(ownOther,200);
 const pending=await prisma.syncEvent.create({data:{companyId,userId,deviceId:a.device.id,eventId:randomUUID(),feature:'caixa',entity:'cashMovement',operation:'create',entityLocalId:randomUUID(),occurredAt:new Date(),payload:{cashEmployeeId:userId},status:'FAILED'}});
 session=(await service.requestClosure(ownOther,session.uuid,{requestId:randomUUID(),expectedRevision:session.revision,countedBalanceCents:200,localExpectedBalanceCents:200})).session!;
 assert.equal((await ack(ownOther,session)).session!.status,'CLOSED');
 assert.equal((await prisma.syncEvent.findUniqueOrThrow({where:{id:pending.id}})).status,'FAILED');
 await prisma.syncEvent.delete({where:{id:pending.id}});
});
test('final acknowledgement races a late write under one session lock; accepted write never disappears behind frozen close',async()=>{
 for(let i=0;i<5;i++){
  await prisma.cashSession.deleteMany({where:{companyId}});
  let session=await open();await service.join(b,session.uuid,{requestId:randomUUID()});
  session=(await service.requestClosure(a,session.uuid,{requestId:randomUUID(),expectedRevision:session.revision,countedBalanceCents:1000,localExpectedBalanceCents:1000})).session!;await ack(a,session);
  const [write,close]=await Promise.allSettled([push(a,session.uuid,'cashMovement',{eventType:'venda',amountCents:10,paymentMethod:'dinheiro'}),ack(b,session)]);
  const current=(await service.get(a)).session!;
  assert.equal(write.status,'fulfilled');
  if(write.status==='fulfilled'&&write.value.outcome==='accepted'){assert.equal(current.status,'REVIEW_REQUIRED');assert.equal(current.expectedBalanceCents,1010);assert.equal(close.status,'rejected');}
  else {assert.equal(current.status,'CLOSED');assert.equal(current.expectedBalanceCents,1000);}
 }
});

test('workspace confirmed UUID coverage, expected and revision remain one snapshot while pushes interleave',async()=>{
 const session=await open();
 const snapshots=await Promise.all(Array.from({length:8},async(_,index)=>{
  if(index%2===0)await push(a,session.uuid,'cashMovement',{eventType:'venda',amountCents:10,paymentMethod:'dinheiro'});
  return (await service.get(a)).session!;
 }));
 for(const snapshot of snapshots){assert.equal(snapshot.expectedBalanceCents,1000+snapshot.confirmedMovementUuids.length*10);assert.equal(snapshot.revision,snapshot.confirmedMovementUuids.length);}
});
test('own unresolved server events block drained acknowledgement; registered device deletion cannot bypass barrier',async()=>{
 let session=await open();
 const pending=await prisma.syncEvent.create({data:{companyId,userId,deviceId:a.device.id,eventId:randomUUID(),feature:'caixa',entity:'cashMovement',operation:'create',entityLocalId:randomUUID(),occurredAt:new Date(),payload:{cashEmployeeId:userId,cashSessionUuid:session.uuid},status:'FAILED'}});
 session=(await service.requestClosure(a,session.uuid,{requestId:randomUUID(),expectedRevision:session.revision,countedBalanceCents:1000,localExpectedBalanceCents:1000})).session!;
 await assert.rejects(ack(a,session),{code:'CASH_DEVICE_NOT_DRAINED'});
 await assert.rejects(prisma.companyDevice.delete({where:{id:a.device.id}}),{code:'P2003'});
 await prisma.syncEvent.update({where:{id:pending.id},data:{status:'ACCEPTED'}});
 assert.equal((await ack(a,session)).session!.status,'CLOSED');
 await prisma.syncEvent.delete({where:{id:pending.id}});
});
